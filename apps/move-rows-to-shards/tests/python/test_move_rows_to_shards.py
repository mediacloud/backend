from datetime import timedelta

# noinspection PyPackageRequirements
from typing import Any, Dict

import pytest
# noinspection PyPackageRequirements
from temporal.workerfactory import WorkerFactory
# noinspection PyPackageRequirements
from temporal.workflow import WorkflowOptions

from mediawords.db import connect_to_db, DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.workflow.client import workflow_client
from mediawords.workflow.worker import stop_worker_faster

from move_rows_to_shards.workflow import MoveRowsToShardsWorkflowImpl, MoveRowsToShardsActivitiesImpl
from move_rows_to_shards.workflow_interface import (
    TASK_QUEUE,
    MoveRowsToShardsWorkflow,
    MoveRowsToShardsActivities,
)

log = create_logger(__name__)


# FIXME test duplicate GUIDs at the start of the "stories" table in production

# noinspection SqlNoDataSourceInspection,SqlResolve
def _create_partitions_up_to_maxint(db: DatabaseHandler) -> None:
    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.table_exists(target_table_name VARCHAR)
        RETURNS BOOLEAN AS $$
        DECLARE
            schema_position INT;
            schema VARCHAR;
        BEGIN
            SELECT POSITION('.' IN target_table_name) INTO schema_position;

            IF schema_position = 0 THEN
                schema := CURRENT_SCHEMA();
            ELSE
                schema := SUBSTRING(target_table_name FROM 1 FOR schema_position - 1);
                target_table_name := SUBSTRING(target_table_name FROM schema_position + 1);
            END IF;

            RETURN EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = schema
                  AND table_name = target_table_name
            );

        END;
        $$
        LANGUAGE plpgsql
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.partition_name(
            base_table_name TEXT,
            chunk_size BIGINT,
            object_id BIGINT
        ) RETURNS TEXT AS $$
        DECLARE
            to_char_format CONSTANT TEXT := '00';
            table_name TEXT;
            chunk_number INT;
        BEGIN
            SELECT object_id / chunk_size INTO chunk_number;        
            SELECT base_table_name || '_' || TRIM(leading ' ' FROM TO_CHAR(chunk_number, to_char_format))
                INTO table_name;
            RETURN table_name;
        END;
        $$
        LANGUAGE plpgsql IMMUTABLE
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.partition_by_stories_id_chunk_size()
        RETURNS BIGINT AS $$
        BEGIN
            RETURN 100 * 1000 * 1000;   -- 100m stories in each partition
        END; $$
        LANGUAGE plpgsql IMMUTABLE
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.partition_by_downloads_id_chunk_size()
        RETURNS BIGINT AS $$
        BEGIN
            RETURN 100 * 1000 * 1000;   -- 100m downloads in each partition
        END; $$
        LANGUAGE plpgsql IMMUTABLE
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.partition_by_stories_id_partition_name(
            base_table_name TEXT,
            stories_id BIGINT
        ) RETURNS TEXT AS $$
        BEGIN

            RETURN unsharded_public.partition_name(
                base_table_name := base_table_name,
                chunk_size := unsharded_public.partition_by_stories_id_chunk_size(),
                object_id := stories_id
            );

        END;
        $$
        LANGUAGE plpgsql IMMUTABLE
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.partition_by_downloads_id_partition_name(
            base_table_name TEXT,
            downloads_id BIGINT
        ) RETURNS TEXT AS $$
        BEGIN

            RETURN unsharded_public.partition_name(
                base_table_name := base_table_name,
                chunk_size := unsharded_public.partition_by_downloads_id_chunk_size(),
                object_id := downloads_id
            );

        END;
        $$
        LANGUAGE plpgsql IMMUTABLE
    """)

    # Recreate stories_id / downloads_id helpers for them to create all the partitions
    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.partition_by_stories_id_create_partitions(base_table_name TEXT)
        RETURNS SETOF TEXT AS
        $$
        DECLARE
            chunk_size BIGINT;
            partition_stories_id BIGINT;
            target_table_name TEXT;
            target_table_owner TEXT;
            stories_id_start BIGINT;
            stories_id_end BIGINT;
        BEGIN

            SELECT unsharded_public.partition_by_stories_id_chunk_size() INTO chunk_size;

            SELECT 1 INTO partition_stories_id;
            WHILE partition_stories_id <= 2147483647 LOOP
                SELECT unsharded_public.partition_by_stories_id_partition_name(
                    base_table_name := base_table_name,
                    stories_id := partition_stories_id
                ) INTO target_table_name;
                IF unsharded_public.table_exists('unsharded_public.' || target_table_name) THEN
                    RAISE NOTICE 'Partition "%" for story ID % already exists.', target_table_name, partition_stories_id;
                ELSE
                    RAISE NOTICE 'Creating partition "%" for story ID %', target_table_name, partition_stories_id;

                    SELECT (partition_stories_id / chunk_size) * chunk_size INTO stories_id_start;
                    SELECT LEAST(((partition_stories_id / chunk_size) + 1) * chunk_size, 2147483647) INTO stories_id_end;

                    PERFORM pid
                    FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
                    WHERE backend_type = 'autovacuum worker'
                      AND query ~ 'stories';

                    EXECUTE '
                        CREATE TABLE unsharded_public.' || target_table_name || ' (

                            PRIMARY KEY (' || base_table_name || '_id),

                            -- Partition by stories_id
                            CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id CHECK (
                                stories_id >= ''' || stories_id_start || '''
                            AND stories_id <  ''' || stories_id_end   || ''')

                        ) INHERITS (unsharded_public.' || base_table_name || ');
                    ';

                    SELECT u.usename AS owner
                    FROM information_schema.tables AS t
                        JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
                        JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
                    WHERE t.table_name = base_table_name
                      AND t.table_schema = 'unsharded_public'
                    INTO target_table_owner;

                    EXECUTE 'ALTER TABLE unsharded_public.' || target_table_name || ' OWNER TO ' || target_table_owner || ';';

                    RETURN NEXT target_table_name;

                END IF;

                SELECT partition_stories_id + chunk_size INTO partition_stories_id;
            END LOOP;

            RETURN;

        END;
        $$
        LANGUAGE plpgsql;
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.partition_by_downloads_id_create_partitions(base_table_name TEXT)
        RETURNS SETOF TEXT AS
        $$
        DECLARE
            chunk_size BIGINT;
            partition_downloads_id BIGINT;
            target_table_name TEXT;
            target_table_owner TEXT;
            downloads_id_start BIGINT;
            downloads_id_end BIGINT;
        BEGIN

            SELECT unsharded_public.partition_by_downloads_id_chunk_size() INTO chunk_size;

            SELECT 1 INTO partition_downloads_id;
            WHILE partition_downloads_id <= 2147483647 LOOP
                SELECT unsharded_public.partition_by_downloads_id_partition_name(
                    base_table_name := base_table_name,
                    downloads_id := partition_downloads_id
                ) INTO target_table_name;
                IF unsharded_public.table_exists('unsharded_public.' || target_table_name) THEN
                    RAISE NOTICE 'Partition "%" for download ID % already exists.', target_table_name, partition_downloads_id;
                ELSE
                    RAISE NOTICE 'Creating partition "%" for download ID %', target_table_name, partition_downloads_id;

                    SELECT (partition_downloads_id / chunk_size) * chunk_size INTO downloads_id_start;
                    SELECT LEAST(((partition_downloads_id / chunk_size) + 1) * chunk_size, 2147483647) INTO downloads_id_end;

                    PERFORM pid
                    FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
                    WHERE backend_type = 'autovacuum worker'
                      AND query ~ 'downloads';

                    EXECUTE '
                        CREATE TABLE unsharded_public.' || target_table_name || '
                            PARTITION OF unsharded_public.' || base_table_name || '
                            FOR VALUES FROM (' || downloads_id_start || ')
                                       TO   (' || downloads_id_end   || ');
                    ';

                    SELECT u.usename AS owner
                    FROM information_schema.tables AS t
                        JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
                        JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
                    WHERE t.table_name = base_table_name
                      AND t.table_schema = 'unsharded_public'
                    INTO target_table_owner;

                    EXECUTE '
                        ALTER TABLE unsharded_public.' || target_table_name || '
                            OWNER TO ' || target_table_owner || ';
                    ';

                    RETURN NEXT target_table_name;

                END IF;

                SELECT partition_downloads_id + chunk_size INTO partition_downloads_id;
            END LOOP;

            RETURN;

        END;
        $$
        LANGUAGE plpgsql
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.feeds_stories_map_create_partitions()
        RETURNS VOID AS
        $$
        DECLARE
            created_partitions TEXT[];
            partition TEXT;
        BEGIN

            created_partitions := ARRAY(SELECT unsharded_public.partition_by_stories_id_create_partitions('feeds_stories_map_p'));

            FOREACH partition IN ARRAY created_partitions LOOP

                EXECUTE '
                    CREATE UNIQUE INDEX ' || partition || '_feeds_id_stories_id
                        ON unsharded_public.' || partition || ' (feeds_id, stories_id);

                    CREATE INDEX ' || partition || '_stories_id
                        ON unsharded_public.' || partition || ' (stories_id);
                ';

            END LOOP;

        END;
        $$
        LANGUAGE plpgsql
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.stories_tags_map_create_partitions()
        RETURNS VOID AS
        $$
        DECLARE
            created_partitions TEXT[];
            partition TEXT;
        BEGIN

            created_partitions := ARRAY(SELECT unsharded_public.partition_by_stories_id_create_partitions('stories_tags_map_p'));

            FOREACH partition IN ARRAY created_partitions LOOP

                EXECUTE '
                    ALTER TABLE unsharded_public.' || partition || '

                        -- Unique duplets
                        ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_stories_id_tags_id_unique
                            UNIQUE (stories_id, tags_id);
                ';

            END LOOP;

        END;
        $$
        LANGUAGE plpgsql
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.story_sentences_create_partitions()
        RETURNS VOID AS
        $$
        DECLARE
            created_partitions TEXT[];
            partition TEXT;
        BEGIN

            created_partitions := ARRAY(SELECT unsharded_public.partition_by_stories_id_create_partitions('story_sentences_p'));

            FOREACH partition IN ARRAY created_partitions LOOP

                EXECUTE '
                    CREATE UNIQUE INDEX ' || partition || '_stories_id_sentence_number
                        ON unsharded_public.' || partition || ' (stories_id, sentence_number);

                    CREATE INDEX ' || partition || '_sentence_media_week
                        ON unsharded_public.' || partition || ' (unsharded_public.half_md5(sentence), media_id, unsharded_public.week_start_date(publish_date::date));
                ';

            END LOOP;

        END;
        $$
        LANGUAGE plpgsql
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.downloads_create_subpartitions(base_table_name TEXT)
        RETURNS VOID AS
        $$
        BEGIN
            PERFORM unsharded_public.partition_by_downloads_id_create_partitions(base_table_name);
        END;
        $$
        LANGUAGE plpgsql
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.downloads_success_content_create_partitions()
        RETURNS VOID AS
        $$
        BEGIN
            PERFORM unsharded_public.downloads_create_subpartitions('downloads_success_content');
        END;
        $$
        LANGUAGE plpgsql
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.downloads_success_feed_create_partitions()
        RETURNS VOID AS
        $$
        BEGIN
            PERFORM unsharded_public.downloads_create_subpartitions('downloads_success_feed');
        END;
        $$
        LANGUAGE plpgsql
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.download_texts_create_partitions()
        RETURNS VOID AS
        $$
        BEGIN
            PERFORM unsharded_public.partition_by_downloads_id_create_partitions('download_texts');
        END;
        $$
        LANGUAGE plpgsql
    """)

    db.query("""
        CREATE OR REPLACE FUNCTION unsharded_public.create_missing_partitions()
        RETURNS VOID AS
        $$
        BEGIN
            RAISE NOTICE 'Creating partitions in "downloads_success_content" table...';
            PERFORM unsharded_public.downloads_success_content_create_partitions();

            RAISE NOTICE 'Creating partitions in "downloads_success_feed" table...';
            PERFORM unsharded_public.downloads_success_feed_create_partitions();

            RAISE NOTICE 'Creating partitions in "download_texts" table...';
            PERFORM unsharded_public.download_texts_create_partitions();

            RAISE NOTICE 'Creating partitions in "stories_tags_map_p" table...';
            PERFORM unsharded_public.stories_tags_map_create_partitions();

            RAISE NOTICE 'Creating partitions in "story_sentences_p" table...';
            PERFORM unsharded_public.story_sentences_create_partitions();

            RAISE NOTICE 'Creating partitions in "feeds_stories_map_p" table...';
            PERFORM unsharded_public.feeds_stories_map_create_partitions();

        END;
        $$
        LANGUAGE plpgsql
    """)

    db.query("SELECT * FROM unsharded_public.create_missing_partitions()")


# noinspection SqlNoDataSourceInspection
def _db_create(db: DatabaseHandler, table: str, insert_hash: Dict[str, Any]) -> None:
    """Like _db_create(db=db, ), but doesn't require for the target table to have a primary key."""

    keys = []
    values = []
    for key, value in insert_hash.items():
        keys.append(key)
        values.append("%(" + key + ")s")  # "%(key)s" to be resolved by psycopg2, not Python

    sql = "INSERT INTO %s " % table
    sql += "(%s) " % ", ".join(keys)
    sql += "VALUES (%s) " % ", ".join(values)

    db.query(sql, insert_hash)


def _create_test_unsharded_dataset(db: DatabaseHandler):
    # Insert rows into huge sharded tables with random IDs and huge gaps in between to test out whether chunking works
    row_ids = [
        1,
        10,
        999_999_999,
        1_000_000_000,
        2_147_483_646,
    ]

    for row_id in row_ids:

        _db_create(
            db=db,
            table='unsharded_public.auth_user_request_daily_counts',
            insert_hash={
                'auth_user_request_daily_counts_id': row_id,
                'email': f'test-{row_id}@test.com',
                'day': '2016-10-15',
                'requests_count': 123,
                'requested_items_count': 123,
            }
        )

        _db_create(
            db=db,
            table='public.media',
            insert_hash={
                'media_id': row_id,
                'url': f'https://test/{row_id}',
                'name': f'test-{row_id}',
            }
        )

        _db_create(
            db=db,
            table='unsharded_public.media_stats',
            insert_hash={
                'media_stats_id': row_id,
                'media_id': row_id,
                'num_stories': 123,
                'num_sentences': 123,
                'stat_date': '2016-10-15',
            }
        )

        _db_create(
            db=db,
            table='unsharded_public.media_coverage_gaps',
            insert_hash={
                'media_id': row_id,
                'stat_week': '2016-10-15',
                'num_stories': 123,
                'expected_stories': 123,
                'num_sentences': 123,
                'expected_sentences': 123,
            }
        )

        _db_create(
            db=db,
            table='unsharded_public.stories',
            insert_hash={
                'stories_id': row_id,
                'media_id': row_id,
                'url': f'http://story.test/{row_id}',
                'guid': f'guid://story.test/{row_id}',
                'title': f'story-{row_id}',
                'description': f'description-{row_id}',
                'publish_date': '2016-10-15 08:00:00',
                'collect_date': '2016-10-15 10:00:00',
                'full_text_rss': True,
                'language': 'xx',
            }
        )

        _db_create(
            db=db,
            table='unsharded_public.stories_ap_syndicated',
            insert_hash={
                'stories_ap_syndicated_id': row_id,
                'stories_id': row_id,
                'ap_syndicated': True,
            }
        )

        _db_create(
            db=db,
            table='unsharded_public.story_urls',
            insert_hash={
                'story_urls_id': row_id,
                'stories_id': row_id,
                'url': f'http://story.test/{row_id}',
            }
        )

        _db_create(
            db=db,
            table='public.feeds',
            insert_hash={
                'feeds_id': row_id,
                'media_id': row_id,
                'name': f'feed-{row_id}',
                'url': f'https://test.url/feed-{row_id}',
                'type': 'syndicated',
            }
        )

        _db_create(
            db=db,
            table='unsharded_public.feeds_stories_map_p',
            insert_hash={
                'feeds_stories_map_p_id': row_id,
                'feeds_id': row_id,
                'stories_id': row_id,
            }
        )

        # Delete preloaded tag sets / tags
        # noinspection SqlNoDataSourceInspection,SqlResolve,SqlWithoutWhere
        db.query("DELETE FROM public.timespans")
        # noinspection SqlNoDataSourceInspection,SqlResolve,SqlWithoutWhere
        db.query("DELETE FROM public.tags")
        # noinspection SqlNoDataSourceInspection,SqlResolve,SqlWithoutWhere
        db.query("DELETE FROM public.tag_sets")

        _db_create(
            db=db,
            table='public.tag_sets',
            insert_hash={
                'tag_sets_id': row_id,
                'name': f'test-{row_id}',
            }
        )

        _db_create(
            db=db,
            table='public.tags',
            insert_hash={
                'tags_id': row_id,
                'tag_sets_id': row_id,
                'tag': f'test-{row_id}',
            }
        )

        _db_create(
            db=db,
            table='unsharded_public.stories_tags_map_p',
            insert_hash={
                'stories_tags_map_p_id': row_id,
                'stories_id': row_id,
                'tags_id': row_id,
            }
        )

        _db_create(
            db=db,
            table='unsharded_public.story_sentences_p',
            insert_hash={
                'story_sentences_p_id': row_id,
                'stories_id': row_id,
                'sentence_number': 1,
                'sentence': f'test-{row_id}',
                'media_id': row_id,
                'publish_date': '2016-10-15 08:00:00',
                'language': 'xx',
            }
        )

        _db_create(
            db=db,
            table='unsharded_public.story_statistics',
            insert_hash={
                'story_statistics_id': row_id,
                'stories_id': row_id,
                'facebook_share_count': 123,
                'facebook_comment_count': 123,
                'facebook_reaction_count': 123,
                'facebook_api_collect_date': '2016-10-15 08:00:00',
            }
        )

        _db_create(
            db=db,
            table='unsharded_public.scraped_stories',
            insert_hash={
                'scraped_stories_id': row_id,
                'stories_id': row_id,
                'import_module': 'test',
            }
        )

        _db_create(
            db=db,
            table='unsharded_public.story_enclosures',
            insert_hash={
                'story_enclosures_id': row_id,
                'stories_id': row_id,
                'url': f'https://test.com/test-{row_id}',
            }
        )

        _db_create(
            db=db,
            table='unsharded_public.downloads',
            insert_hash={
                'downloads_id': row_id,
                'feeds_id': row_id,
                'stories_id': row_id,
                'url': f'https://test.com/test-{row_id}',
                'host': 'test.com',
                'type': 'content',
                'state': 'success',
                'path': f'test-{row_id}',
                'priority': 0,
                'sequence': 0,
            },
        )

        _db_create(
            db=db,
            table='unsharded_public.download_texts',
            insert_hash={
                'download_texts_id': row_id,
                'downloads_id': row_id,
                'download_text': 'test',
                'download_text_length': 4,
            },
        )

        _db_create(
            db=db,
            table='public.topics',
            insert_hash={
                'topics_id': row_id,
                'name': f'test-{row_id}',
                'description': f'test-{row_id}',
                'start_date': '2016-10-01',
                'end_date': '2016-10-01',
                'platform': 'web',
                'job_queue': 'mc',
                'max_stories': 10,
            },
        )

        _db_create(
            db=db,
            table='unsharded_public.topic_stories',
            insert_hash={
                'topic_stories_id': row_id,
                'topics_id': row_id,
                'stories_id': row_id,
            },
        )

        _db_create(
            db=db,
            table='unsharded_public.topic_links',
            insert_hash={
                'topic_links_id': row_id,
                'topics_id': row_id,
                'stories_id': row_id,
                'url': f'https://test.com/test-{row_id}',
            },
        )

        _db_create(
            db=db,
            table='unsharded_public.topic_fetch_urls',
            insert_hash={
                'topic_fetch_urls_id': row_id,
                'topics_id': row_id,
                'url': f'https://test.com/test-{row_id}',
                'state': 'test',
            },
        )

        _db_create(
            db=db,
            table='public.topic_seed_queries',
            insert_hash={
                'topic_seed_queries_id': row_id,
                'topics_id': row_id,
                'source': 'mediacloud',
                'platform': 'web',
            },
        )

        _db_create(
            db=db,
            table='public.topic_post_days',
            insert_hash={
                'topic_post_days_id': row_id,
                'topics_id': row_id,
                'topic_seed_queries_id': row_id,
                'day': '2016-10-01',
                'num_posts_stored': 10,
                'num_posts_fetched': 10,
            },
        )

        _db_create(
            db=db,
            table='unsharded_public.topic_posts',
            insert_hash={
                'topic_posts_id': row_id,
                'topic_post_days_id': row_id,
                'data': '{"test": "test"}',
                'post_id': 10,
                'content': f'test-{row_id}',
                'publish_date': '2016-10-01',
                'author': f'test-{row_id}',
                'channel': f'test-{row_id}',
            },
        )

        _db_create(
            db=db,
            table='unsharded_public.topic_post_urls',
            insert_hash={
                'topic_post_urls_id': row_id,
                'topic_posts_id': row_id,
                'url': f'https://test.com/test-{row_id}',
            },
        )

        _db_create(
            db=db,
            table='unsharded_public.topic_seed_urls',
            insert_hash={
                'topic_seed_urls_id': row_id,
                'topics_id': row_id,
            },
        )

        _db_create(
            db=db,
            table='public.snapshots',
            insert_hash={
                'snapshots_id': row_id,
                'topics_id': row_id,
                'snapshot_date': '2016-10-10',
                'start_date': '2016-10-10',
                'end_date': '2016-10-10',
            },
        )

        _db_create(
            db=db,
            table='public.media_tags_map',
            insert_hash={
                'media_tags_map_id': row_id,
                'media_id': row_id,
                'tags_id': row_id,
            },
        )

        _db_create(
            db=db,
            table='public.focal_sets',
            insert_hash={
                'focal_sets_id': row_id,
                'topics_id': row_id,
                'snapshots_id': row_id,
                'name': f'test-{row_id}',
                'focal_technique': 'Boolean Query',
            },
        )

        _db_create(
            db=db,
            table='public.foci',
            insert_hash={
                'foci_id': row_id,
                'topics_id': row_id,
                'focal_sets_id': row_id,
                'name': f'test-{row_id}',
                'arguments': '{"test": "test"}',
            },
        )

        _db_create(
            db=db,
            table='public.timespans',
            insert_hash={
                'timespans_id': row_id,
                'topics_id': row_id,
                'snapshots_id': row_id,
                'foci_id': row_id,
                'start_date': '2016-10-01',
                'end_date': '2016-10-01',
                'period': 'overall',
                'story_count': 123,
                'story_link_count': 123,
                'medium_count': 123,
                'medium_link_count': 123,
                'post_count': 123,
                'tags_id': row_id,
            },
        )

        _db_create(
            db=db,
            table='unsharded_snap.timespan_posts',
            insert_hash={
                'topic_posts_id': row_id,
                'timespans_id': row_id,
            },
        )

        # Add a few duplicates to a couple of tables to make sure that those
        # tables gets deduplicated while moving rows
        duplicate_count = 3
        for duplicate_num in range(duplicate_count):
            _db_create(
                db=db,
                table='unsharded_public.solr_import_stories',
                insert_hash={
                    'stories_id': row_id,
                },
            )
            _db_create(
                db=db,
                table='unsharded_public.solr_imported_stories',
                insert_hash={
                    'stories_id': row_id,
                    'import_date': '2016-10-15 08:00:00',
                },
            )
            _db_create(
                db=db,
                table='unsharded_public.processed_stories',
                insert_hash={
                    'processed_stories_id': (duplicate_count * duplicate_num) + row_id,
                    'stories_id': row_id,
                },
            )

            _db_create(
                db=db,
                table='unsharded_snap.stories',
                insert_hash={
                    'snapshots_id': row_id,
                    'stories_id': row_id,
                    'media_id': row_id,
                    'url': f'https://test.com/test-{row_id}',
                    'guid': f'https://test.com/test-{row_id}',
                    'title': f'test-{row_id}',
                    'collect_date': '2016-10-01',
                },
            )

            _db_create(
                db=db,
                table='unsharded_snap.topic_stories',
                insert_hash={
                    'snapshots_id': row_id,
                    'topic_stories_id': row_id,
                    'topics_id': row_id,
                    'stories_id': row_id,
                },
            )

            _db_create(
                db=db,
                table='unsharded_snap.topic_links_cross_media',
                insert_hash={
                    'snapshots_id': row_id,
                    'topic_links_id': row_id,
                    'topics_id': row_id,
                    'stories_id': row_id,
                    'url': f'https://test.com/test-{row_id}',
                },
            )

            _db_create(
                db=db,
                table='unsharded_snap.media',
                insert_hash={
                    'snapshots_id': row_id,
                    'media_id': row_id,
                    'url': f'https://test.com/test-{row_id}',
                    'name': f'test-{row_id}',
                },
            )

            _db_create(
                db=db,
                table='unsharded_snap.media_tags_map',
                insert_hash={
                    'snapshots_id': row_id,
                    'media_tags_map_id': row_id,
                    'media_id': row_id,
                    'tags_id': row_id,
                },
            )

            _db_create(
                db=db,
                table='unsharded_snap.stories_tags_map',
                insert_hash={
                    'snapshots_id': row_id,
                    'stories_tags_map_id': row_id,
                    'stories_id': row_id,
                    'tags_id': row_id,
                },
            )

            _db_create(
                db=db,
                table='unsharded_snap.story_links',
                insert_hash={
                    'timespans_id': row_id,
                    'source_stories_id': row_id,
                    'ref_stories_id': row_id,
                },
            )

            _db_create(
                db=db,
                table='unsharded_snap.story_link_counts',
                insert_hash={
                    'timespans_id': row_id,
                    'stories_id': row_id,
                    'media_inlink_count': 123,
                    'inlink_count': 123,
                    'outlink_count': 123,
                },
            )

            _db_create(
                db=db,
                table='unsharded_snap.medium_link_counts',
                insert_hash={
                    'timespans_id': row_id,
                    'media_id': row_id,
                    'sum_media_inlink_count': 123,
                    'media_inlink_count': 123,
                    'inlink_count': 123,
                    'outlink_count': 123,
                    'story_count': 123,
                },
            )

            _db_create(
                db=db,
                table='unsharded_snap.medium_links',
                insert_hash={
                    'timespans_id': row_id,
                    'source_media_id': row_id,
                    'ref_media_id': row_id,
                    'link_count': 123,
                },
            )

    for source_stories_id in row_ids:
        for target_stories_id in row_ids:

            # Add a few duplicates to make sure that the table gets deduplicated while moving rows
            for _ in range(3):
                _db_create(
                    db=db,
                    table='unsharded_public.topic_merged_stories_map',
                    insert_hash={
                        'source_stories_id': source_stories_id,
                        'target_stories_id': target_stories_id,
                    },
                )


@pytest.mark.asyncio
async def test_workflow():
    db = connect_to_db()

    _create_partitions_up_to_maxint(db)

    _create_test_unsharded_dataset(db)

    client = workflow_client()

    # Start worker
    factory = WorkerFactory(client=client, namespace=client.namespace)
    worker = factory.new_worker(task_queue=TASK_QUEUE)

    worker.register_activities_implementation(
        activities_instance=MoveRowsToShardsActivitiesImpl(),
        activities_cls_name=MoveRowsToShardsActivities.__name__,
    )
    worker.register_workflow_implementation_type(impl_cls=MoveRowsToShardsWorkflowImpl)
    factory.start()

    # Initialize workflow instance
    workflow: MoveRowsToShardsWorkflow = client.new_workflow_stub(
        cls=MoveRowsToShardsWorkflow,
        workflow_options=WorkflowOptions(
            workflow_id='move_rows_to_shards',

            # By default, if individual activities of the workflow fail, they will get restarted pretty much
            # indefinitely, and so this test might run for days (or rather just timeout on the CI). So we cap the
            # workflow so that if it doesn't manage to complete in X minutes, we consider it as failed.
            workflow_run_timeout=timedelta(minutes=5),

        ),
    )

    # Wait for the workflow to complete
    # await workflow.move_rows_to_shards()

    # FIXME test everything out

    log.info("Stopping workers...")
    await stop_worker_faster(worker)
    log.info("Stopped workers")
