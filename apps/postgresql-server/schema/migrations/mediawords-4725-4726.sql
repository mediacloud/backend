--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4725 and 4726.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4725, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4726, import this SQL file:
--
--     psql mediacloud < mediawords-4725-4726.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--


--
-- Move a chunk of download texts from a non-partitioned "download_texts_np" to a
-- partitioned "download_texts_p".
--
-- Expects starting and ending "download_texts_id" instead of a chunk size in order
-- to avoid index bloat that would happen when reading rows in sequential
-- chunks.
--
-- Returns number of rows that were moved.
--
-- Call this repeatedly to migrate all the data to the partitioned table.
CREATE OR REPLACE FUNCTION move_chunk_of_nonpartitioned_download_texts_to_partitions(
    start_download_texts_id INT,
    end_download_texts_id INT
)
RETURNS INT AS $$

DECLARE
    moved_row_count INT;

BEGIN

    IF NOT (start_download_texts_id < end_download_texts_id) THEN
        RAISE EXCEPTION '"end_download_texts_id" must be bigger than "start_download_texts_id".';
    END IF;


    PERFORM pid
    FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
    WHERE backend_type = 'autovacuum worker'
      AND query ~ 'download_texts';

    RAISE NOTICE
        'Moving download texts of download_texts_id BETWEEN % AND % to the partitioned table...',
        start_download_texts_id, end_download_texts_id;

    -- Fetch and delete download texts within bounds
    WITH deleted_rows AS (
        DELETE FROM download_texts_np
        WHERE download_texts_np_id BETWEEN start_download_texts_id AND end_download_texts_id
        RETURNING download_texts_np.*
    )

    -- Insert rows to the partitioned table
    INSERT INTO download_texts_p (
        download_texts_p_id,
        downloads_id,
        download_text,
        download_text_length
    )
    SELECT
        download_texts_np_id,
        downloads_id,
        download_text,
        download_text_length
    FROM deleted_rows;

    GET DIAGNOSTICS moved_row_count = ROW_COUNT;

    RAISE NOTICE
        'Done moving download texts of download_texts_id BETWEEN % AND % to the partitioned table, moved % rows.',
        start_download_texts_id, end_download_texts_id, moved_row_count;

    RETURN moved_row_count;

END;
$$
LANGUAGE plpgsql;


-- Move all of the rows in a migration
-- (obviously, this wouldn't work in a production so this migration is to be
-- applied automatically only in the dev environments)
SELECT move_chunk_of_nonpartitioned_download_texts_to_partitions(1, MAX(download_texts_np_id) + 1)
FROM download_texts_np;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4726;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
