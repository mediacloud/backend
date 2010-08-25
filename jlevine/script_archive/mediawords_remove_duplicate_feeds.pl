#!/usr/bin/perl

# use Feed::Scrape::normalize_feed_url to normalized feed urls and then remove any duplicate feeds from each media source

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Feed::Scrape;
use MediaWords::DB;

sub main
{
    my $db = MediaWords::DB::connect_to_db;
    $db->dbh->{ AutoCommit } = 0;

    my $media = $db->query( "select * from media where moderated = false order by media_id" )->hashes;

    for my $medium ( @{ $media } )
    {
        print "MEDIUM: $medium->{ url }\n";

        my $feeds = $db->query( "select * from feeds where media_id = ? order by feeds_id", $medium->{ media_id } )->hashes;

        my $normalized_feed_lists = {};
        for my $feed ( @{ $feeds } )
        {
            my $normalized_feed_url = Feed::Scrape::normalize_feed_url( $feed->{ url } );
            push( @{ $normalized_feed_lists->{ $normalized_feed_url } }, $feed );
        }

        for my $normalized_feed_list ( values( %{ $normalized_feed_lists } ) )
        {
            my $ignore_feed = shift( @{ $normalized_feed_list } );
            print "IGNORE: $ignore_feed->{ url }\n";
            for my $feed ( @{ $normalized_feed_list } )
            {
                print "DELETE: $feed->{ url }\n";
                $db->query( "delete from feeds where feeds_id = ?", $feed->{ feeds_id } );
            }
        }

        $db->commit;
    }

}

main();
