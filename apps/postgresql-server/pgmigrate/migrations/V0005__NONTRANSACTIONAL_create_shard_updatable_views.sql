-- Create schemas to temporarily move the sharded tables to
CREATE SCHEMA sharded_public;
CREATE SCHEMA sharded_public_store;
CREATE SCHEMA sharded_snap;
CREATE SCHEMA sharded_cache;


-- "schema_version" table is small and local so we can just move it straight away


--
-- MOVE ALL ROWS FOR SOME SMALL TABLES
--


--
-- database_variables
--
INSERT INTO public.database_variables (
    database_variables_id,
    name,
    value
)
    SELECT
        database_variables_id::BIGINT,
        name::TEXT,
        value::TEXT
    FROM unsharded_public.database_variables;

SELECT setval(
    pg_get_serial_sequence('public.database_variables', 'database_variables_id'),
    nextval(pg_get_serial_sequence('unsharded_public.database_variables', 'database_variables_id')),
    false
);

TRUNCATE unsharded_public.database_variables;
DROP TABLE unsharded_public.database_variables;


--
-- color_sets
--
INSERT INTO public.color_sets (
    color_sets_id,
    color,
    color_set,
    id
)
    SELECT
        color_sets_id::BIGINT,
        color::TEXT,
        color_set::TEXT,
        id::TEXT
    FROM unsharded_public.color_sets

-- Previous migration pre-inserted a bunch of color sets that are already
-- present in the unsharded table
ON CONFLICT (color_set, id) DO NOTHING;

SELECT setval(
    pg_get_serial_sequence('public.color_sets', 'color_sets_id'),
    nextval(pg_get_serial_sequence('unsharded_public.color_sets', 'color_sets_id')),
    false
);

TRUNCATE unsharded_public.color_sets;
DROP TABLE unsharded_public.color_sets;


--
-- queued_downloads
--
INSERT INTO public.queued_downloads (
    -- queued_downloads_id is not referenced anywhere so we can reset it here
    downloads_id
)
    SELECT
        downloads_id
    FROM unsharded_public.queued_downloads;

TRUNCATE unsharded_public.queued_downloads;
DROP TABLE unsharded_public.queued_downloads;


--
-- topic_modes
--

-- "unsharded_public.topic_modes" and "public.topic_modes" are
-- identical; can't drop the unsharded table here because it's referenced in
-- multiple places, so let's just pretend it doesn't exist at this point


--
-- topic_platforms
--

-- "unsharded_public.topic_platforms" and "public.topic_platforms" are
-- identical; can't drop the unsharded table here because it's referenced in
-- multiple places, so let's just pretend it doesn't exist at this point



--
-- topic_sources
--

-- "unsharded_public.topic_sources" and "public.topic_sources" are
-- identical; can't drop the unsharded table here because it's referenced in
-- multiple places, so let's just pretend it doesn't exist at this point



--
-- celery_groups
--

-- Table's contents will be recreated by Celery
TRUNCATE unsharded_public.celery_groups;
DROP TABLE unsharded_public.celery_groups;



--
-- celery_tasks
--

-- Table's contents will be recreated by Celery
TRUNCATE unsharded_public.celery_tasks;
DROP TABLE unsharded_public.celery_tasks;


--
-- cache.s3_raw_downloads_cache
--

-- Cache table can be just purged
TRUNCATE unsharded_cache.s3_raw_downloads_cache;
DROP TABLE unsharded_cache.s3_raw_downloads_cache;



--
-- cache.extractor_results_cache
--

-- Cache table can be just purged
TRUNCATE unsharded_cache.extractor_results_cache;
DROP TABLE unsharded_cache.extractor_results_cache;


--
-- domain_web_requests
--

-- Nothing worth preserving in this table too
TRUNCATE unsharded_public.domain_web_requests;
DROP TABLE unsharded_public.domain_web_requests;




--
-- MOVE PUBLICLY USED FUNCTIONS
--



--
-- week_start_date()
--

-- Old function is still used in story_sentences_p for indexing



--
-- half_md5()
--

-- Old function is still used in story_sentences_p for indexing



--
-- media_has_active_syndicated_feeds()
--

DROP FUNCTION unsharded_public.media_has_active_syndicated_feeds(INT);



--
-- feed_is_stale()
--

DROP FUNCTION unsharded_public.feed_is_stale(INT);



--
-- pop_queued_download()
--

DROP FUNCTION unsharded_public.pop_queued_download();



--
-- get_normalized_title()
--

DROP FUNCTION unsharded_public.get_normalized_title(TEXT, INT);



--
-- insert_platform_source_pair()
--

DROP FUNCTION unsharded_public.insert_platform_source_pair(TEXT, TEXT);



--
-- generate_api_key()
--

-- Old function is still used in story_sentences_p for indexing



--
-- story_is_english_and_has_sentences()
--

DROP FUNCTION unsharded_public.story_is_english_and_has_sentences(INT);



--
-- update_feeds_from_yesterday()
--

DROP FUNCTION unsharded_public.update_feeds_from_yesterday();




--
-- rescraping_changes()
--

DROP FUNCTION unsharded_public.rescraping_changes();


--
-- cache.purge_object_caches()
--

DROP FUNCTION unsharded_cache.purge_object_caches();



--
-- get_domain_web_requests_lock()
--
DROP FUNCTION unsharded_public.get_domain_web_requests_lock(TEXT, FLOAT);




--
-- DROP UNUSED VIEWS
--

DROP VIEW unsharded_public.controversies;

DROP VIEW unsharded_public.controversy_dumps;

DROP VIEW unsharded_public.controversy_dump_time_slices;

-- Will have to do copying from partitions directly
DROP VIEW unsharded_public.story_sentences;

-- Will have to do copying from partitions directly
DROP VIEW unsharded_public.feeds_stories_map;

-- Will have to do copying from partitions directly
DROP VIEW unsharded_public.stories_tags_map;

DROP VIEW unsharded_public.daily_stats;

DROP VIEW unsharded_public.downloads_media;

DROP VIEW unsharded_public.downloads_non_media;

DROP VIEW unsharded_public.downloads_to_be_extracted;

DROP VIEW unsharded_public.downloads_with_error_in_past_day;

DROP VIEW unsharded_public.downloads_in_past_day;

DROP VIEW unsharded_public.tags_with_sets;

DROP VIEW unsharded_public.media_with_media_types;

DROP VIEW unsharded_public.topic_links_cross_media;

DROP VIEW unsharded_public.feedly_unscraped_feeds;

DROP VIEW unsharded_public.stories_collected_in_past_day;

DROP VIEW unsharded_public.topics_with_user_permission;

DROP VIEW unsharded_public.topic_post_stories;

DROP VIEW unsharded_public.pending_job_states;


--
-- DROP UNUSED SEQUENCES
--

DROP SEQUENCE unsharded_public.task_id_sequence;





--
-- DROP UNUSED FUNCTIONS
--

DROP FUNCTION unsharded_public.table_exists(VARCHAR);

DROP FUNCTION unsharded_public.partition_name(TEXT, BIGINT, BIGINT);

DROP FUNCTION unsharded_public.partition_by_stories_id_chunk_size();

DROP FUNCTION unsharded_public.partition_by_stories_id_partition_name(TEXT, BIGINT);

DROP FUNCTION unsharded_public.partition_by_stories_id_create_partitions(TEXT);

DROP FUNCTION unsharded_public.partition_by_downloads_id_chunk_size();

DROP FUNCTION unsharded_public.partition_by_downloads_id_partition_name(TEXT, BIGINT);

DROP FUNCTION unsharded_public.partition_by_downloads_id_create_partitions(TEXT);

DROP FUNCTION unsharded_public.downloads_create_subpartitions(TEXT);

DROP FUNCTION unsharded_public.downloads_success_content_create_partitions();

DROP FUNCTION unsharded_public.downloads_success_feed_create_partitions();

DROP FUNCTION unsharded_public.feeds_stories_map_create_partitions();

DROP FUNCTION unsharded_public.stories_tags_map_create_partitions();

DROP FUNCTION unsharded_public.download_texts_create_partitions();

DROP FUNCTION unsharded_public.story_sentences_create_partitions();

DROP FUNCTION unsharded_public.auth_user_limits_weekly_usage(CITEXT);

DROP FUNCTION unsharded_public.create_missing_partitions();

DROP FUNCTION unsharded_public.story_sentences_view_insert_update_delete();

DROP FUNCTION unsharded_public.stories_tags_map_view_insert_update_delete();




--
-- DROP UNUSED TRIGGERS
--

DROP TRIGGER stories_tags_map_p_upsert_trigger ON unsharded_public.stories_tags_map_p;
DROP FUNCTION unsharded_public.stories_tags_map_p_upsert_trigger();

DROP TRIGGER story_sentences_p_insert_trigger ON unsharded_public.story_sentences_p;
DROP FUNCTION unsharded_public.story_sentences_p_insert_trigger();

DROP TRIGGER topic_stories_insert_live_story ON unsharded_public.topic_stories;
DROP FUNCTION unsharded_public.insert_live_story();

DROP TRIGGER stories_update_live_story ON unsharded_public.stories;
DROP FUNCTION unsharded_public.update_live_story();

DROP TRIGGER auth_user_api_keys_add_non_ip_limited_api_key ON unsharded_public.auth_users;
DROP FUNCTION unsharded_public.auth_user_api_keys_add_non_ip_limited_api_key();

DROP TRIGGER auth_users_set_default_limits ON unsharded_public.auth_users;
DROP FUNCTION unsharded_public.auth_users_set_default_limits();

DROP FUNCTION unsharded_cache.update_cache_db_row_last_updated();

DROP TRIGGER downloads_error_test_referenced_download_trigger ON unsharded_public.downloads_error;
DROP TRIGGER downloads_feed_error_test_referenced_download_trigger ON unsharded_public.downloads_feed_error;
DROP TRIGGER downloads_fetching_test_referenced_download_trigger ON unsharded_public.downloads_fetching;
DROP TRIGGER downloads_pending_test_referenced_download_trigger ON unsharded_public.downloads_pending;
DROP TRIGGER raw_downloads_test_referenced_download_trigger ON unsharded_public.raw_downloads;

DO $$
DECLARE

    tables CURSOR FOR
        SELECT tablename
        FROM pg_tables
        WHERE
            schemaname = 'unsharded_public' AND (
                tablename LIKE 'downloads_success_content_%' OR
                tablename LIKE 'downloads_success_feed_%' OR
                tablename LIKE 'download_texts_%'
            )

        ORDER BY tablename;

BEGIN
    FOR table_record IN tables LOOP

        EXECUTE '
            DROP TRIGGER ' || table_record.tablename || '_test_referenced_download_trigger
                ON unsharded_public.' || table_record.tablename || '
        ';

    END LOOP;
END
$$;

DROP FUNCTION unsharded_public.test_referenced_download_trigger();

DROP TRIGGER feeds_stories_map_p_insert_trigger ON unsharded_public.feeds_stories_map_p;
DROP FUNCTION unsharded_public.feeds_stories_map_p_insert_trigger();

DROP TRIGGER stories_insert_solr_import_story ON unsharded_public.stories;
DROP TRIGGER stories_tags_map_p_insert_solr_import_story ON unsharded_public.stories_tags_map_p;
DROP TRIGGER ps_insert_solr_import_story ON unsharded_public.processed_stories;
DROP FUNCTION unsharded_public.insert_solr_import_story();
