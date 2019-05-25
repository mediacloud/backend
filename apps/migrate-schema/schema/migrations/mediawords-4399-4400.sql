--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4399 and 4400.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4399, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4400, import this SQL file:
--
--     psql mediacloud < mediawords-4399-4400.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

CREATE TABLE story_subsets (
	story_subsets_id bigserial          primary key,
	start_date timestamp with time zone,
	end_date timestamp with time zone,
	media_id int references media_sets,
	media_sets_id int references media_sets,
	ready boolean DEFAULT 'false',
	last_processed_stories_id bigint references processed_stories(processed_stories_id)
);

CREATE TABLE story_subsets_processed_stories_map (
	story_subsets_processed_stories_map_id bigserial primary key,
	story_subsets_id bigint NOT NULL references story_subsets on delete cascade,
	processed_stories_id bigint NOT NULL references processed_stories on delete cascade
);

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4400;
    
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

