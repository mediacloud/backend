--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4700 and 4701.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4700, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4701, import this SQL file:
--
--     psql mediacloud < mediawords-4700-4701.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


ALTER TABLE feeds_stories_map_partitioned
    RENAME TO feeds_stories_map_p;

ALTER INDEX feeds_stories_map_partitioned_pkey
    RENAME TO feeds_stories_map_p_pkey;

DO $$
DECLARE
    tables CURSOR FOR
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename LIKE 'feeds_stories_map_partitioned_%'
        ORDER BY tablename;
    new_table_name TEXT;
BEGIN
    FOR table_record IN tables LOOP
        SELECT REPLACE(table_record.tablename, '_partitioned', '_p') INTO new_table_name;
        EXECUTE '
            ALTER TABLE ' || table_record.tablename || '
                RENAME TO ' || new_table_name || ';';
        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_pkey
                RENAME TO ' || new_table_name || '_pkey;';
        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_feeds_id_stories_id
                RENAME TO ' || new_table_name || '_feeds_id_stories_id;';
        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_stories_id
                RENAME TO ' || new_table_name || '_stories_id;';
        EXECUTE '
            ALTER TABLE ' || new_table_name || '
                RENAME CONSTRAINT ' || table_record.tablename || '_stories_id
                TO ' || new_table_name || '_stories_id';
        EXECUTE '
            ALTER TABLE ' || new_table_name || '
                RENAME CONSTRAINT ' || table_record.tablename || '_feeds_id_fkey
                TO ' || new_table_name || '_feeds_id_fkey';
        EXECUTE '
            ALTER TABLE ' || new_table_name || '
                RENAME CONSTRAINT ' || table_record.tablename || '_stories_id_fkey
                TO ' || new_table_name || '_stories_id_fkey';

    END LOOP;
END
$$;

ALTER TABLE feeds_stories_map_p
    RENAME COLUMN feeds_stories_map_partitioned_id TO feeds_stories_map_p_id;

ALTER SEQUENCE feeds_stories_map_partitioned_feeds_stories_map_partitioned_seq
    RENAME TO feeds_stories_map_p_feeds_stories_map_p_seq;


ALTER TABLE story_sentences_partitioned
    RENAME TO story_sentences_p;

ALTER INDEX story_sentences_partitioned_pkey
    RENAME TO story_sentences_p_pkey;

DO $$
DECLARE
    tables CURSOR FOR
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename LIKE 'story_sentences_partitioned_%'
        ORDER BY tablename;
    new_table_name TEXT;
BEGIN
    FOR table_record IN tables LOOP
        SELECT REPLACE(table_record.tablename, '_partitioned', '_p') INTO new_table_name;
        EXECUTE '
            ALTER TABLE ' || table_record.tablename || '
                RENAME TO ' || new_table_name || ';';
        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_pkey
                RENAME TO ' || new_table_name || '_pkey;';
        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_stories_id_sentence_number
                RENAME TO ' || new_table_name || '_stories_id_sentence_number;';
        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_sentence_media_week
                RENAME TO ' || new_table_name || '_sentence_media_week;';
        EXECUTE '
            ALTER TABLE ' || new_table_name || '
                RENAME CONSTRAINT ' || table_record.tablename || '_stories_id
                TO ' || new_table_name || '_stories_id';
        EXECUTE '
            ALTER TABLE ' || new_table_name || '
                RENAME CONSTRAINT ' || table_record.tablename || '_media_id_fkey
                TO ' || new_table_name || '_media_id_fkey';
        EXECUTE '
            ALTER TABLE ' || new_table_name || '
                RENAME CONSTRAINT ' || table_record.tablename || '_stories_id_fkey
                TO ' || new_table_name || '_stories_id_fkey';
    END LOOP;
END
$$;

ALTER TABLE story_sentences_p
    RENAME COLUMN story_sentences_partitioned_id TO story_sentences_p_id;

ALTER SEQUENCE story_sentences_partitioned_story_sentences_partitioned_id_seq
    RENAME TO story_sentences_p_story_sentences_p_id_seq;


DROP TRIGGER feeds_stories_map_partitioned_insert_trigger ON feeds_stories_map_p;

DROP FUNCTION feeds_stories_map_partitioned_insert_trigger();

CREATE OR REPLACE FUNCTION feeds_stories_map_p_insert_trigger() RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "feeds_stories_map_01")
BEGIN
    SELECT partition_by_stories_id_partition_name(
        base_table_name := 'feeds_stories_map_p',
        stories_id := NEW.stories_id
    ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER feeds_stories_map_p_insert_trigger
    BEFORE INSERT ON feeds_stories_map_p
    FOR EACH ROW
    EXECUTE PROCEDURE feeds_stories_map_p_insert_trigger();


DROP FUNCTION feeds_stories_map_create_partitions();

CREATE FUNCTION feeds_stories_map_create_partitions() RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_stories_id_create_partitions('feeds_stories_map_p'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;
        
        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_feeds_id_fkey
                FOREIGN KEY (feeds_id) REFERENCES feeds (feeds_id) MATCH FULL ON DELETE CASCADE;

            CREATE UNIQUE INDEX ' || partition || '_feeds_id_stories_id
                ON ' || partition || ' (feeds_id, stories_id);

            CREATE INDEX ' || partition || '_stories_id
                ON ' || partition || ' (stories_id);
        ';

    END LOOP;

END;
$$
LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS story_sentences_partitioned_01_insert_trigger ON story_sentences_p;  -- Typo
DROP TRIGGER IF EXISTS story_sentences_partitioned_insert_trigger ON story_sentences_p;

DROP FUNCTION story_sentences_partitioned_insert_trigger();

CREATE FUNCTION story_sentences_p_insert_trigger() RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "stories_tags_map_01")
BEGIN
    SELECT partition_by_stories_id_partition_name(
        base_table_name := 'story_sentences_p',
        stories_id := NEW.stories_id
    ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER story_sentences_p_insert_trigger
    BEFORE INSERT ON story_sentences_p
    FOR EACH ROW
    EXECUTE PROCEDURE story_sentences_p_insert_trigger();


DROP FUNCTION story_sentences_create_partitions();

CREATE FUNCTION story_sentences_create_partitions() RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_stories_id_create_partitions('story_sentences_p'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;
        
        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_media_id_fkey
                FOREIGN KEY (media_id) REFERENCES media (media_id) MATCH FULL ON DELETE CASCADE;

            CREATE UNIQUE INDEX ' || partition || '_stories_id_sentence_number
                ON ' || partition || ' (stories_id, sentence_number);

            CREATE INDEX ' || partition || '_sentence_media_week
                ON ' || partition || ' (half_md5(sentence), media_id, week_start_date(publish_date::date));
        ';

    END LOOP;

END;
$$
LANGUAGE plpgsql;


DROP FUNCTION create_missing_partitions();

CREATE OR REPLACE FUNCTION create_missing_partitions() RETURNS VOID AS
$$
BEGIN

    RAISE NOTICE 'Creating partitions in "stories_tags_map" table...';
    PERFORM stories_tags_map_create_partitions();

    RAISE NOTICE 'Creating partitions in "story_sentences_p" table...';
    PERFORM story_sentences_create_partitions();

    RAISE NOTICE 'Creating partitions in "feeds_stories_map_p" table...';
    PERFORM feeds_stories_map_create_partitions();

END;
$$
LANGUAGE plpgsql;


DROP VIEW feeds_stories_map;

CREATE VIEW feeds_stories_map AS
    SELECT
        feeds_stories_map_p_id AS feeds_stories_map_id,
        feeds_id,
        stories_id
    FROM feeds_stories_map_p;

-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW feeds_stories_map
    ALTER COLUMN feeds_stories_map_id
    SET DEFAULT nextval(pg_get_serial_sequence('feeds_stories_map_p', 'feeds_stories_map_p_id'));

-- Prevent the next INSERT from failing
SELECT nextval(pg_get_serial_sequence('feeds_stories_map_p', 'feeds_stories_map_p_id'));

DROP FUNCTION feeds_stories_map_view_insert_update_delete();

CREATE FUNCTION feeds_stories_map_view_insert_update_delete() RETURNS trigger AS $$

BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- By INSERTing into the master table, we're letting triggers choose
        -- the correct partition.
        INSERT INTO feeds_stories_map_p SELECT NEW.*;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE feeds_stories_map_p
            SET feeds_id = NEW.feeds_id,
                stories_id = NEW.stories_id
            WHERE feeds_id = OLD.feeds_id
              AND stories_id = OLD.stories_id;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        DELETE FROM feeds_stories_map_p
            WHERE feeds_id = OLD.feeds_id
              AND stories_id = OLD.stories_id;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER feeds_stories_map_view_insert_update_delete_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE ON feeds_stories_map
    FOR EACH ROW EXECUTE PROCEDURE feeds_stories_map_view_insert_update_delete();


DROP VIEW story_sentences;

CREATE VIEW story_sentences AS
    SELECT
        story_sentences_p_id AS story_sentences_id,
        stories_id,
        sentence_number,
        sentence,
        media_id,
        publish_date,
        language,
        is_dup
    FROM story_sentences_p;

-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW story_sentences
    ALTER COLUMN story_sentences_id
    SET DEFAULT nextval(pg_get_serial_sequence('story_sentences_p', 'story_sentences_p_id'));

-- Prevent the next INSERT from failing
SELECT nextval(pg_get_serial_sequence('story_sentences_p', 'story_sentences_p_id'));

DROP FUNCTION story_sentences_view_insert_update_delete();

CREATE FUNCTION story_sentences_view_insert_update_delete() RETURNS trigger AS $$
BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- By INSERTing into the master table, we're letting triggers choose
        -- the correct partition.
        INSERT INTO story_sentences_p SELECT NEW.*;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE story_sentences_p
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

        DELETE FROM story_sentences_p
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


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4701;
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
