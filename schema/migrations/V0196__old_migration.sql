


-- Trigger that implements INSERT / UPDATE / DELETE behavior on "story_sentences" view
CREATE OR REPLACE FUNCTION story_sentences_view_insert_update_delete() RETURNS trigger AS $$

BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- All new INSERTs go to partitioned table only

        -- FIXME restore back to the version that uses stories_partition_name()

        IF (NEW.stories_id >= 0 AND NEW.stories_id < 100000000) THEN
            INSERT INTO story_sentences_partitioned_00 VALUES (NEW.*);

        ELSIF (NEW.stories_id >= 100000000 AND NEW.stories_id < 200000000) THEN
            INSERT INTO story_sentences_partitioned_01 VALUES (NEW.*);

        ELSIF (NEW.stories_id >= 200000000 AND NEW.stories_id < 300000000) THEN
            INSERT INTO story_sentences_partitioned_02 VALUES (NEW.*);

        ELSIF (NEW.stories_id >= 300000000 AND NEW.stories_id < 400000000) THEN
            INSERT INTO story_sentences_partitioned_03 VALUES (NEW.*);

        ELSIF (NEW.stories_id >= 400000000 AND NEW.stories_id < 500000000) THEN
            INSERT INTO story_sentences_partitioned_04 VALUES (NEW.*);

        ELSIF (NEW.stories_id >= 500000000 AND NEW.stories_id < 600000000) THEN
            INSERT INTO story_sentences_partitioned_05 VALUES (NEW.*);

        ELSIF (NEW.stories_id >= 600000000 AND NEW.stories_id < 700000000) THEN
            INSERT INTO story_sentences_partitioned_06 VALUES (NEW.*);

        ELSIF (NEW.stories_id >= 700000000 AND NEW.stories_id < 800000000) THEN
            INSERT INTO story_sentences_partitioned_07 VALUES (NEW.*);

        ELSIF (NEW.stories_id >= 800000000 AND NEW.stories_id < 900000000) THEN
            INSERT INTO story_sentences_partitioned_08 VALUES (NEW.*);

        ELSIF (NEW.stories_id >= 900000000 AND NEW.stories_id < 1000000000) THEN
            INSERT INTO story_sentences_partitioned_09 VALUES (NEW.*);

        ELSIF (NEW.stories_id >= 1000000000 AND NEW.stories_id < 1100000000) THEN
            INSERT INTO story_sentences_partitioned_10 VALUES (NEW.*);

        ELSIF (NEW.stories_id >= 1100000000 AND NEW.stories_id < 1200000000) THEN
            INSERT INTO story_sentences_partitioned_11 VALUES (NEW.*);

        ELSE
            RAISE EXCEPTION 'stories_id out of range: %', NEW.stories_id;

        END IF;

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



