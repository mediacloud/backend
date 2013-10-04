--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4424 and 4425.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4424, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4425, import this SQL file:
--
--     psql mediacloud < mediawords-4424-4425.sql
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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4425;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
	UPDATE story_sentences set db_row_last_updated = now() where stories_id = NEW.stories_id;
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER stories_update_story_sentences_last_updated_trigger
	AFTER UPDATE ON stories
	FOR EACH ROW
	EXECUTE PROCEDURE update_story_sentences_updated_time_trigger() ;

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

