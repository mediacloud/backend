--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4492 and 4493.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4492, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4493, import this SQL file:
--
--     psql mediacloud < mediawords-4492-4493.sql
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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4493;
    
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
      table_with_trigger_column  boolean default false;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';                                                                                                                            
        IF TG_TABLE_NAME in ( 'processed_stories', 'stories', 'story_sentences') THEN
           table_with_trigger_column = true;
        ELSE
           table_with_trigger_column = false;
        END IF;

	IF table_with_trigger_column THEN
	   IF ( ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') ) AND NEW.disable_triggers THEN
     	       RETURN NEW;
           END IF;
      END IF;

      IF ( story_triggers_enabled() ) AND ( ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') ) then

      	 NEW.db_row_last_updated = now();

      END IF;

      RETURN NEW;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN

        IF NOT story_triggers_enabled() THEN
           RETURN NULL;
        END IF;

        IF NEW.disable_triggers THEN
           RETURN NULL;
        END IF;

	UPDATE story_sentences set db_row_last_updated = now() where stories_id = NEW.stories_id;
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_stories_updated_time_by_stories_id_trigger() RETURNS trigger AS
$$
    DECLARE
        path_change boolean;
        table_with_trigger_column  boolean default false;
        reference_stories_id integer default null;
    BEGIN

       IF NOT story_triggers_enabled() THEN
           RETURN NULL;
        END IF;

        IF TG_TABLE_NAME in ( 'processed_stories', 'stories', 'story_sentences') THEN
           table_with_trigger_column = true;
        ELSE
           table_with_trigger_column = false;
        END IF;

	IF table_with_trigger_column THEN
	   IF TG_OP = 'INSERT' AND NEW.disable_triggers THEN
	       RETURN NULL;
	   ELSEIF ( ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') ) AND OLD.disable_triggers THEN
     	       RETURN NULL;
           END IF;
       END IF;

        IF TG_OP = 'INSERT' THEN
            -- The "old" record doesn't exist
            reference_stories_id = NEW.stories_id;
        ELSIF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
            reference_stories_id = OLD.stories_id;
        ELSE
            RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;
        END IF;

	IF table_with_trigger_column THEN
            UPDATE stories
               SET db_row_last_updated = now()
               WHERE stories_id = reference_stories_id;
            RETURN NULL;
        ELSE
            UPDATE stories
               SET db_row_last_updated = now()
               WHERE stories_id = reference_stories_id and (disable_triggers is NOT true);
            RETURN NULL;
        END IF;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_by_story_sentences_id_trigger() RETURNS trigger AS
$$
    DECLARE
        path_change boolean;
        table_with_trigger_column  boolean default false;
        reference_story_sentences_id bigint default null;
    BEGIN

       IF NOT story_triggers_enabled() THEN
           RETURN NULL;
        END IF;

       IF NOT story_triggers_enabled() THEN
           RETURN NULL;
        END IF;

        IF TG_TABLE_NAME in ( 'processed_stories', 'stories', 'story_sentences') THEN
           table_with_trigger_column = true;
        ELSE
           table_with_trigger_column = false;
        END IF;

	IF table_with_trigger_column THEN
	   IF TG_OP = 'INSERT' AND NEW.disable_triggers THEN
	       RETURN NULL;
	   ELSEIF ( ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') ) AND OLD.disable_triggers THEN
     	       RETURN NULL;
           END IF;
       END IF;

        IF TG_OP = 'INSERT' THEN
            -- The "old" record doesn't exist
            reference_story_sentences_id = NEW.story_sentences_id;
        ELSIF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
            reference_story_sentences_id = OLD.story_sentences_id;
        ELSE
            RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;
        END IF;

	IF table_with_trigger_column THEN
            UPDATE story_sentences
              SET db_row_last_updated = now()
              WHERE story_sentences_id = reference_story_sentences_id;
            RETURN NULL;
        ELSE
            UPDATE story_sentences
              SET db_row_last_updated = now()
              WHERE story_sentences_id = reference_story_sentences_id and (disable_triggers is NOT true);
            RETURN NULL;
        END IF;
   END;
$$
LANGUAGE 'plpgsql';

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

