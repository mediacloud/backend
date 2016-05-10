--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4537 and 4538.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4537, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4538, import this SQL file:
--
--     psql mediacloud < mediawords-4537-4538.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--


--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DROP TABLE gearman_job_queue;
DROP FUNCTION gearman_job_queue_sync_lastmod();

COMMENT ON COLUMN controversies.process_with_bitly
  IS 'Enable processing controversy''s stories with Bit.ly; add all new controversy stories to Bit.ly processing queue';


--
-- 2 of 2. Reset the database version.
--
CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4538;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
