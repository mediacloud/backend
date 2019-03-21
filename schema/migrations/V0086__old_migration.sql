

DROP TRIGGER story_sentences_tags_map_update_story_sentences_last_updated_trigger ON story_sentences_tags_map;


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

