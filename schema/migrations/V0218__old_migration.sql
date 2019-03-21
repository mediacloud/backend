


CREATE OR REPLACE FUNCTION story_triggers_enabled() RETURNS boolean  LANGUAGE  plpgsql AS $$
BEGIN

    return current_setting('PRIVATE.use_story_triggers') = 'yes';
     EXCEPTION when undefined_object then
        perform enable_story_triggers();
        return true;
END$$;

CREATE OR REPLACE FUNCTION enable_story_triggers() RETURNS void LANGUAGE  plpgsql AS $$
DECLARE
BEGIN
        perform set_config('PRIVATE.use_story_triggers', 'yes', false );
END$$;

CREATE OR REPLACE FUNCTION disable_story_triggers() RETURNS void LANGUAGE  plpgsql AS $$
DECLARE
BEGIN
        perform set_config('PRIVATE.use_story_triggers', 'no', false );
END$$;

CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN

        IF NOT story_triggers_enabled() THEN
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
        reference_stories_id integer default null;
    BEGIN

       IF NOT story_triggers_enabled() THEN
           RETURN NULL;
        END IF;

        IF TG_OP = 'INSERT' THEN
            -- The "old" record doesn't exist
            reference_stories_id = NEW.stories_id;
        ELSIF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
            reference_stories_id = OLD.stories_id;
        ELSE
            RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;
        END IF;

        UPDATE stories
        SET db_row_last_updated = now()
        WHERE stories_id = reference_stories_id;
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_by_story_sentences_id_trigger() RETURNS trigger AS
$$
    DECLARE
        path_change boolean;
        reference_story_sentences_id bigint default null;
    BEGIN

       IF NOT story_triggers_enabled() THEN
           RETURN NULL;
        END IF;

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

