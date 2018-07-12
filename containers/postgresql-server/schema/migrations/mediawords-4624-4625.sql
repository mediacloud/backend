--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4624 and 4625.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4624, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4625, import this SQL file:
--
--     psql mediacloud < mediawords-4624-4625.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


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

    RAISE NOTICE 'Purging "s3_bitly_processing_results_cache" table...';
    EXECUTE '
        DELETE FROM cache.s3_bitly_processing_results_cache
        WHERE db_row_last_updated <= NOW() - INTERVAL ''3 days'';
    ';

END;
$$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4625;

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

