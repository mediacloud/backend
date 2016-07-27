--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4567 and 4568.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4567, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4568, import this SQL file:
--
--     psql mediacloud < mediawords-4567-4568.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DROP TABLE bitly_clicks_daily;

DROP FUNCTION upsert_bitly_clicks_daily(param_stories_id INT, param_day DATE, param_click_count INT);

DROP FUNCTION bitly_clicks_daily_partition_by_stories_id_insert_trigger();


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4568;

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

