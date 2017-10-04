--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4635 and 4636.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4635, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4636, import this SQL file:
--
--     psql mediacloud < mediawords-4635-4636.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DROP TABLE IF EXISTS story_sentences_tags_map;

-- Remove orphan tags
-- DELETE FROM tags
-- WHERE NOT EXISTS (SELECT 1 FROM feeds_tags_map WHERE tags.tags_id = feeds_tags_map.tags_id)
--   AND NOT EXISTS (SELECT 1 FROM media_tags_map WHERE tags.tags_id = media_tags_map.tags_id)
--   AND NOT EXISTS (SELECT 1 FROM stories_tags_map WHERE tags.tags_id = stories_tags_map.tags_id)
--   AND NOT EXISTS (SELECT 1 FROM media_suggestions_tags_map WHERE tags.tags_id = media_suggestions_tags_map.tags_id)
-- ;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4636;

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
