#!/usr/bin/env perl

# dedup stories in a given controversy.  should only have to be run on a controversy if the deduping
# code in CM::Mine has changed.

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Getopt::Long;

use MediaWords::CM::Mine;
use MediaWords::DB;
use MediaWords::CM;
use MediaWords::Util::Web;

sub main
{
    my ( $controversy_opt );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $archive_media;

    Getopt::Long::GetOptions( "controversy=s" => \$controversy_opt, "media_id=s@" => \$archive_media ) || return;

    die( "usage: $0 --controversy < controversy id or pattern > --media_id < media_id> " )
      unless ( $controversy_opt && $archive_media );

    my $db = MediaWords::DB::connect_to_db;

    my $controversies = MediaWords::CM::require_controversies_by_opt( $db, $controversy_opt );

    for my $controversy ( @{ $controversies } )
    {
        $db->disconnect;
        $db = MediaWords::DB::connect_to_db;
        print "CONTROVERSY $controversy->{ name } \n";

        #say Dumper ( $controversy );

        for my $media_id ( @{ $archive_media } )
        {
            say STDERR "media_id $media_id";

            my $archive_stories =
              $db->query( "SELECT * from cd.live_stories where media_id in ( ? ) order by stories_id", $media_id )->hashes();

            #say Dumper( $archive_stories );

            my $i = 0;
            for my $archive_story ( @$archive_stories )
            {

                my $original_url =
                  MediaWords::Util::Web::get_original_url_from_momento_archive_url( $archive_story->{ url } );

                if ( !$original_url )
                {
                    say STDERR "could not get original URL for $archive_story->{ url } SKIPPING";
                    next;
                }
                say "Archive: $archive_story->{ url }, Original $original_url ";
                my $medium = MediaWords::CM::Mine::get_spider_medium( $db, $original_url );

                #say Dumper ( $medium );

                $i++;

                say STDERR "setting media_id for story $archive_story->{ stories_id } to $medium->{ media_id } ";

                $db->query(
                    " UPDATE cd.live_stories set media_id = ? where stories_id = ? ",
                    $medium->{ media_id },
                    $archive_story->{ stories_id }
                );

                #last if $i > 3;
            }

        }

        #MediaWords::CM::Mine::dedup_stories( $db, $controversy );
    }
}

main();
