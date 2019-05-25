--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4691 and 4692.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4691, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4692, import this SQL file:
--
--     psql mediacloud < mediawords-4691-4692.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW feeds_stories_map
    ALTER COLUMN feeds_stories_map_id
    SET DEFAULT nextval(pg_get_serial_sequence('feeds_stories_map_partitioned', 'feeds_stories_map_partitioned_id'));

-- Prevent the next INSERT from failing
SELECT nextval(pg_get_serial_sequence('feeds_stories_map_partitioned', 'feeds_stories_map_partitioned_id'));


-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW story_sentences
    ALTER COLUMN story_sentences_id
    SET DEFAULT nextval(pg_get_serial_sequence('story_sentences_partitioned', 'story_sentences_partitioned_id'));

-- Prevent the next INSERT from failing
SELECT nextval(pg_get_serial_sequence('story_sentences_partitioned', 'story_sentences_partitioned_id'));


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4692;
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
