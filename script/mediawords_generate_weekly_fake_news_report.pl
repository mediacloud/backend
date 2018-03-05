#!/usr/bin/env perl

# generate csv dump of any stories in the fake news collection that appear in the top ten by links, fb,
# or twitter count of any given week of the election topic
use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

Readonly my $ELECTION_TOPICS_ID => 1503;
Readonly my $FAKE_NEWS_TAGS_ID  => 9360532;

#Readonly my $FAKE_NEWS_TAGS_ID => 9360521;

use MediaWords::DB;
use MediaWords::Util::CSV;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $query = <<SQL;
with weekly_timespans as (
    select *
        from timespans
        where
            snapshots_id in (
                select snapshots_id
                    from snapshots
                where
                    topics_id = $ELECTION_TOPICS_ID and
                    state = 'completed'
                order by snapshot_date desc
                limit 1
            ) and
            period = 'weekly' and
            foci_id is null
),

ranked_link_counts as (
    select
            stories_id,
            rank() over ( partition by t.timespans_id order by media_inlink_count desc ) media_inlink_count_rank,
            media_inlink_count,
            rank() over ( partition by t.timespans_id order by inlink_count desc ) inlink_count_rank,
            inlink_count,
            rank() over ( partition by t.timespans_id order by facebook_share_count desc ) facebook_share_count_rank,
            facebook_share_count,
            rank() over ( partition by t.timespans_id order by simple_tweet_count desc ) simple_tweet_count_rank,
            simple_tweet_count,
            timespans_id
    from snap.story_link_counts
        join weekly_timespans t using ( timespans_id )
)

select
        s.stories_id, s.title, s.url, s.publish_date,
        t.timespans_id, t.start_date timespan_week,
        media_inlink_count_rank, media_inlink_count,
        inlink_count_rank, inlink_count,
        facebook_share_count_rank, facebook_share_count,
        simple_tweet_count_rank, simple_tweet_count
    from
        weekly_timespans t
        join ranked_link_counts rlc using ( timespans_id )
        join snap.stories s using( snapshots_id, stories_id )
        join media_tags_map mtm using ( media_id )
    where
        mtm.tags_id = $FAKE_NEWS_TAGS_ID
    order by timespans_id, facebook_share_count_rank
SQL

    print( MediaWords::Util::CSV::get_query_as_csv( $db, $query ) );

}

main();
