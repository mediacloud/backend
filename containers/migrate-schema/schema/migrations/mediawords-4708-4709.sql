--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4708 and 4709.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4708, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4709, import this SQL file:
--
--     psql mediacloud < mediawords-4708-4709.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


--
-- Due to a missing downloads.stories_id -> stories.stories_id foreign key in
-- production, some downloads in the non-partitioned "downloads_np" table don't
-- have a story that they point to.
--
-- The partitioned table reintroduces
-- downloads.stories_id -> stories.stories_id foreign key, so in order to move
-- rows from a non-partitioned table to a partitioned one and not break this
-- constraint, we'll move rows from "downloads_np" with no matching story to
-- this table.
--
CREATE TABLE downloads_np_with_no_matching_story
    AS TABLE downloads_np
    WITH NO DATA;

CREATE UNIQUE INDEX downloads_np_with_no_matching_story_downloads_np_id
    ON downloads_np_with_no_matching_story (downloads_np_id);


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
            FROM downloads_np
            WHERE downloads_np_id BETWEEN start_downloads_id AND end_downloads_id
              AND stories_id IS NOT NULL
              AND NOT EXISTS (
                SELECT stories_id
                FROM stories
                WHERE downloads_np.stories_id = stories.stories_id
            )
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
        WHERE downloads_np_id BETWEEN start_downloads_id AND end_downloads_id
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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4709;
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
