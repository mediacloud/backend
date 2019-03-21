

-- Returns true if the date is greater than the latest import date in solr_imports
CREATE OR REPLACE FUNCTION before_last_solr_import(db_row_last_updated timestamp with time zone) RETURNS boolean AS $$
BEGIN
   RETURN ( ( db_row_last_updated is null ) OR
            ( db_row_last_updated < ( select max( import_date ) from solr_imports ) ) );
END;
$$
LANGUAGE 'plpgsql'
;

CREATE OR REPLACE FUNCTION update_media_last_updated () RETURNS trigger AS
$$
  DECLARE
  BEGIN

     IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
        update media set db_row_last_updated = now()
            where media_id = NEW.media_id and before_last_solr_import( db_row_last_updated );
     END IF;

     IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
        update media set db_row_last_updated = now()
             where media_id = OLD.media_id and before_last_solr_import( db_row_last_updated );
     END IF;

     RETURN NEW;
  END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_trigger () RETURNS trigger AS
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

	UPDATE story_sentences set db_row_last_updated = now()
        where stories_id = NEW.stories_id and before_last_solr_import( db_row_last_updated );
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_stories_updated_time_by_stories_id_trigger () RETURNS trigger AS
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
               WHERE stories_id = reference_stories_id
                and before_last_solr_import( db_row_last_updated );
            RETURN NULL;
        ELSE
            UPDATE stories
               SET db_row_last_updated = now()
               WHERE stories_id = reference_stories_id and (disable_triggers is NOT true)
                and before_last_solr_import( db_row_last_updated );
            RETURN NULL;
        END IF;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_by_story_sentences_id_trigger () RETURNS trigger AS
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
              WHERE story_sentences_id = reference_story_sentences_id
                and before_last_solr_import( db_row_last_updated );
            RETURN NULL;
        ELSE
            UPDATE story_sentences
              SET db_row_last_updated = now()
              WHERE story_sentences_id = reference_story_sentences_id and (disable_triggers is NOT true)
                and before_last_solr_import( db_row_last_updated );
            RETURN NULL;
        END IF;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_stories_updated_time_by_media_id_trigger () RETURNS trigger AS
$$
    DECLARE
        path_change boolean;
        reference_media_id integer default null;
    BEGIN

        IF TG_OP = 'INSERT' THEN
            -- The "old" record doesn't exist
            reference_media_id = EWEW.media_id;
        ELSIF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
            reference_media_id = OLD.media_id;
        ELSE
            RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;
        END IF;

        UPDATE stories SET db_row_last_updated = now()
            WHERE media_id = reference_media_id and before_last_solr_import( db_row_last_updated );

        RETURN NULL;
    END;
$$
LANGUAGE 'plpgsql';





