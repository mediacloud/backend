--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4430 and 4431.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4430, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4431, import this SQL file:
--
--     psql mediacloud < mediawords-4430-4431.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4431;
    
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

ALTER TYPE download_state ADD value 'extractor_error';

-- Fix downloads marked as errors when the problem was with the extractor
UPDATE downloads set state = 'extractor_error' where state='error' and type='content' and error_message is not null and error_message like 'extractor_error%';