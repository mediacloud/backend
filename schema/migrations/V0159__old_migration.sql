


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

