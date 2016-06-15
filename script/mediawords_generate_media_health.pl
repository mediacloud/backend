#!/usr/bin/env perl

# generate media_health table, which contains denormalized results of analytical queries run on
# the media_stats table to enable quick analysis of the health of individual media sources.
#
# also generate a report that includes a summary of overall system health as well as alerts
# for specific media that appear unhealthy

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Getopt::Long;
use Readonly;

use MediaWords::DB;

# weeks are considered unhealthy if they are below $HEALTHY_VOLUME_RATIO * $expected_stories|sentences
Readonly my $HEALTHY_VOLUME_RATIO => 0.25;

Readonly my $START_DATE => '2011-01-01';

# aggregate media_stats into media_stats_weekly table, which is a dense table that includes
# 0 counts for each media source for each week for which there is no data
sub generate_media_stats_weekly
{
    my ( $db ) = @_;

    $db->query( "drop table if exists media_stats_weekly" );

    $db->query( <<SQL );
create table media_stats_weekly as

    with sparse_media_stats_weekly as (
        select date_trunc( 'week', stat_date ) stat_week,
                ms.media_id,
                round( sum( num_stories::numeric ) / 7, 2 ) num_stories,
                round( sum( num_sentences::numeric ) / 7, 2 ) num_sentences
            from media_stats ms
            where
                ms.stat_date between '$START_DATE' and now() and
                ms.media_id in ( select media_id from crawled_media )
            group by ms.media_id, stat_week
    )

    select
            media_id,
            row_number() over ( partition by w.media_id order by num_stories desc ) stories_rank,
            num_stories,
            row_number() over ( partition by w.media_id order by num_sentences desc ) sentences_rank,
            num_sentences,
            stat_week
        from sparse_media_stats_weekly w;
SQL

    $db->query( "create index media_stats_weekly_medium on media_stats_weekly ( media_id )" );
}

# generate media_expected_volume table, which uses the media_stats_weekly table to generate expected
# healthy volume of stories and sentences for each media source, along with the start_date and end_date
# on which the media source had at least $HEALTHY_VOLUME_RATIO volume of the expected volume
sub generate_media_expected_volume
{
    my ( $db ) = @_;

    $db->query( <<SQL );
create temporary table dateless_media_expected_volume as

    with media_expected_stories as (
        select media_id, avg( num_stories ) expected_stories
            from media_stats_weekly where stories_rank <= 20 group by media_id
    ),

    media_expected_sentences as (
        select media_id, avg( num_sentences ) expected_sentences
            from media_stats_weekly where sentences_rank <= 20 group by media_id
    )


    select s.media_id,
                round( s.expected_stories, 2 ) expected_stories,
                round( ss.expected_sentences, 2) expected_sentences
            from media_expected_stories s
                join media_expected_sentences ss on ( s.media_id = ss.media_id
    )
SQL

    $db->query( "drop table if exists media_expected_volume" );

    $db->query( <<SQL );
create table media_expected_volume as

    select
            msw.media_id,
            min( stat_week ) start_date,
            max( stat_week ) end_date,
            min( expected_stories ) expected_stories,
            min( expected_sentences ) expected_sentences
        from media_stats_weekly msw
            join dateless_media_expected_volume mev on ( msw.media_id = mev.media_id )
        where msw.num_stories > ( $HEALTHY_VOLUME_RATIO * ( mev.expected_stories ) ) and
            msw.num_sentences > ( $HEALTHY_VOLUME_RATIO * ( mev.expected_sentences ) ) and
            msw.stat_week between '$START_DATE' and now()
        group by msw.media_id
        order by media_id;
SQL

    $db->query( "create index media_expected_volume_medium on media_expected_volume ( media_id )" );

}

# create a temporary table that exists only of media that have at least one crawled feed
sub create_crawled_media
{
    my ( $db ) = @_;

    $db->query( <<SQL );
create temporary table crawled_media as
    select * from media
        where exists (
            select 1 from feeds where feeds.media_id = media.media_id and name != 'Controversy Spider Feed'
        )
SQL
}

# generate a table of media / weeks for which the coverage was less than
# $HEALTHY_VOLUME_RATIO * expected_stories|sentences
sub generate_media_coverage_gaps
{
    my ( $db ) = @_;

    $db->query( "drop table if exists media_coverage_gaps" );

    $db->query( <<SQL );
create table media_coverage_gaps as
    select
            msw.media_id,
            stat_week,
            num_stories,
            expected_stories,
            num_sentences,
            expected_sentences
        from media_stats_weekly msw
            join media_expected_volume mev on ( msw.media_id = mev.media_id )
        where
            stat_week between mev.start_date and mev.end_date and
            ( msw.num_stories < ( $HEALTHY_VOLUME_RATIO * mev.expected_stories ) or
              msw.num_sentences < ( $HEALTHY_VOLUME_RATIO * mev.expected_sentences ) )
SQL

    # media_stats_weekly is sparse -- it only includes weeks for which there were more than 0
    # stories or sentences for the given media source.  this query inserts as coverage gaps
    # all missing weeks between the start_date and end_date for the given media source
    $db->query( <<SQL );
insert into media_coverage_gaps
    select
            m.media_id,
            weeks.stat_week,
            0 num_stories,
            expected_stories,
            0 num_sentences,
            expected_sentences
        from
            ( media m
              cross join generate_series ( date_trunc( 'week', '$START_DATE'::timestamp ), now(), interval '7 days' )
                as weeks( stat_week ) )
            join media_expected_volume mev on ( m.media_id = mev.media_id )
            left join media_stats_weekly msw on ( msw.media_id = m.media_id and msw.stat_week = weeks.stat_week )
        where
            weeks.stat_week between mev.start_date and mev.end_date and
            msw.num_stories is null
SQL

    $db->query( "create index media_coverage_gaps_medium on media_coverage_gaps ( media_id )" );
}

# create the media_health table by executing big analytical query.
# also generates necessary predicate tables media_stats_weekly, media_expected_volume, and
# media_coverage_gaps tables
sub generate_media_health
{
    my ( $db ) = @_;

    $db->begin();

    # this stops warning messages when running 'drop table if exists' on non-existent tables
    $db->query( 'set client_min_messages=WARNING' );

    $db->query( 'drop table if exists media_health cascade' );

    if ( my $large_work_mem = MediaWords::Util::Config::get_config->{ mediawords }->{ large_work_mem } )
    {
        $db->query( 'set work_mem = ?', $large_work_mem );
    }

    create_crawled_media( $db );

    generate_media_stats_weekly( $db );
    generate_media_expected_volume( $db );

    # note for the following queries that we manually compute the average like this:
    #     round( sum( num_stories::numeric ) / 90, 2 ) num_stories,
    # we do this because the media_stats table is sparse -- it does not include entries
    # for day in which a media source generated no stories / sentences

    $db->query( <<SQL );
create temporary table media_stats_90 as

    with sparse_media_stats_90 as (
        select m.media_id,
                round( sum( num_stories::numeric ) / 90, 2 ) num_stories,
                round( sum( num_sentences::numeric ) / 90, 2 ) num_sentences
            from crawled_media m
                left join media_stats ms on ( ms.media_id = m.media_id )
            where ms.stat_date > now() - interval '90 days'
            group by m.media_id
    )

    select
            m.media_id,
            coalesce( d.num_stories, 0 ) num_stories,
            coalesce( d.num_sentences, 0 ) num_sentences
        from crawled_media m
            left join sparse_media_stats_90 d on ( m.media_id = d.media_id )
SQL

    $db->query( <<SQL );
create temporary table media_stats_week as

with sparse_media_stats_week as (
    select m.media_id,
            round( sum( num_stories::numeric ) / 7, 2 ) num_stories,
            round( sum( num_sentences::numeric ) / 7, 2 ) num_sentences
        from crawled_media m
            left join media_stats ms on ( ms.media_id = m.media_id )
        where ms.stat_date > now() - interval '1 week'
        group by m.media_id
)

select
        m.media_id,
        coalesce( w.num_stories, 0 ) num_stories,
        coalesce( w.num_sentences, 0 ) num_sentences
    from crawled_media m
        left join sparse_media_stats_week w on ( m.media_id = w.media_id )
SQL

    $db->query( <<SQL );
create temporary table media_stats_year as

        with sparse_media_stats_year as (
            select m.media_id,
                    round( sum( num_stories::numeric ) / 365, 2 ) num_stories,
                    round( sum( num_sentences::numeric ) / 365, 2 ) num_sentences
                from crawled_media m
                    left join media_stats ms on ( ms.media_id = m.media_id )
                where ms.stat_date > now() - interval '365 days'
                group by m.media_id
        )

        select
                m.media_id,
                coalesce( d.num_stories, 0 ) num_stories,
                coalesce( d.num_sentences, 0 ) num_sentences
            from crawled_media m
                left join sparse_media_stats_year d on ( m.media_id = d.media_id )
SQL

    $db->query( <<SQL );
create temporary table media_stats_0 as
    select m.media_id,
            coalesce( ms.num_stories, 0 ) num_stories,
            coalesce( ms.num_sentences, 0 ) num_sentences
        from crawled_media m
            left join media_stats ms on (
                ms.media_id = m.media_id  and
                ms.stat_date = date_trunc( 'day', now() - interval '1 day' )
            )
SQL

    $db->query( <<SQL );
create temporary table media_coverage_gap_counts as
    select media_id, count(*) coverage_gaps
        from media_coverage_gaps
        group by media_id
SQL

    $db->query( <<SQL );
create table media_health as

    select m.media_id,
            ms0.num_stories,
            msy.num_stories num_stories_y,
            msw.num_stories num_stories_w,
            ms90.num_stories num_stories_90,
            ms0.num_sentences,
            msy.num_sentences num_sentences_y,
            msw.num_sentences num_sentences_w,
            ms90.num_sentences num_sentences_90,
            'false'::boolean is_healthy,
            'true'::boolean has_active_feed,
            mev.start_date,
            mev.end_date,
            mev.expected_sentences,
            mev.expected_stories,
            coalesce( mcg.coverage_gaps, 0 ) coverage_gaps
        from crawled_media m
            join media_stats_0 ms0 on ( m.media_id = ms0.media_id )
            join media_stats_90 ms90 on ( m.media_id = ms90.media_id )
            join media_stats_year msy on ( m.media_id = msy.media_id )
            join media_stats_week msw on ( m.media_id = msw.media_id )
            join media_expected_volume mev on ( m.media_id = mev.media_id )
            left join media_coverage_gap_counts mcg on ( m.media_id = mcg.media_id )
SQL

    $db->query( "create index media_health_medium on media_health ( media_id )" );

    $db->query( "analyze media_health" );

    generate_media_coverage_gaps( $db );

    $db->commit;
}

# set is_health and has_active_feed for media_health table
sub update_media_health_status
{
    my ( $db ) = @_;

    # only check the single day during the week day
    my $wday = ( localtime( time() - 86400 ) )[ 6 ];

    my $is_weekend = grep { $wday == $_ } ( 0, 6 );

    $db->query( "update media_health mh set is_healthy = 't'" );
    $db->query( <<SQL );
update media_health set is_healthy = 'f'
    where
        ( ( num_stories_90 > 10 ) and
          ( ( ( num_stories_w / greatest( num_stories_y, 1 ) ) < $HEALTHY_VOLUME_RATIO ) or
            ( ( num_stories_w / greatest( num_stories_90, 1 ) ) < $HEALTHY_VOLUME_RATIO ) or
            ( ( num_sentences_w / greatest( num_sentences_y, 1 ) ) < $HEALTHY_VOLUME_RATIO ) or
            ( ( num_sentences_w / greatest( num_sentences_90, 1 ) ) < $HEALTHY_VOLUME_RATIO )
          )
        )
        or
        ( num_sentences_90 = 0 )

SQL

    $db->query( "update media_health mh set has_active_feed = 'f'" );
    $db->query( <<SQL );
update media_health mh set has_active_feed = 't'
    where
        num_stories_90 > 1 or
        (
            num_sentences_90 > 0 and
            exists (
                select 1
                    from feeds f
                        join feeds_stories_map fsm on ( f.feeds_id = fsm.feeds_id )
                    where
                        feed_status = 'active' and
                        feed_type = 'syndicated' and
                        f.media_id = mh.media_id
            )
        )
SQL
}

# print some summary health statistics and a list of unhealthy media
sub print_health_report
{
    my ( $db ) = @_;

    my $mhs = $db->query( <<SQL )->hash;
select
        round( sum( num_stories::numeric ), 2 ) num_stories,
        round( sum( num_stories_y::numeric ), 2 ) num_stories_y,
        round( sum( num_stories_w::numeric ), 2 ) num_stories_w,
        round( sum( num_stories_90::numeric ), 2 ) num_stories_90,
        round( sum( num_sentences::numeric ), 2 ) num_sentences,
        round( sum( num_sentences_y::numeric ), 2 ) num_sentences_y,
        round( sum( num_sentences_w::numeric ), 2 ) num_sentences_w,
        round( sum( num_sentences_90::numeric ), 2 ) num_sentences_90
    from media_health
SQL

    my $unhealthy_media = $db->query( <<SQL )->hashes;
select m.*, mh.*, t.tags_id
    from crawled_media m
        join media_health mh on ( m.media_id = mh.media_id )
        left join
            ( media_tags_map mtm
                join tags t on ( mtm.tags_id = t.tags_id and t.tag = 'ap_english_us_top25_20100110' )
                join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id and ts.name = 'collection' )
            ) on mh.media_id = mtm.media_id
    where
        not mh.is_healthy
    order by t.tags_id is not null desc, num_stories_90 desc, num_stories_y desc
    limit 50
SQL

    print <<END;
SUMMARY

stories (0, w, 90, y)   - $mhs->{ num_stories }, $mhs->{ num_stories_w }, $mhs->{ num_stories_90 }, $mhs->{ num_stories_y }
sentences (0, w, 90, y) - $mhs->{ num_sentences }, $mhs->{ num_sentences_w }, $mhs->{ num_sentences_90 }, $mhs->{ num_sentences_y }

TOP 50 UNHEALTHY MEDIA

END

    for my $m ( @{ $unhealthy_media } )
    {
        print <<END;
$m->{ name } [https://core.mediacloud.org/admin/health/medium/$m->{ media_id }]:
    stories (0, w, 90, y)   - $m->{ num_stories }, $m->{ num_stories_w }, $m->{ num_stories_90 }, $m->{ num_stories_y }
    sentences (0, w, 90, y) - $m->{ num_sentences }, $m->{ num_sentences_w }, $m->{ num_sentences_90 }, $m->{ num_sentences_y }

END
    }
}

sub main
{
    binmode( STDOUT, ':utf8' );

    my ( $skip_generation ) = @_;

    Getopt::Long::GetOptions( "skip_generation!" => \$skip_generation, ) || return;

    my $db = MediaWords::DB::connect_to_db;

    generate_media_health( $db ) unless ( $skip_generation );

    update_media_health_status( $db );

    print_health_report( $db );
}

main();
