--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4547 and 4548.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4547, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4548, import this SQL file:
--
--     psql mediacloud < mediawords-4547-4548.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DROP FUNCTION loop_forever();

DROP FUNCTION add_query_version(new_query_version_enum_string character varying);

DROP FUNCTION show_stat_activity();

DROP FUNCTION cat(text, text);

DROP FUNCTION cancel_pg_process(cancel_pid integer);

DROP VIEW story_extracted_texts;

DROP VIEW media_feed_counts;

DROP TABLE url_discovery_counts;

DROP TABLE extractor_results_cache;

DROP TABLE feedless_stories;

DROP SEQUENCE IF EXISTS extractor_results_cache_extractor_results_cache_id_seq;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4548;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

