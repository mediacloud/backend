


DROP TRIGGER IF EXISTS processed_stories_update_stories_last_updated_trigger ON processed_stories;

CREATE TRIGGER processed_stories_update_stories_last_updated_trigger
	AFTER INSERT OR UPDATE OR DELETE ON processed_stories
	FOR EACH ROW
	EXECUTE PROCEDURE update_stories_updated_time_by_stories_id_trigger();

