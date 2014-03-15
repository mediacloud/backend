--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4442 and 4443.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4442, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4443, import this SQL file:
--
--     psql mediacloud < mediawords-4442-4443.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

DROP TRIGGER story_sentences_tags_map_update_story_sentences_last_updated_trigger ON story_sentences_tags_map;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4443;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_by_story_sentences_id_trigger() RETURNS trigger AS
$$
    DECLARE
        path_change boolean;
        reference_story_sentences_id integer default null;
    BEGIN

        IF TG_OP = 'INSERT' THEN
            -- The "old" record doesn't exist
            reference_story_sentences_id = NEW.story_sentences_id;
        ELSIF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
            reference_story_sentences_id = OLD.story_sentences_id;
        ELSE
            RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;
        END IF;

        UPDATE story_sentences
        SET db_row_last_updated = now()
        WHERE story_sentences_id = reference_story_sentences_id;
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER story_sentences_tags_map_update_story_sentences_last_updated_trigger
	AFTER INSERT OR UPDATE OR DELETE ON story_sentences_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE update_story_sentences_updated_time_by_story_sentences_id_trigger();

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

