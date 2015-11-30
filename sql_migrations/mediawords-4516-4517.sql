--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4516 and 4517.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4516, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4517, import this SQL file:
--
--     psql mediacloud < mediawords-4516-4517.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

drop index stories_db_row_last_updated;
drop INDEX downloads_file_status;
drop INDEX downloads_relative_path;
drop index downloads_type;
drop index downloads_host_state_priority;
drop index downloads_feed_state;
drop index downloads_url;
drop INDEX downloads_for_extractor_trainer;

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4517;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
