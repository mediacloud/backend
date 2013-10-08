--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4422 and 4423.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4422, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4423, import this SQL file:
--
--     psql mediacloud < mediawords-4422-4423.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

ALTER TABLE media_sets_media_map
	ADD COLUMN db_row_last_updated timestamp with time zone default now();

ALTER TABLE media_sets_media_map
	ALTER COLUMN db_row_last_updated SET NOT NULL;

ALTER TABLE stories
	ADD COLUMN db_row_last_updated timestamp with time zone;

ALTER TABLE story_sentences
	ADD COLUMN db_row_last_updated timestamp with time zone;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4423;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION last_updated_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';                                                                                                                            

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') then

      	 NEW.db_row_last_updated = now();

      END IF;

      RETURN NEW;
   END;
$$
LANGUAGE 'plpgsql';

CREATE INDEX media_sets_media_map_db_row_last_updated ON media_sets_media_map ( db_row_last_updated );

CREATE INDEX stories_db_row_last_updated ON stories ( db_row_last_updated );

CREATE INDEX story_sentences_db_row_last_updated ON story_sentences ( db_row_last_updated );

CREATE TRIGGER media_sets_media_map_last_updated_trigger
	BEFORE INSERT OR UPDATE ON media_sets_media_map
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger() ;

CREATE TRIGGER stories_last_updated_trigger
	BEFORE INSERT OR UPDATE ON stories
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger() ;

CREATE TRIGGER story_sentences_last_updated_trigger
	BEFORE INSERT OR UPDATE ON story_sentences
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger() ;

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

