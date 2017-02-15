#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::Facebook;
use MediaWords::Util::SQL;

use Encode;
use Readonly;
use Text::CSV_XS;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    Readonly my $sample_size => 1000;

    INFO "Fetching $sample_size random stories from 'story_statistics'...";
    my $sample_stories = $db->query(
        <<SQL,
        SELECT story_statistics.stories_id,
               stories.url AS stories_url,
               stories.publish_date AS stories_publish_date,
               stories.collect_date AS stories_collect_date,
               facebook_share_count AS past_share_count,
               facebook_comment_count AS past_comment_count,
               facebook_api_collect_date::timestamp(0) AS past_stats_collect_date
        FROM story_statistics
            INNER JOIN stories
                ON story_statistics.stories_id = stories.stories_id
            INNER JOIN media
                ON stories.media_id = media.media_id
        WHERE facebook_share_count IS NOT NULL
          AND facebook_comment_count IS NOT NULL
          AND media.name = 'New York Times'
        ORDER BY RANDOM()
        LIMIT ?
SQL
        $sample_size
    )->hashes;

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    $csv->combine(
        'stories_id',              #
        'stories_url',             #
        'stories_publish_date',    #
        'stories_collect_date',    #

        'past_share_count',        #
        'past_comment_count',      #
        'past_stats_collect_date', #

        'present_share_count',           #
        'present_comment_count',         #
        'present_stats_collect_date',    #
    );
    print $csv->string . "\n";

    INFO "Refetching stats for sample of stories...";
    foreach my $sample_story ( @{ $sample_stories } )
    {
        my $stories_id  = $sample_story->{ stories_id };
        my $stories_url = $sample_story->{ stories_url };

        INFO "Refetching stats for story $stories_id ($stories_url)...";
        my ( $present_share_count, $present_comment_count ) =
          MediaWords::Util::Facebook::get_url_share_comment_counts( $db, $stories_url );

        INFO "Present share count: $present_share_count, comment count: $present_comment_count";

        $csv->combine(
            int( $stories_id ),                         #
            $stories_url,                               #
            $sample_story->{ stories_publish_date },    #
            $sample_story->{ stories_collect_date },    #

            int( $sample_story->{ past_share_count } ),      #
            int( $sample_story->{ past_comment_count } ),    #
            $sample_story->{ past_stats_collect_date },      #

            $present_share_count,                            #
            $present_comment_count,                          #
            MediaWords::Util::SQL::sql_now(),                #
        );
        print encode( 'utf8', $csv->string . "\n" );
    }

    INFO "Done refetching stats for sample of stories.";
}

main();
