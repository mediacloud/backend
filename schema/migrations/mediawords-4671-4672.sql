--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4671 and 4672.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4671, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4672, import this SQL file:
--
--     psql mediacloud < mediawords-4671-4672.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DROP TRIGGER IF EXISTS ss_insert_story_media_stats ON story_sentences_nonpartitioned;
DROP TRIGGER IF EXISTS ss_update_story_media_stats ON story_sentences_nonpartitioned;
DROP TRIGGER IF EXISTS story_delete_ss_media_stats ON story_sentences_nonpartitioned;

DROP FUNCTION IF EXISTS insert_ss_media_stats();
DROP FUNCTION IF EXISTS update_ss_media_stats();
DROP FUNCTION IF EXISTS delete_ss_media_stats();


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4672;

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

