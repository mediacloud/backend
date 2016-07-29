#!/usr/bin/env perl

# dedup stories in a given topic.  should only have to be run on a topic if the deduping
# code in TM::Mine has changed.

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;

use MediaWords::TM::Mine;
use MediaWords::DB;
use MediaWords::TM;
use MediaWords::Util::Web;

sub main
{
    my ( $topic_opt );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $archive_media;

    Getopt::Long::GetOptions( "topic=s" => \$topic_opt, "media_id=s@" => \$archive_media ) || return;

    die( "usage: $0 --topic < topic id or pattern > --media_id < media_id> " )
      unless ( $topic_opt && $archive_media );

    my $db = MediaWords::DB::connect_to_db;

    my $topics = MediaWords::TM::require_topics_by_opt( $db, $topic_opt );

    for my $topic ( @{ $topics } )
    {
        $db->disconnect;
        $db = MediaWords::DB::connect_to_db;
        INFO "topic $topic->{ name }";

        TRACE Dumper( $topic );

        for my $media_id ( @{ $archive_media } )
        {
            INFO "media_id $media_id";

            my $archive_stories =
              $db->query( "SELECT * from snap.live_stories where media_id in ( ? ) order by stories_id", $media_id )
              ->hashes();

            TRACE Dumper( $archive_stories );

            my $i = 0;
            for my $archive_story ( @$archive_stories )
            {

                my $original_url =
                  MediaWords::Util::Web::get_original_url_from_momento_archive_url( $archive_story->{ url } );

                if ( !$original_url )
                {
                    WARN "could not get original URL for $archive_story->{ url } SKIPPING";
                    next;
                }
                INFO "Archive: $archive_story->{ url }, Original $original_url ";
                my $medium = MediaWords::TM::Mine::get_spider_medium( $db, $original_url );

                TRACE Dumper( $medium );

                $i++;

                INFO "setting media_id for story $archive_story->{ stories_id } to $medium->{ media_id } ";

                $db->query(
                    " UPDATE snap.live_stories set media_id = ? where stories_id = ? ",
                    $medium->{ media_id },
                    $archive_story->{ stories_id }
                );
            }

        }

    }
}

main();
