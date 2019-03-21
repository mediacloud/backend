


-- Kill all autovacuums before proceeding with DDL changes
SELECT pid
FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
WHERE backend_type = 'autovacuum worker'
  AND query ~ 'story_sentences';


DROP FUNCTION copy_chunk_of_nonpartitioned_sentences_to_partitions(start_stories_id INT, end_stories_id INT);


CREATE OR REPLACE FUNCTION story_sentences_view_insert_update_delete() RETURNS trigger AS $$

DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "story_sentences_01")

BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- By INSERTing into the master table, we're letting triggers choose
        -- the correct partition.
        INSERT INTO story_sentences_partitioned SELECT NEW.*;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE story_sentences_partitioned
            SET stories_id = NEW.stories_id,
                sentence_number = NEW.sentence_number,
                sentence = NEW.sentence,
                media_id = NEW.media_id,
                publish_date = NEW.publish_date,
                language = NEW.language,
                is_dup = NEW.is_dup
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        DELETE FROM story_sentences_partitioned
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

DROP VIEW story_sentences;

CREATE VIEW story_sentences AS
    SELECT
        story_sentences_partitioned_id AS story_sentences_id,
        stories_id,
        sentence_number,
        sentence,
        media_id,
        publish_date,
        language,
        is_dup
    FROM story_sentences_partitioned;

CREATE TRIGGER story_sentences_view_insert_update_delete_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE ON story_sentences
    FOR EACH ROW EXECUTE PROCEDURE story_sentences_view_insert_update_delete();

ALTER VIEW story_sentences
    ALTER COLUMN story_sentences_id
    SET DEFAULT nextval(pg_get_serial_sequence('story_sentences_partitioned', 'story_sentences_partitioned_id')) + 1;


TRUNCATE TABLE story_sentences_nonpartitioned;
DROP TABLE story_sentences_nonpartitioned;


