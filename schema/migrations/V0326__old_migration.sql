


CREATE OR REPLACE FUNCTION last_updated_trigger() RETURNS trigger AS $$

BEGIN
    IF (TG_OP = 'UPDATE') OR (TG_OP = 'INSERT') then
        NEW.db_row_last_updated = NOW();
    END IF;

    RETURN NEW;
END;

$$ LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_trigger() RETURNS trigger AS $$

BEGIN
    UPDATE story_sentences
    SET db_row_last_updated = NOW()
    WHERE stories_id = NEW.stories_id
      AND before_last_solr_import( db_row_last_updated );

    RETURN NULL;
END;

$$ LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION update_stories_updated_time_by_stories_id_trigger() RETURNS trigger AS $$

DECLARE
    reference_stories_id integer default null;

BEGIN

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
    WHERE stories_id = reference_stories_id
      AND before_last_solr_import( db_row_last_updated );

    RETURN NULL;

END;

$$ LANGUAGE 'plpgsql';




