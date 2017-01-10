--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4410 and 4411.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4409, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4411, import this SQL file:
--
--     psql mediacloud < mediawords-4410-4411.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4411;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

ALTER TABLE feeds
    RENAME COLUMN last_download_time TO last_attempted_download_time;
ALTER TABLE feeds
    ADD COLUMN last_successful_download_time TIMESTAMP WITH TIME ZONE;
UPDATE feeds
    SET last_new_story_time = GREATEST( last_attempted_download_time, last_new_story_time );
ALTER INDEX feeds_last_download_time
    RENAME TO feeds_last_attempted_download_time;
CREATE INDEX feeds_last_successful_download_time
    ON feeds(last_successful_download_time);


--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

