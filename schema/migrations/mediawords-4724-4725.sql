--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4724 and 4725.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4724, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4725, import this SQL file:
--
--     psql mediacloud < mediawords-4724-4725.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--


-- Delete download texts which don't have references in "downloads" due to a missing foreign key
DELETE FROM download_texts
WHERE downloads_id IN (
    SELECT download_texts.downloads_id
    FROM download_texts
        LEFT JOIN downloads
            ON download_texts.downloads_id = downloads.downloads_id
    WHERE downloads.downloads_id IS NULL
);


-- Delete download texts which are not successful content downloads (some
-- extraction errors somehow ended up getting stored in "download_texts" as
-- extracted text)
DELETE FROM download_texts_np
WHERE downloads_id IN (
    SELECT download_texts_np.downloads_id
    FROM download_texts_np
        INNER JOIN downloads
            ON download_texts_np.downloads_id = downloads.downloads_id
    WHERE downloads.state != 'success'
);


-- Create index *only* on the base table (initially invalid)
CREATE UNIQUE INDEX downloads_success_content_downloads_id
    ON ONLY downloads_success_content (downloads_id);


-- Create partition indexes and attach them to the base table's index to make it valid
DO $$
DECLARE
    tables CURSOR FOR
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename LIKE 'downloads_success_content_%'
        ORDER BY tablename;
BEGIN
    FOR table_record IN tables LOOP

        -- Create index on one of the partitions
        EXECUTE '
            CREATE UNIQUE INDEX ' || table_record.tablename || '_downloads_id_idx
                ON ' || table_record.tablename || ' (downloads_id);
        ';

        -- Attach the newly created index to base table
        EXECUTE '
            ALTER INDEX downloads_success_content_downloads_id
                ATTACH PARTITION ' || table_record.tablename || '_downloads_id_idx;
        ';

    END LOOP;
END
$$;


-- Add foreign key constraints from "download_texts" partitions to "downloads_success_content" partitions
DO $$
DECLARE
    tables CURSOR FOR
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename LIKE 'download_texts_p_%'
        ORDER BY tablename;
BEGIN
    FOR table_record IN tables LOOP

        EXECUTE '
            ALTER TABLE ' || table_record.tablename || '
                ADD CONSTRAINT ' || table_record.tablename || '_downloads_id_fkey
                FOREIGN KEY (downloads_id)
                REFERENCES ' || REPLACE(table_record.tablename, 'download_texts_p', 'downloads_success_content') || ' (downloads_id)
                ON DELETE CASCADE;
        ';

    END LOOP;
END
$$;


CREATE OR REPLACE FUNCTION download_texts_p_create_partitions()
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_downloads_id_create_partitions('download_texts_p'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Adding foreign key to created partition "%"...', partition;
        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || partition || '_downloads_id_fkey
                FOREIGN KEY (downloads_id)
                REFERENCES ' || REPLACE(partition, 'download_texts_p', 'downloads_success_content') || ' (downloads_id)
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


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4725;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
