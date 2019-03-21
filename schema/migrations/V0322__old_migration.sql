

DROP TRIGGER stories_update_story_sentences_last_updated_trigger ON stories;

DROP TRIGGER stories_tags_map_update_stories_last_updated_trigger ON stories_tags_map;

DROP TRIGGER IF EXISTS media_tags_map_update_stories_last_updated_trigger ON media_tags_map;
DROP TRIGGER IF EXISTS media_sets_media_map_update_stories_last_updated_trigger on media_sets_media_map;

DROP FUNCTION update_stories_updated_time_trigger();


CREATE OR REPLACE FUNCTION update_stories_updated_time_by_stories_id_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
	UPDATE stories set db_row_last_updated = now() where stories_id = OLD.stories_id;
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_stories_updated_time_by_media_id_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
	UPDATE stories set db_row_last_updated = now() where media_id = OLD.media_id;
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER media_tags_map_update_stories_last_updated_trigger
	AFTER INSERT OR UPDATE OR DELETE ON media_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE update_stories_updated_time_by_media_id_trigger();

CREATE TRIGGER media_sets_media_map_update_stories_last_updated_trigger
	AFTER INSERT OR UPDATE OR DELETE ON media_sets_media_map
	FOR EACH ROW
	EXECUTE PROCEDURE update_stories_updated_time_by_media_id_trigger();

CREATE TRIGGER stories_update_story_sentences_last_updated_trigger
	AFTER INSERT OR UPDATE ON stories
	FOR EACH ROW
	EXECUTE PROCEDURE update_story_sentences_updated_time_trigger() ;

CREATE TRIGGER stories_tags_map_update_stories_last_updated_trigger
	AFTER INSERT OR UPDATE OR DELETE ON stories_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE update_stories_updated_time_by_stories_id_trigger();

