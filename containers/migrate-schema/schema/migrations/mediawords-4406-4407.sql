--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4406 and 4407.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4406, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4407, import this SQL file:
--
--     psql mediacloud < mediawords-4406-4407.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

ALTER TABLE controversies
	ALTER COLUMN query_story_searches_id TYPE int not null references query_story_searches /* TYPE change - table: controversies original: int new: int not null references query_story_searches */,
	ALTER COLUMN query_story_searches_id DROP NOT NULL;

ALTER TABLE controversy_seed_urls
	ADD COLUMN assume_match boolean not null DEFAULT false;
	
CREATE INDEX controversy_seed_urls_url ON controversy_seed_urls (url);

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4407;
    
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

