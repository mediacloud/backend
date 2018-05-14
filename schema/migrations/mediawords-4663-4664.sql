--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4663 and 4664.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4663, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4664, import this SQL file:
--
--     psql mediacloud < mediawords-4663-4664.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Kill all autovacuums before proceeding with DDL changes
SELECT pid
FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
WHERE backend_type = 'autovacuum worker';


ALTER TABLE story_sentences
    RENAME TO story_sentences_nonpartitioned;

ALTER TABLE story_sentences_nonpartitioned
    RENAME COLUMN story_sentences_id TO story_sentences_nonpartitioned_id;

ALTER INDEX story_sentences_story
    RENAME TO story_sentences_nonpartitioned_story;
ALTER INDEX story_sentences_db_row_last_updated
    RENAME TO story_sentences_nonpartitioned_db_row_last_updated;
ALTER INDEX story_sentences_sentence_half_md5
    RENAME TO story_sentences_nonpartitioned_sentence_half_md5;
ALTER TRIGGER story_sentences_last_updated_trigger ON story_sentences_nonpartitioned
    RENAME TO story_sentences_nonpartitioned_last_updated_trigger;


-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE story_sentences_partitioned (
    story_sentences_partitioned_id      BIGSERIAL       PRIMARY KEY NOT NULL,
    stories_id                          INT             NOT NULL,
    sentence_number                     INT             NOT NULL,
    sentence                            TEXT            NOT NULL,
    media_id                            INT             NOT NULL,
    publish_date                        TIMESTAMP       NOT NULL,

    -- Time this row was last updated
    db_row_last_updated                 TIMESTAMP WITH TIME ZONE,

    -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
    language                            VARCHAR(3)      NULL,

    -- Set to 'true' for every sentence for which a duplicate sentence was
    -- found in a future story (even though that duplicate sentence wasn't
    -- added to the table)
    --
    -- "We only use is_dup in the topic spidering, but I think it is critical
    -- there. It is there because the first time I tried to run a spider on a
    -- broadly popular topic, it was unusable because of the amount of
    -- irrelevant content. When I dug in, I found that stories were getting
    -- included because of matches on boilerplate content that was getting
    -- duped out of most stories but not the first time it appeared. So I added
    -- the check to remove stories that match on a dup sentence, even if it is
    -- the dup sentence, and things cleaned up."
    is_dup                              BOOLEAN         NULL
);

CREATE TRIGGER story_sentences_partitioned_last_updated_trigger
    BEFORE INSERT OR UPDATE ON story_sentences_partitioned
    FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger();


-- Make the partitioned table continue the sequence where the non-partitioned
-- table left off
SELECT setval(
    pg_get_serial_sequence('story_sentences_partitioned', 'story_sentences_partitioned_id'),
    (SELECT MAX(story_sentences_nonpartitioned_id) FROM story_sentences_nonpartitioned)
);


-- Create missing "story_sentences_partitioned" partitions
CREATE OR REPLACE FUNCTION story_sentences_create_partitions()
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT stories_create_partitions('story_sentences_partitioned'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;
        
        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_media_id_fkey
                FOREIGN KEY (media_id) REFERENCES media (media_id) MATCH FULL ON DELETE CASCADE;

            CREATE UNIQUE INDEX ' || partition || '_stories_id_sentence_number
                ON ' || partition || ' (stories_id, sentence_number);

            CREATE INDEX ' || partition || '_db_row_last_updated
                ON ' || partition || ' (db_row_last_updated);

            CREATE INDEX ' || partition || '_sentence_media_week
                ON ' || partition || ' (half_md5(sentence), media_id, week_start_date(publish_date::date));
        ';

    END LOOP;

END;
$$
LANGUAGE plpgsql;

-- Create initial "story_sentences_partitioned" partitions for empty database
SELECT story_sentences_create_partitions();


-- View that joins the non-partitioned and partitioned tables while the data is
-- being migrated
CREATE OR REPLACE VIEW story_sentences AS

    SELECT *
    FROM (
        SELECT
            story_sentences_partitioned_id AS story_sentences_id,
            stories_id,
            sentence_number,
            sentence,
            media_id,
            publish_date,
            db_row_last_updated,
            language,
            is_dup
        FROM story_sentences_partitioned

        UNION ALL

        SELECT
            story_sentences_nonpartitioned_id AS story_sentences_id,
            stories_id,
            sentence_number,
            sentence,
            media_id,
            publish_date,
            db_row_last_updated,
            language,
            is_dup
        FROM story_sentences_nonpartitioned

    ) AS ss;


-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW story_sentences
    ALTER COLUMN story_sentences_id
    SET DEFAULT nextval(pg_get_serial_sequence('story_sentences_partitioned', 'story_sentences_partitioned_id')) + 1;


-- Trigger that implements INSERT / UPDATE / DELETE behavior on "story_sentences" view
CREATE OR REPLACE FUNCTION story_sentences_view_insert_update_delete() RETURNS trigger AS $$

DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "story_sentences_01")

BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- All new INSERTs go to partitioned table only
        SELECT stories_partition_name( 'story_sentences_partitioned', NEW.stories_id ) INTO target_table_name;
        EXECUTE '
            INSERT INTO ' || target_table_name || '
                SELECT $1.*
            ' USING NEW;

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

CREATE TRIGGER story_sentences_view_insert_update_delete_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE ON story_sentences
    FOR EACH ROW EXECUTE PROCEDURE story_sentences_view_insert_update_delete();


-- Copy a chunk of sentences from a non-partitioned "story_sentences" to a
-- partitioned one; call this repeatedly to migrate all the data to the partitioned table
CREATE OR REPLACE FUNCTION copy_chunk_of_nonpartitioned_sentences_to_partitions(chunk_size INT)
RETURNS VOID AS $$
BEGIN

    RAISE NOTICE 'Copying % rows to the partitioned table...', chunk_size;

    WITH rows_to_move AS (
        DELETE FROM story_sentences_nonpartitioned
        WHERE story_sentences_nonpartitioned_id IN (
            SELECT story_sentences_nonpartitioned_id
            FROM story_sentences_nonpartitioned
            LIMIT chunk_size
        )
        RETURNING story_sentences_nonpartitioned.*
    )
    INSERT INTO story_sentences_partitioned (
        story_sentences_partitioned_id,
        stories_id,
        sentence_number,
        sentence,
        media_id,
        publish_date,
        db_row_last_updated,
        language,
        is_dup
    )
    SELECT
        story_sentences_nonpartitioned_id,
        stories_id,
        sentence_number,
        sentence,
        media_id,
        publish_date,
        db_row_last_updated,
        language,
        is_dup
    FROM rows_to_move;

    RAISE NOTICE 'Done copying % rows to the partitioned table.', chunk_size;

END;
$$
LANGUAGE plpgsql;


-- Migrate a huge chunk of sentences to the partitioned table
--
-- This should help upgrade the dev environments by copying *all* sentences in
-- small test datasets while not blocking the migration in production due to a
-- small chunk size.
SELECT copy_chunk_of_nonpartitioned_sentences_to_partitions(1000000);


CREATE OR REPLACE FUNCTION create_missing_partitions() RETURNS VOID AS
$$
BEGIN

    RAISE NOTICE 'Creating partitions in "stories_tags_map" table...';
    PERFORM stories_tags_map_create_partitions();

    RAISE NOTICE 'Creating partitions in "story_sentences_partitioned" table...';
    PERFORM story_sentences_create_partitions();


END;
$$
LANGUAGE plpgsql;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4664;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
