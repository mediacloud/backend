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

use MediaWords::DB;

# create the media_health table by executing big analytical query
sub generate_media_health
{
    my ( $db ) = @_;

    $db->begin();

    $db->query( 'set client_min_messages=WARNING; drop table if exists media_health' );

    $db->query( <<SQL );
create table media_health as

with last_90_days as
(
    select day::date, m.media_id
        from media m,
            generate_series( now() - interval '91 days', now() - interval '2 day' , interval '1 day') day

),

media_stats_90 as
(
    select d.media_id,
            round( avg( coalesce( num_stories, 0 ) ), 3 ) num_stories,
            round( avg( coalesce( num_sentences, 0 ) ), 3 ) num_sentences
        from last_90_days d
            left join media_stats ms on ( ms.media_id = d.media_id and ms.stat_date = d.day )
        group by d.media_id
),

last_week as
(
    select day::date, m.media_id
        from media m,
            generate_series( now() - interval '8 days', now() - interval '2 day' , interval '1 day') day

),

media_stats_week as
(
    select d.media_id,
            round( avg( coalesce( num_stories, 0 ) ), 3 ) num_stories,
            round( avg( coalesce( num_sentences, 0 ) ), 3 ) num_sentences
        from last_week d
            left join media_stats ms on ( ms.media_id = d.media_id and ms.stat_date = d.day )
        group by d.media_id
),

last_year as
(
    select day::date, m.media_id
        from media m,
            generate_series( now() - interval '1 year', now() - interval '2 day' , interval '1 day') day

),

media_stats_year as
(
    select d.media_id,
            round( avg( coalesce( num_stories, 0 ) ), 3 ) num_stories,
            round( avg( coalesce( num_sentences, 0 ) ), 3 ) num_sentences
        from last_year d
            left join media_stats ms on ( ms.media_id = d.media_id and ms.stat_date = d.day )
        group by d.media_id
),

media_stats_0 as
(
    select m.media_id,
            coalesce( ms.num_stories, 0 ) num_stories,
            coalesce( ms.num_sentences, 0 ) num_sentences
        from media m
            left join media_stats ms on (
                ms.media_id = m.media_id  and
                ms.stat_date = date_trunc( 'day', now() - interval '1 day' )
            )
)

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
        'true'::boolean has_active_feed

    from media m
        join media_stats_0 ms0 on ( m.media_id = ms0.media_id )
        join media_stats_90 ms90 on ( m.media_id = ms90.media_id )
        join media_stats_year msy on ( m.media_id = msy.media_id )
        join media_stats_week msw on ( m.media_id = msw.media_id )
SQL

    $db->query( "create index media_health_medium on media_health ( media_id )" );

    $db->query( "analyze media_health" );

    $db->commit;
}

# set is_health and has_active_feed for media_health table
sub update_media_health_status
{
    my ( $db ) = @_;

    $db->query( "update media_health mh set is_healthy = 't'" );
    $db->query( <<SQL );
update media_health set is_healthy = 'f'
    where
        ( ( num_stories_90 > 50 ) and
          ( ( ( num_stories / num_stories_y ) < 0.25 ) or
            ( ( num_stories / num_stories_90 ) < 0.25 ) or
            ( ( num_sentences / num_sentences_y ) < 0.25 ) or
            ( ( num_sentences / num_sentences_90 ) < 0.25 )
          )
        )
        or
        ( ( num_stories_90 > 10 ) and
          ( ( ( num_stories_w / num_stories_y ) < 0.25 ) or
            ( ( num_stories_w / num_stories_90 ) < 0.25 ) or
            ( ( num_sentences_w / num_sentences_y ) < 0.25 ) or
            ( ( num_sentences_w / num_sentences_90 ) < 0.25 )
          )
        )
        or
        ( num_stories_90 = 0 )

SQL

    $db->query( "update media_health mh set has_active_feed = 'f'" );
    $db->query( <<SQL );
update media_health mh set has_active_feed = 't'
    where
        num_stories_90 > 1 or
        (
            num_stories_90 > 0 and
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
        round( sum( num_stories ), 0 ) num_stories,
        round( sum( num_stories_y ), 0 ) num_stories_y,
        round( sum( num_stories_w ), 0 ) num_stories_w,
        round( sum( num_stories_90 ), 0 ) num_stories_90,
        round( sum( num_sentences ), 0 ) num_sentences,
        round( sum( num_sentences_y ), 0 ) num_sentences_y,
        round( sum( num_sentences_w ), 0 ) num_sentences_w,
        round( sum( num_sentences_90 ), 0 ) num_sentences_90
    from media_health
SQL

    my $unhealthy_media = $db->query( <<SQL )->hashes;
select m.*, mh.*, t.tags_id
    from media m
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
$m->{ name }:
    stories (0, w, 90, y)   - $m->{ num_stories }, $m->{ num_stories_w }, $m->{ num_stories_90 }, $m->{ num_stories_y }
    sentences (0, w, 90, y) - $m->{ num_sentences }, $m->{ num_sentences_w }, $m->{ num_sentences_90 }, $m->{ num_sentences_y }

END
    }
}

sub main
{
    binmode( STDOUT, ':utf8' );

    my $db = MediaWords::DB::connect_to_db;

    generate_media_health( $db );

    update_media_health_status( $db );

    print_health_report( $db );
}

main();
