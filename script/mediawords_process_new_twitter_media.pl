#!/usr/bin/env perl

use strict;

use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::StoryVectors;

sub main
{

    my $db = MediaWords::DB::connect_to_db;

    my $twitter_media_without_feeds = $db->query(
"select media.* from media left join feeds on ( media.media_id = feeds.media_id) where  ( media.url ~ '.*twitter.com/[^/#]+' ) and feeds.feeds_id is null; "
    )->hashes;

    for my $twitter_media_source ( @{ $twitter_media_without_feeds } )
    {
        DEBUG Dumper( $twitter_media_source );

        my $media_source_url = $twitter_media_source->{ url };

        $media_source_url =~ /twitter\.com\/(.*)/;

        my $twitter_user_name = $1;

        DEBUG $twitter_user_name;

        my $feed_url = "https://api.twitter.com/1/statuses/user_timeline.rss?screen_name=$twitter_user_name";

        my $feed = {
            media_id => $twitter_media_source->{ media_id },
            url      => $feed_url,
            name     => $twitter_media_source->{ name },
        };

        $feed = $db->create( 'feeds', $feed );

        say Dumper ( $feed );

        $db->query( " UPDATE media set full_text_rss = true where media_id = ? ", $twitter_media_source->{ media_id } );

        #exit;
    }
}

main();
