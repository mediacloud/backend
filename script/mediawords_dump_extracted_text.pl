#!/usr/bin/env perl

# generate a dump of extracted html for seas students

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::DBI::DownloadTexts;

# dump us msm, political blogs, and popular blogs
my $_dump_media_sets = [ 1, 26, 725 ];

sub main
{
    my ( $start_date, $end_date ) = @ARGV;

    binmode( STDOUT, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    my $dump_media_sets_list = join( ", ", @{ $_dump_media_sets } );

    my $stories = $db->query( <<END, $start_date, $end_date )->hashes;
select distinct s.* from stories s, media_sets ms, media_sets_media_map msmm
    where s.media_id = msmm.media_id and ms.media_sets_id = msmm.media_sets_id
        and ms.media_sets_id in ( $dump_media_sets_list )
        and s.publish_date between ?::date and ?::date
    order by publish_date
END

    for my $story ( @{ $stories } )
    {
        print "BEGIN STORY: $story->{ stories_id }\n";

        my $download_texts = $db->query( <<END, $story->{ stories_id } )->hashes;
select dt.* from download_texts dt, downloads d
    where dt.downloads_id = d.downloads_id and d.stories_id = ?
END
        for my $download_text ( @{ $download_texts } )
        {
            print "BEGIN DOWNLOAD TEXT: $download_text->{ download_texts_id }\n";
            eval { print MediaWords::DBI::DownloadTexts::get_extracted_html_from_db( $db, $download_text ) . "\n"; };
            print "END DOWNLOAD TEXT: $download_text->{ download_texts_id }\n";
        }

        print "END STORY: $story->{ stories_id }\n";
    }
}

main();
