package MediaWords::DBI::Stats;

#
# Various functions related to the stats table
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

# update the data in the mediacloud_stats data to reflect the state of the systems (total stories, downloads, etc).
sub refresh_stats($)
{
    my ( $db ) = @_;

    my $stats = {};

    ( $stats->{ daily_downloads } ) = $db->query( <<SQL )->flat;
select count(*) as daily_downloads
    from downloads_in_past_day
SQL

    ( $stats->{ daily_stories } ) = $db->query( <<SQL )->flat;
select count(*) as daily_stories
    from stories_collected_in_past_day
SQL

    ( $stats->{ total_stories } ) = $db->query( <<SQL )->flat;
select reltuples::bigint total_stories
    from pg_class c join
        pg_namespace n on ( n.oid = c.relnamespace )
    where
        n.nspname = 'public' and
        c.relname = 'stories'
SQL

    ( $stats->{ total_downloads } ) = $db->query( <<SQL )->flat;
select reltuples::bigint total_downloads
    from pg_class c join
        pg_namespace n on ( n.oid = c.relnamespace )
    where
        n.nspname = 'public' and
        c.relname = 'downloads'
SQL

    ( $stats->{ total_sentences } ) = $db->query( <<SQL )->flat;
select reltuples::bigint total_sentences
    from pg_class c join
        pg_namespace n on ( n.oid = c.relnamespace )
    where
        n.nspname = 'public' and
        c.relname = 'story_sentences'
SQL

    ( $stats->{ active_crawled_feeds } ) = $db->query( <<SQL )->flat;
select count(*) active_crawled_feeds
    from feeds f
    where
        f.type = 'syndicated' and
        f.last_new_story_time > now() - '180 days'::interval
SQL

    ( $stats->{ active_crawled_media } ) = $db->query( <<SQL )->flat;
select count(*) active_crawled_media
    from media m
    where
        media_id in (
            select media_id
                from feeds f
                where
                    f.type = 'syndicated' and
                    f.last_new_story_time > now() - '180 days'::interval
        )
SQL

    $db->begin;

    $db->query( "delete from mediacloud_stats" );

    $db->insert( 'mediacloud_stats', $stats );

    $db->commit;
}

1;
