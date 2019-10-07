--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4707 and 4708.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4707, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4708, import this SQL file:
--
--     psql mediacloud < mediawords-4707-4708.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


--
-- Kill all autovacuums before proceeding with DDL changes
--
SELECT pid
FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
WHERE backend_type = 'autovacuum worker'
  AND query ~ 'download_texts';


-- Proxy view to join partitioned and non-partitioned "download_texts" tables
CREATE OR REPLACE VIEW download_texts AS

    -- Non-partitioned table
    SELECT
        download_texts_np_id::bigint AS download_texts_id,
        downloads_id::bigint,
        download_text,
        download_text_length
    FROM download_texts_np

    UNION ALL

    -- Partitioned table
    SELECT
        download_texts_p_id AS download_texts_id,
        downloads_id,
        download_text,
        download_text_length
    FROM download_texts_p;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4708;
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
