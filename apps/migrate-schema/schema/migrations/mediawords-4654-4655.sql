--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4654 and 4655.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4654, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4655, import this SQL file:
--
--     psql mediacloud < mediawords-4654-4655.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


ALTER TABLE feeds DROP COLUMN skip_bitly_processing;

DROP TABLE IF EXISTS story_statistics_bitly_referrers;

DROP TABLE bitly_clicks_total CASCADE;

DROP FUNCTION bitly_partition_chunk_size();

DROP FUNCTION bitly_get_partition_name(INT, TEXT);

DROP FUNCTION bitly_clicks_total_partition_by_stories_id_insert_trigger();

DROP FUNCTION bitly_clicks_total_create_partitions();

DROP TABLE bitly_processing_schedule;

DROP FUNCTION num_topic_stories_without_bitly_statistics(INT);

ALTER TABLE snap.story_link_counts DROP COLUMN bitly_click_count;

ALTER TABLE snap.medium_link_counts DROP COLUMN bitly_click_count;

DROP TABLE bitly_processing_results;

DROP TABLE cache.s3_bitly_processing_results_cache;

DROP TABLE IF EXISTS bitly_processed_stories;


-- Create missing partitions for partitioned tables
CREATE OR REPLACE FUNCTION create_missing_partitions()
RETURNS VOID AS
$$
BEGIN

    -- "stories_tags_map" table
    RAISE NOTICE 'Creating partitions in "stories_tags_map" table...';
    PERFORM stories_tags_map_create_partitions();

END;
$$
LANGUAGE plpgsql;


-- Helper to purge object caches
CREATE OR REPLACE FUNCTION cache.purge_object_caches()
RETURNS VOID AS
$$
BEGIN

    RAISE NOTICE 'Purging "s3_raw_downloads_cache" table...';
    EXECUTE '
        DELETE FROM cache.s3_raw_downloads_cache
        WHERE db_row_last_updated <= NOW() - INTERVAL ''3 days'';
    ';

END;
$$
LANGUAGE plpgsql;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4655;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
