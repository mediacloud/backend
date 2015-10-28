--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4469 and 4470.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4469, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4470, import this SQL file:
--
--     psql mediacloud < mediawords-4469-4470.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--
create index controversy_merged_stories_map_story on controversy_merged_stories_map ( target_stories_id );
create index controversy_links_ref_story on controversy_links ( ref_stories_id );
create index controversy_seed_urls_story on controversy_seed_urls ( stories_id );
create index authors_stories_queue_story on authors_stories_queue( stories_id );
create index story_subsets_processed_stories_map_processed_stories_id on story_subsets_processed_stories_map ( processed_stories_id );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4470;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
