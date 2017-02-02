--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4431 and 4432.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4431, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4432, import this SQL file:
--
--     psql mediacloud < mediawords-4431-4432.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

DROP TRIGGER stories_update_story_sentences_last_updated_trigger ON stories;

DROP TRIGGER stories_tags_map_update_stories_last_updated_trigger ON stories_tags_map;

DROP TRIGGER IF EXISTS media_tags_map_update_stories_last_updated_trigger ON media_tags_map;
DROP TRIGGER IF EXISTS media_sets_media_map_update_stories_last_updated_trigger on media_sets_media_map;

DROP FUNCTION update_stories_updated_time_trigger();

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4432;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_stories_updated_time_by_stories_id_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
	UPDATE stories set db_row_last_updated = now() where stories_id = OLD.stories_id;
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_stories_updated_time_by_media_id_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
	UPDATE stories set db_row_last_updated = now() where media_id = OLD.media_id;
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER media_tags_map_update_stories_last_updated_trigger
	AFTER INSERT OR UPDATE OR DELETE ON media_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE update_stories_updated_time_by_media_id_trigger();

CREATE TRIGGER media_sets_media_map_update_stories_last_updated_trigger
	AFTER INSERT OR UPDATE OR DELETE ON media_sets_media_map
	FOR EACH ROW
	EXECUTE PROCEDURE update_stories_updated_time_by_media_id_trigger();

CREATE TRIGGER stories_update_story_sentences_last_updated_trigger
	AFTER INSERT OR UPDATE ON stories
	FOR EACH ROW
	EXECUTE PROCEDURE update_story_sentences_updated_time_trigger() ;

CREATE TRIGGER stories_tags_map_update_stories_last_updated_trigger
	AFTER INSERT OR UPDATE OR DELETE ON stories_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE update_stories_updated_time_by_stories_id_trigger();

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

