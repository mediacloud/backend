--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4507 and 4508.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4507, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4508, import this SQL file:
--
--     psql mediacloud < mediawords-4507-4508.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- "media.content_delay" should have been added in "mediawords-4504-4505.sql"
-- schema migration file, but it wasn't there
--
-- Additionally, the column is live on the production database, so we test if
-- it's there before trying to add it

DO $$ 
    BEGIN
        ALTER TABLE media
            -- Delay content downloads for this media source this many hours
            ADD COLUMN content_delay int;
    EXCEPTION
        WHEN duplicate_column THEN
            RAISE NOTICE 'Column "media.content_delay" already exists.';
    END
$$;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4508;
    
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

