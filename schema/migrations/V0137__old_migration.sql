


CREATE OR REPLACE FUNCTION update_stories_updated_time_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
	UPDATE stories set db_row_last_updated = now() where stories_id = NEW.stories_id;
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER stories_tags_map_update_stories_last_updated_trigger
	AFTER DELETE ON stories_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE update_stories_updated_time_trigger();

