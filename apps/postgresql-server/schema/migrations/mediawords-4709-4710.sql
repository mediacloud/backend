--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4709 and 4710.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4709, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4710, import this SQL file:
--
--     psql mediacloud < mediawords-4709-4710.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


CREATE OR REPLACE FUNCTION move_chunk_of_nonpartitioned_downloads_to_partitions(
    start_downloads_id INT,
    end_downloads_id INT
)
RETURNS INT AS $$

DECLARE
    moved_row_count INT;

BEGIN

    IF NOT (start_downloads_id < end_downloads_id) THEN
        RAISE EXCEPTION '"end_downloads_id" must be bigger than "start_downloads_id".';
    END IF;


    RAISE NOTICE 'Creating a table of downloads BETWEEN % AND %...',
        start_downloads_id, end_downloads_id;

    -- For whatever reason (table stats way off? Too many tables referencing
    -- "stories"? Bloated "downloads_np" primary key index so QP can't do
    -- MAX(downloads_np_id)?), query planner (not the query itself!) runs for
    -- the whole 6 or so minutes if we try to do
    -- "FROM downloads_np LEFT JOIN stories" (to test for downloads with no
    -- matching story).
    --
    -- Everything seems to be snappier when we create a temporary table with
    -- row IDs to be moved first.
    CREATE TEMPORARY TABLE temp_downloads_np_chunk AS
        SELECT downloads_np_id, stories_id
        FROM downloads_np
        WHERE downloads_np_id BETWEEN start_downloads_id AND end_downloads_id;


    PERFORM pid
    FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
    WHERE backend_type = 'autovacuum worker'
      AND query ~ 'downloads';

    RAISE NOTICE 'Moving away downloads BETWEEN % AND % with no matching story...',
        start_downloads_id, end_downloads_id;

    WITH deleted_rows AS (
        DELETE FROM downloads_np
        WHERE downloads_np_id IN (
            SELECT downloads_np_id
            FROM temp_downloads_np_chunk AS td
                LEFT JOIN stories AS s
                    ON td.stories_id = s.stories_id
            WHERE td.stories_id IS NOT NULL
              AND s.stories_id IS NULL
        )
        RETURNING *
    )
    INSERT INTO downloads_np_with_no_matching_story
        SELECT *
        FROM deleted_rows;

    GET DIAGNOSTICS moved_row_count = ROW_COUNT;

    RAISE NOTICE 'Done moving away downloads BETWEEN % AND % with no matching story, moved % rows.',
        start_downloads_id, end_downloads_id, moved_row_count;


    PERFORM pid
    FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
    WHERE backend_type = 'autovacuum worker'
      AND query ~ 'downloads';

    RAISE NOTICE
        'Moving downloads of downloads_id BETWEEN % AND % to the partitioned table...',
        start_downloads_id, end_downloads_id;

    -- Fetch and delete downloads within bounds
    WITH deleted_rows AS (
        DELETE FROM downloads_np
        WHERE downloads_np_id IN (
            SELECT downloads_np_id
            FROM temp_downloads_np_chunk
        )
        RETURNING downloads_np.*
    )

    -- Insert rows to the partitioned table
    INSERT INTO downloads_p (
        downloads_p_id,
        feeds_id,
        stories_id,
        parent,
        url,
        host,
        download_time,
        type,
        state,
        path,
        error_message,
        priority,
        sequence,
        extracted
    )
    SELECT
        downloads_np_id,
        feeds_id,
        stories_id,
        parent,
        url,
        host,
        download_time,
        download_np_type_to_download_p_type(type) AS type,
        download_np_state_to_download_p_state(state) AS state,
        path,
        error_message,
        priority,
        sequence,
        extracted
    FROM deleted_rows
    WHERE type IN ('content', 'feed');  -- Skip obsolete types like 'Calais'

    GET DIAGNOSTICS moved_row_count = ROW_COUNT;

    RAISE NOTICE
        'Done moving downloads of downloads_id BETWEEN % AND % to the partitioned table, moved % rows.',
        start_downloads_id, end_downloads_id, moved_row_count;


    DROP TABLE temp_downloads_np_chunk;


    RETURN moved_row_count;

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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4710;
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
