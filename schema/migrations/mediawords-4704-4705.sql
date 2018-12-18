--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4704 and 4705.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4704, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4705, import this SQL file:
--
--     psql mediacloud < mediawords-4704-4705.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


--
-- Rename non-partitioned "download_texts" to "download_texts_np"
--
ALTER TABLE download_texts
    RENAME TO download_texts_np;
ALTER TABLE download_texts_np
    RENAME COLUMN download_texts_id TO download_texts_np_id;
ALTER TABLE download_texts_np
    RENAME CONSTRAINT download_text_length_is_correct
    TO download_texts_np_length_is_correct;
ALTER SEQUENCE download_texts_download_texts_id_seq
    RENAME TO download_texts_np_download_texts_np_id_seq;
ALTER INDEX download_texts_pkey
    RENAME TO download_texts_np_pkey;
ALTER INDEX download_texts_downloads_id_index
    RENAME TO download_texts_np_downloads_id_index;
ALTER TRIGGER download_texts_test_referenced_download_trigger
    ON download_texts_np
    RENAME TO download_texts_np_test_referenced_download_trigger;


--
-- Create partitioned "download_texts_p"
--
CREATE TABLE download_texts_p (
    download_texts_p_id     BIGSERIAL   NOT NULL,
    downloads_id            BIGINT      NOT NULL,
    download_text           TEXT        NOT NULL,
    download_text_length    INT         NOT NULL,

    PRIMARY KEY (download_texts_p_id, downloads_id)

) PARTITION BY RANGE (downloads_id);

CREATE UNIQUE INDEX download_texts_p_downloads_id
    ON download_texts_p (downloads_id);

ALTER TABLE download_texts_p
    ADD CONSTRAINT download_texts_p_length_is_correct
    CHECK (length(download_text) = download_text_length);

CREATE OR REPLACE FUNCTION download_texts_p_create_partitions()
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_downloads_id_create_partitions('download_texts_p'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;
        
        EXECUTE '
            CREATE TRIGGER ' || partition || '_test_referenced_download_trigger
                BEFORE INSERT OR UPDATE ON ' || partition || '
                FOR EACH ROW
                EXECUTE PROCEDURE test_referenced_download_trigger(''downloads_id'');
        ';

    END LOOP;

END;
$$
LANGUAGE plpgsql;


--
-- Create initial "download_texts_p" partitions for empty database
--
SELECT download_texts_p_create_partitions();


-- Make partitioned table's "download_texts_id" sequence start from where
-- non-partitioned table's sequence left off
SELECT setval(
    pg_get_serial_sequence('download_texts_p', 'download_texts_p_id'),
    COALESCE(MAX(download_texts_np_id), 1), MAX(download_texts_np_id) IS NOT NULL
) FROM download_texts_np;


--
-- Create proxy view to join partitioned and non-partitioned "download_texts"
-- tables
--
CREATE OR REPLACE VIEW download_texts AS

    SELECT *
    FROM (

        -- Non-partitioned table
        SELECT
            download_texts_np_id::bigint AS download_texts_id,
            downloads_id::bigint,
            download_text,
            download_text_length
        FROM download_texts_np

        UNION ALL

        -- Partitioned table
        SELECT
            download_texts_p_id AS download_texts_id,
            downloads_id,
            download_text,
            download_text_length
        FROM download_texts_p

    ) AS dt;

-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW download_texts
    ALTER COLUMN download_texts_id
    SET DEFAULT nextval(pg_get_serial_sequence('download_texts_p', 'download_texts_p_id'));

-- Prevent the next INSERT from failing
SELECT nextval(pg_get_serial_sequence('download_texts_p', 'download_texts_p_id'));

-- Trigger that implements INSERT / UPDATE / DELETE behavior on "download_texts" view
CREATE OR REPLACE FUNCTION download_texts_view_insert_update_delete() RETURNS trigger AS $$
BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- New rows go into the partitioned table only
        INSERT INTO download_texts_p (
            download_texts_p_id,
            downloads_id,
            download_text,
            download_text_length
        ) SELECT
            NEW.download_texts_id,
            NEW.downloads_id,
            NEW.download_text,
            NEW.download_text_length;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        -- Update both tables as one of them will have the row
        UPDATE download_texts_np SET
            download_texts_np_id = NEW.download_texts_id,
            downloads_id = NEW.downloads_id,
            download_text = NEW.download_text,
            download_text_length = NEW.download_text_length
        WHERE download_texts_np_id = OLD.download_texts_id;

        UPDATE download_texts_p SET
            download_texts_p_id = NEW.download_texts_id,
            downloads_id = NEW.downloads_id,
            download_text = NEW.download_text,
            download_text_length = NEW.download_text_length
        WHERE download_texts_p_id = OLD.download_texts_id;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        -- Delete from both tables as one of them will have the row
        DELETE FROM download_texts_np
            WHERE download_texts_np_id = OLD.download_texts_id;

        DELETE FROM download_texts_p
            WHERE download_texts_p_id = OLD.download_texts_id;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER download_texts_view_insert_update_delete_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE ON download_texts
    FOR EACH ROW EXECUTE PROCEDURE download_texts_view_insert_update_delete();


--
-- Recreate function that creates new partitions
--
CREATE OR REPLACE FUNCTION create_missing_partitions()
RETURNS VOID AS
$$
BEGIN

    RAISE NOTICE 'Creating partitions in "downloads_p_success_content" table...';
    PERFORM downloads_p_success_content_create_partitions();

    RAISE NOTICE 'Creating partitions in "downloads_p_success_feed" table...';
    PERFORM downloads_p_success_feed_create_partitions();

    RAISE NOTICE 'Creating partitions in "download_texts_p" table...';
    PERFORM download_texts_p_create_partitions();

    RAISE NOTICE 'Creating partitions in "stories_tags_map_p" table...';
    PERFORM stories_tags_map_create_partitions();

    RAISE NOTICE 'Creating partitions in "story_sentences_p" table...';
    PERFORM story_sentences_create_partitions();

    RAISE NOTICE 'Creating partitions in "feeds_stories_map_p" table...';
    PERFORM feeds_stories_map_create_partitions();

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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4705;
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
