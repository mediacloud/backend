--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4727 and 4728.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4727, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4728, import this SQL file:
--
--     psql mediacloud < mediawords-4727-4728.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--


DROP VIEW download_texts;


TRUNCATE TABLE download_texts_np;
DROP TABLE download_texts_np;


DROP FUNCTION download_texts_view_insert_update_delete();
DROP FUNCTION move_chunk_of_nonpartitioned_download_texts_to_partitions(INT, INT);

DROP FUNCTION to_bigint(INT);


ALTER TABLE download_texts_p RENAME TO download_texts;
ALTER TABLE download_texts RENAME COLUMN download_texts_p_id TO download_texts_id;
ALTER TABLE download_texts RENAME CONSTRAINT download_texts_p_length_is_correct TO download_texts_length_is_correct;

ALTER INDEX download_texts_p_pkey RENAME TO download_texts_pkey;
ALTER INDEX download_texts_p_downloads_id RENAME TO download_texts_downloads_id;

ALTER SEQUENCE download_texts_p_download_texts_p_id_seq RENAME TO download_texts_download_texts_id_seq;


DO $$
DECLARE

    new_table_name TEXT;

    tables CURSOR FOR
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename LIKE 'download_texts_p_%'
        ORDER BY tablename;

BEGIN
    FOR table_record IN tables LOOP

        SELECT REPLACE(table_record.tablename, 'download_texts_p_', 'download_texts_') INTO new_table_name;

        EXECUTE '
            ALTER TABLE ' || table_record.tablename || '
                RENAME TO ' || new_table_name || '
        ';

        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_pkey
                RENAME TO ' || new_table_name || '_pkey
        ';

        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_downloads_id_idx
                RENAME TO ' || new_table_name || '_downloads_id_idx
        ';

        EXECUTE '
            ALTER TABLE ' || new_table_name || '
                RENAME CONSTRAINT ' || table_record.tablename || '_downloads_id_fkey
                TO ' || new_table_name || '_downloads_id_fkey
        ';

        EXECUTE '
            ALTER TRIGGER ' || table_record.tablename || '_test_referenced_download_trigger
                ON ' || new_table_name || '
                RENAME TO ' || new_table_name || '_test_referenced_download_trigger
        ';

    END LOOP;
END
$$;


-- Recreate function that creates "download_texts" partitions with a different name
DROP FUNCTION download_texts_p_create_partitions();

CREATE OR REPLACE FUNCTION download_texts_create_partitions()
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_downloads_id_create_partitions('download_texts'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Adding foreign key to created partition "%"...', partition;
        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || partition || '_downloads_id_fkey
                FOREIGN KEY (downloads_id)
                REFERENCES ' || REPLACE(partition, 'download_texts', 'downloads_success_content') || ' (downloads_id)
                ON DELETE CASCADE;
        ';

        RAISE NOTICE 'Adding trigger to created partition "%"...', partition;
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


-- Update function that creates partitions of all partitioned tables to call
-- the right "subsidiary" for the "download_texts" table
CREATE OR REPLACE FUNCTION create_missing_partitions()
RETURNS VOID AS
$$
BEGIN

    -- We have to create "downloads" partitions before "download_texts" ones
    -- because "download_texts" will have a foreign key reference to
    -- "downloads_success_content"

    RAISE NOTICE 'Creating partitions in "downloads_success_content" table...';
    PERFORM downloads_success_content_create_partitions();

    RAISE NOTICE 'Creating partitions in "downloads_success_feed" table...';
    PERFORM downloads_success_feed_create_partitions();

    RAISE NOTICE 'Creating partitions in "download_texts" table...';
    PERFORM download_texts_create_partitions();

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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4728;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
