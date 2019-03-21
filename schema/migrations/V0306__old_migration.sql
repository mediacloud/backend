


-- Kill all autovacuums before proceeding with DDL changes
SELECT pid
FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
WHERE backend_type = 'autovacuum worker'
  AND query ~ 'story_sentences';


DROP TRIGGER stories_last_updated_trigger ON stories;
DROP TRIGGER stories_update_story_sentences_last_updated_trigger ON stories;
DROP TRIGGER story_sentences_last_updated_trigger ON story_sentences;


CREATE OR REPLACE FUNCTION last_updated_trigger() RETURNS trigger AS $$

BEGIN
    NEW.db_row_last_updated = NOW();
    RETURN NEW;
END;

$$ LANGUAGE 'plpgsql';


CREATE TRIGGER stories_last_updated_trigger
	BEFORE INSERT OR UPDATE ON stories
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger();

CREATE TRIGGER stories_update_story_sentences_last_updated_trigger
	AFTER INSERT OR UPDATE ON stories
	FOR EACH ROW
	EXECUTE PROCEDURE update_story_sentences_updated_time_trigger();

CREATE TRIGGER story_sentences_last_updated_trigger
	BEFORE INSERT OR UPDATE ON story_sentences
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger();




