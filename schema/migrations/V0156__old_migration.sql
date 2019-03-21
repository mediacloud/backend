


DROP TRIGGER story_sentences_partitioned_last_updated_trigger ON story_sentences_partitioned;


CREATE TRIGGER story_sentences_partitioned_00_last_updated_trigger
    BEFORE INSERT OR UPDATE ON story_sentences_partitioned
    FOR EACH ROW
    EXECUTE PROCEDURE last_updated_trigger();


-- Note: "INSERT ... RETURNING *" doesn't work with the trigger, please use
-- "story_sentences" view instead
CREATE OR REPLACE FUNCTION story_sentences_partitioned_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "stories_tags_map_01")
BEGIN
    SELECT stories_partition_name('story_sentences_partitioned', NEW.stories_id ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER story_sentences_partitioned_01_insert_trigger
    BEFORE INSERT ON story_sentences_partitioned
    FOR EACH ROW
    EXECUTE PROCEDURE story_sentences_partitioned_insert_trigger();


CREATE OR REPLACE FUNCTION story_sentences_view_insert_update_delete() RETURNS trigger AS $$

DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "story_sentences_01")

BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- All new INSERTs go to partitioned table only.
        --
        -- By INSERTing into the master table, we're letting triggers choose
        -- the correct partition and update db_row_last_updated.
        INSERT INTO story_sentences_partitioned SELECT NEW.*;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        -- UPDATE on both tables

        UPDATE story_sentences_partitioned
            SET stories_id = NEW.stories_id,
                sentence_number = NEW.sentence_number,
                sentence = NEW.sentence,
                media_id = NEW.media_id,
                publish_date = NEW.publish_date,
                db_row_last_updated = NEW.db_row_last_updated,
                language = NEW.language,
                is_dup = NEW.is_dup
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        UPDATE story_sentences_nonpartitioned
            SET stories_id = NEW.stories_id,
                sentence_number = NEW.sentence_number,
                sentence = NEW.sentence,
                media_id = NEW.media_id,
                publish_date = NEW.publish_date,
                db_row_last_updated = NEW.db_row_last_updated,
                language = NEW.language,
                is_dup = NEW.is_dup
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        -- DELETE from both tables

        DELETE FROM story_sentences_partitioned
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        DELETE FROM story_sentences_nonpartitioned
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;




