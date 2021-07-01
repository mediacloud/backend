package MediaWords::DBI::Media::Health;

use strict;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME MediaWords::DBI::Media::Health

=head1 DESCRIPTION

generate media_health table, which contains denormalized results of analytical queries run on
the media_stats table to enable quick analysis of the health of individual media sources.

also generate a report that includes a summary of overall system health as well as alerts
for specific media that appear unhealthy

=cut

use Readonly;

# weeks are considered unhealthy if they are below $HEALTHY_VOLUME_RATIO * $expected_stories|sentences
Readonly my $HEALTHY_VOLUME_RATIO => 0.25;

Readonly my $START_DATE => '2011-01-01';

# udpate media_stats table with all sentences since the last time we ran this function
sub _update_media_stats
{
    my ( $db ) = @_;

    my ( $ss_id ) = $db->query( <<SQL,
        SELECT value
        FROM database_variables
        WHERE name = 'media_health_last_ss_id'
SQL
    )->flat;
    $ss_id = defined( $ss_id ) ? int( $ss_id ) : 0;

    my ( $max_ss_id ) = $db->query( "SELECT MAX(story_sentences_id) FROM story_sentences" )->flat;
    $max_ss_id = defined( $max_ss_id ) ? int( $max_ss_id ) : 0;
    
    $db->query( <<SQL
        INSERT INTO media_stats AS old (
            media_id,
            num_stories,
            num_sentences,
            stat_date
        )

            SELECT
                media_id,
                COUNT(DISTINCT stories_id) AS num_stories,
                COUNT(DISTINCT story_sentences_id) AS num_sentences,
                date_trunc('day', publish_date) AS stat_date
            FROM story_sentences AS ss
            where
                ss.story_sentences_id BETWEEN $ss_id AND $max_ss_id AND
                ss.publish_date IS NOT NULL
            GROUP BY
                media_id,
                stat_date

        ON CONFLICT (media_id, stat_date) DO UPDATE SET
            num_stories = old.num_stories + EXCLUDED.num_stories, 
            num_sentences = old.num_sentences + EXCLUDED.num_sentences
SQL
    );

    $db->query( <<SQL
        INSERT INTO database_variables (name, value)
        VALUES ('media_health_last_ss_id', $max_ss_id)
        ON CONFLICT (name) DO UPDATE SET
            value = EXCLUDED.value
SQL
    );

}

# aggregate media_stats into media_stats_weekly table, which is a dense table that includes
# 0 counts for each media source for each week for which there is no data
sub _generate_media_stats_weekly
{
    my ( $db ) = @_;

    $db->begin;

    $db->query( "DELETE FROM media_stats_weekly" );

    $db->query( <<SQL
        INSERT INTO media_stats_weekly (
            media_id,
            stories_rank,
            num_stories,
            sentences_rank,
            num_sentences,
            stat_week
        )

            WITH sparse_media_stats_weekly AS (
                SELECT
                    date_trunc('week', stat_date) AS stat_week,
                    ms.media_id,
                    ROUND(SUM(num_stories::numeric) / 7, 2 ) AS num_stories,
                    ROUND(SUM(num_sentences::numeric) / 7, 2 ) AS num_sentences
                FROM media_stats AS ms
                WHERE
                    ms.stat_date BETWEEN '$START_DATE' AND NOW() AND
                    ms.media_id IN (
                        SELECT media_id
                        FROM crawled_media
                    )
                GROUP BY
                    ms.media_id,
                    stat_week
            )

            SELECT
                media_id,
                ROW_NUMBER() OVER (PARTITION BY w.media_id ORDER BY num_stories DESC) AS stories_rank,
                num_stories,
                ROW_NUMBER() OVER (PARTITION BY w.media_id ORDER BY num_sentences DESC) AS sentences_rank,
                num_sentences,
                stat_week
            FROM sparse_media_stats_weekly AS w
SQL
    );

    $db->commit;

}

# generate media_expected_volume table, which uses the media_stats_weekly table to generate expected
# healthy volume of stories and sentences for each media source, along with the start_date and end_date
# on which the media source had at least $HEALTHY_VOLUME_RATIO volume of the expected volume
sub _generate_media_expected_volume
{
    my ( $db ) = @_;

    $db->query( <<SQL
        CREATE TEMPORARY TABLE dateless_media_expected_volume AS

            WITH media_expected_stories AS (
                SELECT
                    media_id,
                    AVG(num_stories) AS expected_stories
                FROM media_stats_weekly
                WHERE stories_rank <= 20
                GROUP BY media_id
            ),

            media_expected_sentences AS (
                SELECT
                    media_id,
                    AVG(num_sentences) AS expected_sentences
                FROM media_stats_weekly
                WHERE sentences_rank <= 20
                GROUP BY media_id
            )

            SELECT
                s.media_id,
                ROUND(s.expected_stories::numeric, 2) AS expected_stories,
                ROUND(ss.expected_sentences::numeric, 2) AS expected_sentences
            FROM media_expected_stories AS s
                INNER JOIN media_expected_sentences AS ss ON
                    s.media_id = ss.media_id
SQL
    );

    $db->begin;

    $db->query( "DELETE FROM media_expected_volume" );

    $db->query( <<SQL
        INSERT INTO media_expected_volume (
            media_id,
            start_date,
            end_date,
            expected_stories,
            expected_sentences
        )

            SELECT
                msw.media_id,
                MIN(stat_week) AS start_date,
                MAX(stat_week) AS end_date,
                MIN(expected_stories) AS expected_stories,
                MIN(expected_sentences) AS expected_sentences
            FROM media_stats_weekly AS msw
                INNER JOIN dateless_media_expected_volume AS mev ON
                    msw.media_id = mev.media_id
            WHERE
                msw.num_stories > ($HEALTHY_VOLUME_RATIO * mev.expected_stories) AND
                msw.num_sentences > ($HEALTHY_VOLUME_RATIO * mev.expected_sentences) AND
                msw.stat_week BETWEEN '$START_DATE' AND NOW()
            GROUP BY msw.media_id
            ORDER BY media_id
SQL
    );

    $db->commit;

}

# create a temporary table that exists only of media that have at least one crawled feed
sub _create_crawled_media
{
    my ( $db ) = @_;

    $db->query( <<SQL
        CREATE TEMPORARY TABLE crawled_media AS
            SELECT *
            FROM media
            WHERE EXISTS (
                SELECT 1
                FROM feeds
                WHERE
                    feeds.media_id = media.media_id AND
                    name != 'Topic Spider Feed'
            )
SQL
    );
}

# generate a table of media / weeks for which the coverage was less than
# $HEALTHY_VOLUME_RATIO * expected_stories|sentences
sub _generate_media_coverage_gaps
{
    my ( $db ) = @_;

    $db->begin;

    $db->query( "DELETE FROM media_coverage_gaps" );

    $db->query( <<SQL
        INSERT INTO media_coverage_gaps (
            media_id,
            stat_week,
            num_stories,
            expected_stories,
            num_sentences,
            expected_sentences
        )
            SELECT
                msw.media_id,
                stat_week,
                num_stories,
                expected_stories,
                num_sentences,
                expected_sentences
            FROM media_stats_weekly AS msw
                INNER JOIN media_expected_volume AS mev ON
                    msw.media_id = mev.media_id
            WHERE
                stat_week BETWEEN mev.start_date AND mev.end_date AND
                (
                    msw.num_stories < ($HEALTHY_VOLUME_RATIO * mev.expected_stories) OR
                    msw.num_sentences < ($HEALTHY_VOLUME_RATIO * mev.expected_sentences)
                )
SQL
    );

    # media_stats_weekly is sparse -- it only includes weeks for which there were more than 0
    # stories or sentences for the given media source.  this query inserts as coverage gaps
    # all missing weeks between the start_date and end_date for the given media source
    $db->query( <<SQL
        insert into media_coverage_gaps (
            media_id,
            stat_week,
            num_stories,
            expected_stories,
            num_sentences,
            expected_sentences
        )
            SELECT
                m.media_id,
                weeks.stat_week,
                0 AS num_stories,
                expected_stories,
                0 AS num_sentences,
                expected_sentences
            FROM (
                media AS m
                    CROSS JOIN generate_series (
                        date_trunc('week', '$START_DATE'::timestamp),
                        NOW(),
                        INTERVAL '7 days'
                    ) AS weeks(stat_week)
            )
                INNER JOIN media_expected_volume AS mev ON
                    m.media_id = mev.media_id
                LEFT JOIN media_stats_weekly AS msw ON
                    msw.media_id = m.media_id AND
                    msw.stat_week = weeks.stat_week
            WHERE
                weeks.stat_week BETWEEN mev.start_date AND mev.end_date AND
                msw.num_stories IS NULL
SQL
    );

    $db->commit;
}

# create the media_health table by executing big analytical query.
# also generates necessary predicate tables media_stats_weekly, media_expected_volume, and
# media_coverage_gaps tables
sub _generate_media_health_table
{
    my ( $db ) = @_;

    _create_crawled_media( $db );

    _update_media_stats( $db );

    _generate_media_stats_weekly( $db );
    _generate_media_expected_volume( $db );

    # note for the following queries that we manually compute the average like this:
    #     round( sum( num_stories::numeric ) / 90, 2 ) num_stories,
    # we do this because the media_stats table is sparse -- it does not include entries
    # for day in which a media source generated no stories / sentences

    $db->query( <<SQL
        CREATE TEMPORARY TABLE media_stats_90 AS

            WITH sparse_media_stats_90 AS (
                SELECT
                    m.media_id,
                    ROUND(SUM(num_stories::numeric) / 90, 2) AS num_stories,
                    ROUND(SUM(num_sentences::numeric) / 90, 2) AS num_sentences
                FROM crawled_media AS m
                    LEFT JOIN media_stats AS ms ON
                        ms.media_id = m.media_id
                WHERE ms.stat_date > NOW() - INTERVAL '90 days'
                GROUP BY m.media_id
            )

            select
                m.media_id,
                COALESCE(d.num_stories, 0) AS num_stories,
                COALESCE(d.num_sentences, 0) AS num_sentences
            from crawled_media AS m
                LEFT JOIN sparse_media_stats_90 AS d ON
                    m.media_id = d.media_id
SQL
    );

    $db->query( <<SQL
        CREATE TEMPORARY TABLE media_stats_week AS

            WITH sparse_media_stats_week AS (
                SELECT
                    m.media_id,
                    ROUND(SUM(num_stories::numeric) / 7, 2) AS num_stories,
                    ROUND(SUM(num_sentences::numeric) / 7, 2) AS num_sentences
                FROM crawled_media AS m
                    LEFT JOIN media_stats AS ms ON
                        ms.media_id = m.media_id
                WHERE ms.stat_date > NOW() - INTERVAL '1 week'
                GROUP BY m.media_id
            )

            SELECT
                m.media_id,
                COALESCE(w.num_stories, 0) AS num_stories,
                COALESCE(w.num_sentences, 0) AS num_sentences
            FROM crawled_media AS m
                LEFT JOIN sparse_media_stats_week AS w ON
                    m.media_id = w.media_id
SQL
    );

    $db->query( <<SQL
        CREATE TEMPORARY TABLE media_stats_year AS

            WITH sparse_media_stats_year AS (
                SELECT
                    m.media_id,
                    ROUND(SUM(num_stories::numeric) / 365, 2) AS num_stories,
                    ROUND(SUM(num_sentences::numeric) / 365, 2) AS num_sentences
                FROM crawled_media AS m
                    LEFT JOIN media_stats AS ms ON
                        ms.media_id = m.media_id
                WHERE ms.stat_date > NOW() - INTERVAL '365 days'
                GROUP BY m.media_id
            )

            SELECT
                m.media_id,
                COALESCE(d.num_stories, 0) AS num_stories,
                COALESCE(d.num_sentences, 0) AS num_sentences
            FROM crawled_media AS m
                LEFT JOIN sparse_media_stats_year AS d ON
                    m.media_id = d.media_id
SQL
    );

    $db->query( <<SQL
        CREATE TEMPORARY TABLE media_stats_0 AS
            SELECT
                m.media_id,
                COALESCE(ms.num_stories, 0) AS num_stories,
                COALESCE(ms.num_sentences, 0) AS num_sentences
            FROM crawled_media AS m
                LEFT JOIN media_stats AS ms ON
                    ms.media_id = m.media_id AND
                    ms.stat_date = date_trunc('day', NOW() - INTERVAL '1 day'
SQL
    );

    $db->query( <<SQL
        CREATE TEMPORARY TABLE media_coverage_gap_counts AS
            SELECT
                media_id,
                COUNT(*) AS coverage_gaps
            FROM media_coverage_gaps
            GROUP BY media_id
SQL
    );

    $db->begin;

    $db->query( 'DELETE FROM media_health' );

    $db->query( <<SQL
        insert into media_health (
            media_id,
            num_stories,
            num_stories_y,
            num_stories_w,
            num_stories_90,
            num_sentences,
            num_sentences_y,
            num_sentences_w,
            num_sentences_90,
            is_healthy,
            has_active_feed,
            start_date,
            end_date,
            expected_sentences,
            expected_stories,
            coverage_gaps
        )
            SELECT
                m.media_id,
                ms0.num_stories,
                msy.num_stories AS num_stories_y,
                msw.num_stories AS num_stories_w,
                ms90.num_stories AS num_stories_90,
                ms0.num_sentences,
                msy.num_sentences AS num_sentences_y,
                msw.num_sentences AS num_sentences_w,
                ms90.num_sentences AS num_sentences_90,
                'false'::boolean AS is_healthy,
                'true'::boolean AS has_active_feed,
                mev.start_date,
                mev.end_date,
                mev.expected_sentences,
                mev.expected_stories,
                COALESCE(mcg.coverage_gaps, 0) AS coverage_gaps
            FROM crawled_media AS m
                INNER JOIN media_stats_0 AS ms0 ON
                    m.media_id = ms0.media_id
                INNER JOIN media_stats_90 ms90 ON
                    m.media_id = ms90.media_id
                INNER JOIN media_stats_year AS msy ON
                    m.media_id = msy.media_id
                INNER JOIN media_stats_week AS msw ON
                    m.media_id = msw.media_id
                INNER JOIN media_expected_volume AS mev ON
                    m.media_id = mev.media_id
                LEFT JOIN media_coverage_gap_counts AS mcg ON
                    m.media_id = mcg.media_id
SQL
    );

    $db->commit;

    $db->query( "ANALYZE media_health" );

    _generate_media_coverage_gaps( $db );

}

=head2 update_media_health_status

Set is_health and has_active_feed fields in media_health table according to the current media_health data.

=cut

sub update_media_health_status
{
    my ( $db ) = @_;

    # only check the single day during the week day
    my $wday = ( localtime( time() - 86400 ) )[ 6 ];

    my $is_weekend = grep { $wday == $_ } ( 0, 6 );

    $db->query( "UPDATE media_health SET is_healthy = 't'" );
    $db->query( <<SQL
        UPDATE media_health SET
            is_healthy = 'f'
        WHERE
            (
                num_stories_90 > 10 AND
                (
                    num_stories_w / GREATEST(num_stories_y, 1) < $HEALTHY_VOLUME_RATIO OR
                    num_stories_w / GREATEST(num_stories_90, 1) < $HEALTHY_VOLUME_RATIO OR
                    num_sentences_w / GREATEST(num_sentences_y, 1) < $HEALTHY_VOLUME_RATIO OR
                    num_sentences_w / GREATEST(num_sentences_90, 1) < $HEALTHY_VOLUME_RATIO
                )
            ) OR
            num_sentences_90 = 0
SQL
    );

    $db->query( "UPDATE media_health SET has_active_feed = 'f'" );
    $db->query( <<SQL
        UPDATE media_health AS mh SET
            has_active_feed = 't'
        WHERE
            num_stories_90 > 1 OR
            (
                num_sentences_90 > 0 AND
                EXISTS (
                    SELECT 1
                    FROM feeds AS f
                        INNER JOIN feeds_stories_map AS fsm ON
                            f.feeds_id = fsm.feeds_id
                    WHERE
                        active = 't' AND
                        type = 'syndicated' AND
                        f.media_id = mh.media_id
                )
            )
SQL
    );
}

=head2 print_health_report( $db )

Print a report on the current health of the system and any unhelthy sources.

=cut

sub print_health_report
{
    my ( $db ) = @_;

    my $mhs = $db->query( <<SQL
        SELECT
            ROUND(SUM(num_stories::numeric), 2) AS num_stories,
            ROUND(SUM(num_stories_y::numeric), 2) AS num_stories_y,
            ROUND(SUM(num_stories_w::numeric), 2) AS num_stories_w,
            ROUND(SUM(num_stories_90::numeric), 2) AS num_stories_90,
            ROUND(SUM(num_sentences::numeric), 2) AS num_sentences,
            ROUND(SUM(num_sentences_y::numeric), 2) AS num_sentences_y,
            ROUND(SUM(num_sentences_w::numeric), 2) AS num_sentences_w,
            ROUND(SUM(num_sentences_90::numeric), 2) AS num_sentences_90
        FROM media_health
SQL
    )->hash;

    my $unhealthy_media = $db->query( <<SQL
        SELECT
            m.*,
            mh.*,
            t.tags_id
        FROM crawled_media AS m
            INNER JOIN media_health AS mh ON
                m.media_id = mh.media_id
            LEFT JOIN (
                media_tags_map AS mtm
                    INNER JOIN tags AS t ON
                        mtm.tags_id = t.tags_id AND
                        t.tag = 'ap_english_us_top25_20100110'
                    INNER JOIN tag_sets AS ts ON
                        t.tag_sets_id = ts.tag_sets_id AND
                        ts.name = 'collection'
            ) ON
                mh.media_id = mtm.media_id
        WHERE NOT mh.is_healthy
        ORDER BY
            t.tags_id IS NOT NULL DESC,
            num_stories_90 DESC,
            num_stories_y DESC
        LIMIT 50
SQL
    )->hashes;

    print <<END;
SUMMARY

stories (0, w, 90, y)   - $mhs->{ num_stories }, $mhs->{ num_stories_w }, $mhs->{ num_stories_90 }, $mhs->{ num_stories_y }
sentences (0, w, 90, y) - $mhs->{ num_sentences }, $mhs->{ num_sentences_w }, $mhs->{ num_sentences_90 }, $mhs->{ num_sentences_y }

TOP 50 UNHEALTHY MEDIA

END

    for my $m ( @{ $unhealthy_media } )
    {
        print <<END;
$m->{ name } [$m->{ media_id }]:
    stories (0, w, 90, y)   - $m->{ num_stories }, $m->{ num_stories_w }, $m->{ num_stories_90 }, $m->{ num_stories_y }
    sentences (0, w, 90, y) - $m->{ num_sentences }, $m->{ num_sentences_w }, $m->{ num_sentences_90 }, $m->{ num_sentences_y }

END
    }
}

=head2 generate_media_health( $db )

Regenerate the media health and media_coverage_gaps tables from the data in the daily media_stats table.  Update
the is_healtha and has_active_feed fields in the media_health table.

=cut

sub generate_media_health($;$)
{
    my ( $db ) = @_;

    _generate_media_health_table( $db );

    update_media_health_status( $db );
}

1;
