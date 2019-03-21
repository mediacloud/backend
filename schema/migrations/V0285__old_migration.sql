--
-- Kill all autovacuums before proceeding with DDL changes
--
SELECT pid
FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
WHERE backend_type = 'autovacuum worker'
  AND query ~ 'downloads';


--
-- Drop views that use "downloads" to be recreated later
--
DROP VIEW daily_stats;
DROP VIEW downloads_media;
DROP VIEW downloads_non_media;
DROP VIEW downloads_to_be_extracted;
DROP VIEW downloads_with_error_in_past_day;
DROP VIEW downloads_in_past_day;


--
-- Rename enums used by the non-partitioned table (and having obsolete values)
--
ALTER TYPE download_state
    RENAME TO download_np_state;
ALTER TYPE download_type
    RENAME TO download_np_type;


--
-- Rename non-partitioned "downloads" table and its resources to "downloads_np"
--
ALTER TABLE downloads
    RENAME TO downloads_np;

ALTER TABLE downloads_np
    RENAME COLUMN downloads_id TO downloads_np_id;

ALTER INDEX downloads_pkey
    RENAME TO downloads_np_pkey;
ALTER INDEX downloads_parent
    RENAME TO downloads_np_parent;
ALTER INDEX downloads_time
    RENAME TO downloads_np_time;
ALTER INDEX downloads_feed_download_time
    RENAME TO downloads_np_feed_download_time;
ALTER INDEX downloads_story
    RENAME TO downloads_np_story;
ALTER INDEX downloads_story_not_null
    RENAME TO downloads_np_story_not_null;
ALTER INDEX downloads_type
    RENAME TO downloads_np_type;
ALTER INDEX downloads_state_downloads_id_pending
    RENAME TO downloads_np_state_downloads_id_pending;
ALTER INDEX downloads_extracted
    RENAME TO downloads_np_extracted;
ALTER INDEX downloads_stories_to_be_extracted
    RENAME TO downloads_np_stories_to_be_extracted;
ALTER INDEX downloads_extracted_stories
    RENAME TO downloads_np_extracted_stories;
ALTER INDEX downloads_state_queued_or_fetching
    RENAME TO downloads_np_state_queued_or_fetching;
ALTER INDEX downloads_state_fetching
    RENAME TO downloads_np_state_fetching;

ALTER TABLE downloads_np
    RENAME CONSTRAINT downloads_feed_id_valid TO downloads_np_feed_id_valid;
ALTER TABLE downloads_np
    RENAME CONSTRAINT downloads_path TO downloads_np_path;
ALTER TABLE downloads_np
    RENAME CONSTRAINT downloads_story TO downloads_np_story;
ALTER TABLE downloads_np
    RENAME CONSTRAINT valid_download_type TO downloads_np_valid_download_type;
ALTER TABLE downloads_np
    RENAME CONSTRAINT downloads_feeds_id_fkey TO downloads_np_feeds_id_fkey;
ALTER TABLE downloads_np
    RENAME CONSTRAINT downloads_parent_fkey TO downloads_np_parent_fkey;
ALTER TABLE downloads_np
    RENAME CONSTRAINT downloads_stories_id_fkey TO downloads_np_stories_id_fkey;



--
-- Create the partitioned "downloads_p" table
--
CREATE TYPE download_p_state AS ENUM (
    'error',
    'fetching',
    'pending',
    'success',
    'feed_error'
);

CREATE TYPE download_p_type AS ENUM (
    'content',
    'feed'
);


-- Helper for indexing nonpartitioned "downloads.downloads_id" as BIGINT for
-- faster casting
CREATE OR REPLACE FUNCTION to_bigint(p_integer INT) RETURNS BIGINT AS $$
    SELECT p_integer::bigint;
$$ LANGUAGE SQL IMMUTABLE;


-- Convert "download_np_type" (nonpartitioned table's "type" column)
-- to "download_p_type" (partitioned table's "type" column)
CREATE OR REPLACE FUNCTION download_np_type_to_download_p_type(p_type download_np_type)
RETURNS download_p_type
AS $$
    SELECT (
        CASE
            -- Allow only the following types:
            WHEN (p_type = 'content') THEN 'content'
            WHEN (p_type = 'feed') THEN 'feed'

            -- Temporarily expose obsolete types as "content"
            -- (filtering them out in WHERE wouldn't work because then
            -- PostgreSQL decides to do a sequential scan)
            ELSE 'content'
        END
    )::download_p_type;
$$ LANGUAGE SQL IMMUTABLE;


-- Convert "download_np_state" (nonpartitioned table's "state" column)
-- to "download_p_state" (partitioned table's "state" column)
CREATE OR REPLACE FUNCTION download_np_state_to_download_p_state(p_state download_np_state)
RETURNS download_p_state
AS $$
    SELECT (
        CASE
            -- Rewrite obsolete states
            WHEN (p_state = 'queued') THEN 'pending'
            WHEN (p_state = 'extractor_error') THEN 'error'

            -- All the other states are OK
            ELSE p_state::text
        END
    )::download_p_state;
$$ LANGUAGE SQL IMMUTABLE;


-- Create a bunch of extra indexes on the non-partitioned table with columns
-- cast to partitioned table's types for faster querying
CREATE INDEX IF NOT EXISTS downloads_np_pkey_bigint
    ON downloads_np (to_bigint(downloads_np_id));

CREATE INDEX IF NOT EXISTS downloads_np_parent_bigint
    ON downloads_np (to_bigint(parent));

CREATE INDEX IF NOT EXISTS downloads_np_type_p
    ON downloads_np (download_np_type_to_download_p_type(type));

CREATE INDEX IF NOT EXISTS downloads_np_state_p_downloads_id_bigint_pending
    ON downloads_np (download_np_state_to_download_p_state(state), to_bigint(downloads_np_id))
    WHERE download_np_state_to_download_p_state(state) = 'pending';

CREATE INDEX IF NOT EXISTS downloads_np_extracted_p
    ON downloads_np (extracted, download_np_state_to_download_p_state(state), download_np_type_to_download_p_type(type))
    WHERE extracted = 'f'
      AND download_np_state_to_download_p_state(state) = 'success'
      AND download_np_type_to_download_p_type(type) = 'content';

CREATE INDEX IF NOT EXISTS downloads_np_state_p_fetching
    ON downloads_np (download_np_state_to_download_p_state(state), downloads_np_id)
    WHERE download_np_state_to_download_p_state(state) = 'fetching';


CREATE TABLE downloads_p (
    downloads_p_id  BIGSERIAL           NOT NULL,
    feeds_id        INT                 NOT NULL REFERENCES feeds (feeds_id),
    stories_id      INT                 NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    parent          BIGINT              NULL,
    url             TEXT                NOT NULL,
    host            TEXT                NOT NULL,
    download_time   TIMESTAMP           NOT NULL DEFAULT NOW(),
    type            download_p_type     NOT NULL,
    state           download_p_state    NOT NULL,
    path            TEXT                NULL,
    error_message   TEXT                NULL,
    priority        SMALLINT            NOT NULL,
    sequence        SMALLINT            NOT NULL,
    extracted       BOOLEAN             NOT NULL DEFAULT 'f',

    PRIMARY KEY (downloads_p_id, state, type)

) PARTITION BY LIST (state);

-- Make partitioned table's "downloads_id" sequence start from where
-- non-partitioned table's sequence left off
SELECT setval(
    pg_get_serial_sequence('downloads_p', 'downloads_p_id'),
    COALESCE(MAX(downloads_np_id), 1), MAX(downloads_np_id) IS NOT NULL
) FROM downloads_np;


--
-- Create a proxy view to join partitioned and non-partitioned "downloads"
-- tables
--
CREATE OR REPLACE VIEW downloads AS

    -- Non-partitioned table
    SELECT
        downloads_np_id::bigint AS downloads_id,
        feeds_id,
        stories_id,
        parent::bigint,
        url::text,
        host::text,
        download_time,
        download_np_type_to_download_p_type(type) AS type,
        download_np_state_to_download_p_state(state) AS state,
        path::text,
        error_message::text,
        priority::smallint,
        sequence::smallint,
        extracted
    FROM downloads_np

    UNION ALL

    -- Partitioned table
    SELECT
        downloads_p_id AS downloads_id,
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
    FROM downloads_p;

-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW downloads
    ALTER COLUMN downloads_id
    SET DEFAULT nextval(pg_get_serial_sequence('downloads_p', 'downloads_p_id'));

-- Prevent the next INSERT from failing
SELECT nextval(pg_get_serial_sequence('downloads_p', 'downloads_p_id'));


-- Trigger that implements INSERT / UPDATE / DELETE behavior on "downloads" view
CREATE OR REPLACE FUNCTION downloads_view_insert_update_delete() RETURNS trigger AS $$
BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- New rows go into the partitioned table only
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
        ) SELECT
            NEW.downloads_id,
            NEW.feeds_id,
            NEW.stories_id,
            NEW.parent,
            NEW.url,
            NEW.host,
            COALESCE(NEW.download_time, NOW()),
            NEW.type,
            NEW.state,
            NEW.path,
            NEW.error_message,
            NEW.priority,
            NEW.sequence,
            COALESCE(NEW.extracted, 'f');

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        -- Update both tables as one of them will have the row
        UPDATE downloads_np SET
            downloads_np_id = NEW.downloads_id,
            feeds_id = NEW.feeds_id,
            stories_id = NEW.stories_id,
            parent = NEW.parent,
            url = NEW.url,
            host = NEW.host,
            download_time = NEW.download_time,
            type = NEW.type::text::download_np_type,
            state = NEW.state::text::download_np_state,
            path = NEW.path,
            error_message = NEW.error_message,
            priority = NEW.priority,
            sequence = NEW.sequence,
            extracted = NEW.extracted
        WHERE downloads_np_id = OLD.downloads_id;

        UPDATE downloads_p SET
            downloads_p_id = NEW.downloads_id,
            feeds_id = NEW.feeds_id,
            stories_id = NEW.stories_id,
            parent = NEW.parent_id,
            url = NEW.url,
            host = NEW.host,
            download_time = NEW.download_time,
            type = NEW.type,
            state = NEW.state,
            path = NEW.path,
            error_message = NEW.error_message,
            priority = NEW.priority,
            sequence = NEW.sequence,
            extracted = NEW.extracted
        WHERE downloads_p_id = OLD.downloads_id;

        -- Update record in tables that reference "downloads" with a given ID
        UPDATE downloads_np
        SET parent = NEW.downloads_id
        WHERE parent = OLD.downloads_id;

        UPDATE downloads_p
        SET parent = NEW.downloads_id
        WHERE parent = OLD.downloads_id;

        UPDATE raw_downloads
        SET object_id = NEW.downloads_id
        WHERE object_id = OLD.downloads_id;

        UPDATE download_texts
        SET downloads_id = NEW.downloads_id
        WHERE downloads_id = OLD.downloads_id;

        UPDATE cached_extractor_results
        SET downloads_id = NEW.downloads_id
        WHERE downloads_id = OLD.downloads_id;

        UPDATE cache.s3_raw_downloads_cache
        SET object_id = NEW.downloads_id
        WHERE object_id = OLD.downloads_id;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        -- Delete from both tables as one of them will have the row
        DELETE FROM downloads_np
            WHERE downloads_np_id = OLD.downloads_id;

        DELETE FROM downloads_p
            WHERE downloads_p_id = OLD.downloads_id;

        -- Update / delete record in tables that reference "downloads" with a
        -- given ID
        UPDATE downloads_np
        SET parent = NULL
        WHERE parent = OLD.downloads_id;

        UPDATE downloads_p
        SET parent = NULL
        WHERE parent = OLD.downloads_id;

        DELETE FROM raw_downloads
        WHERE object_id = OLD.downloads_id;

        DELETE FROM download_texts
        WHERE downloads_id = OLD.downloads_id;

        DELETE FROM cached_extractor_results
        WHERE downloads_id = OLD.downloads_id;

        DELETE FROM cache.s3_raw_downloads_cache
        WHERE object_id = OLD.downloads_id;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER downloads_view_insert_update_delete_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE ON downloads
    FOR EACH ROW EXECUTE PROCEDURE downloads_view_insert_update_delete();


-- Imitate a foreign key by testing if a download with an INSERTed / UPDATEd
-- "downloads_id" exists in "downloads"
--
-- Partitioned tables don't support foreign keys being pointed to them, so this
-- trigger achieves the same referential integrity for tables that point to
-- "downloads".
--
-- Column name from NEW (NEW.<column_name>) that contains the
-- INSERTed / UPDATEd "downloads_id" should be passed as an trigger argument.
CREATE OR REPLACE FUNCTION test_referenced_download_trigger()
RETURNS TRIGGER AS $$
DECLARE
    param_column_name TEXT;
    param_downloads_id BIGINT;
BEGIN

    IF TG_NARGS != 1 THEN
        RAISE EXCEPTION 'Trigger should be called with an column name argument.';
    END IF;

    SELECT TG_ARGV[0] INTO param_column_name;
    SELECT to_json(NEW) ->> param_column_name INTO param_downloads_id;

    -- Might be NULL, e.g. downloads.parent
    IF (param_downloads_id IS NOT NULL) THEN

        IF NOT EXISTS (
            SELECT 1
            FROM downloads
            WHERE downloads_id = param_downloads_id
        ) THEN
            RAISE EXCEPTION 'Referenced download ID % from column "%" does not exist in "downloads".', param_downloads_id, param_column_name;
        END IF;

    END IF;

    RETURN NEW;

END;
$$
LANGUAGE plpgsql;


--
-- Create indexes and partitions of the partitioned "downloads_p" table
--
CREATE INDEX downloads_p_parent
    ON downloads_p (parent);

CREATE INDEX downloads_time_p
    ON downloads_p (download_time);

CREATE INDEX downloads_p_feed_download_time
    ON downloads_p (feeds_id, download_time);

CREATE INDEX downloads_p_story
    ON downloads_p (stories_id);


CREATE TABLE downloads_p_error
    PARTITION OF downloads_p
    FOR VALUES IN ('error');

CREATE TRIGGER downloads_p_error_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON downloads_p_error
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('parent');


CREATE TABLE downloads_p_feed_error
    PARTITION OF downloads_p
    FOR VALUES IN ('feed_error');

CREATE TRIGGER downloads_p_feed_error_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON downloads_p_feed_error
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('parent');


CREATE TABLE downloads_p_fetching
    PARTITION OF downloads_p
    FOR VALUES IN ('fetching');

CREATE TRIGGER downloads_p_fetching_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON downloads_p_fetching
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('parent');


CREATE TABLE downloads_p_pending
    PARTITION OF downloads_p
    FOR VALUES IN ('pending');

CREATE TRIGGER downloads_p_pending_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON downloads_p_pending
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('parent');


CREATE TABLE downloads_p_success
    PARTITION OF downloads_p (
        CONSTRAINT downloads_p_success_path_not_null
        CHECK (path IS NOT NULL)
    ) FOR VALUES IN ('success')
    PARTITION BY LIST (type);


CREATE TABLE downloads_p_success_feed
    PARTITION OF downloads_p_success (
        CONSTRAINT downloads_p_success_feed_stories_id_null
        CHECK (stories_id IS NULL)
    ) FOR VALUES IN ('feed')
    PARTITION BY RANGE (downloads_p_id);


CREATE TABLE downloads_p_success_content
    PARTITION OF downloads_p_success (
        CONSTRAINT downloads_p_success_content_stories_id_not_null
        CHECK (stories_id IS NOT NULL)
    ) FOR VALUES IN ('content')
    PARTITION BY RANGE (downloads_p_id);

CREATE INDEX downloads_p_success_content_extracted
    ON downloads_p_success_content (extracted);


--
-- Recreate views dropped previously that use "downloads"
--

CREATE VIEW downloads_media AS
    SELECT
        d.*,
        f.media_id AS _media_id
    FROM
        downloads AS d,
        feeds AS f
    WHERE d.feeds_id = f.feeds_id;

CREATE VIEW downloads_non_media AS
    SELECT d.*
    FROM downloads AS d
    WHERE d.feeds_id IS NULL;

CREATE VIEW downloads_to_be_extracted AS
    SELECT *
    FROM downloads
    WHERE extracted = 'f'
      AND state = 'success'
      AND type = 'content';

CREATE VIEW downloads_in_past_day AS
    SELECT *
    FROM downloads
    WHERE download_time > NOW() - interval '1 day';

CREATE VIEW downloads_with_error_in_past_day AS
    SELECT *
    FROM downloads_in_past_day
    WHERE state = 'error';

CREATE VIEW daily_stats AS
    SELECT *
    FROM (
            SELECT COUNT(*) AS daily_downloads
            FROM downloads_in_past_day
         ) AS dd,
         (
            SELECT COUNT(*) AS daily_stories
            FROM stories_collected_in_past_day
         ) AS ds,
         (
            SELECT COUNT(*) AS downloads_to_be_extracted
            FROM downloads_to_be_extracted
         ) AS dex,
         (
            SELECT COUNT(*) AS download_errors
            FROM downloads_with_error_in_past_day
         ) AS er,
         (
            SELECT COALESCE( SUM( num_stories ), 0  ) AS solr_stories
            FROM solr_imports WHERE import_date > now() - interval '1 day'
         ) AS si;


--
-- Create partitioning tools for tables partitioned by "downloads_id"
--

-- Return partition size for every table that is partitioned by "downloads_id"
CREATE OR REPLACE FUNCTION partition_by_downloads_id_chunk_size()
RETURNS BIGINT AS $$
BEGIN
    RETURN 100 * 1000 * 1000;   -- 100m downloads in each partition
END; $$
LANGUAGE plpgsql IMMUTABLE;


-- Return partition table name for a given base table name and "downloads_id"
CREATE OR REPLACE FUNCTION partition_by_downloads_id_partition_name(
    base_table_name TEXT,
    downloads_id BIGINT
) RETURNS TEXT AS $$
BEGIN

    RETURN partition_name(
        base_table_name := base_table_name,
        chunk_size := partition_by_downloads_id_chunk_size(),
        object_id := downloads_id
    );

END;
$$
LANGUAGE plpgsql IMMUTABLE;

-- Create missing partitions for tables partitioned by "downloads_id", returning
-- a list of created partition tables
CREATE OR REPLACE FUNCTION partition_by_downloads_id_create_partitions(base_table_name TEXT)
RETURNS SETOF TEXT AS
$$
DECLARE
    chunk_size INT;
    max_downloads_id BIGINT;
    partition_downloads_id BIGINT;

    -- Partition table name (e.g. "downloads_success_content_01")
    target_table_name TEXT;

    -- Partition table owner (e.g. "mediaclouduser")
    target_table_owner TEXT;

    -- "downloads_id" chunk lower limit, inclusive (e.g. 30,000,000)
    downloads_id_start BIGINT;

    -- "downloads_id" chunk upper limit, exclusive (e.g. 31,000,000)
    downloads_id_end BIGINT;
BEGIN

    SELECT partition_by_downloads_id_chunk_size() INTO chunk_size;

    -- Create +1 partition for future insertions
    SELECT COALESCE(MAX(downloads_id), 0) + chunk_size FROM downloads INTO max_downloads_id;

    FOR partition_downloads_id IN 1..max_downloads_id BY chunk_size LOOP
        SELECT partition_by_downloads_id_partition_name(
            base_table_name := base_table_name,
            downloads_id := partition_downloads_id
        ) INTO target_table_name;
        IF table_exists(target_table_name) THEN
            RAISE NOTICE 'Partition "%" for download ID % already exists.', target_table_name, partition_downloads_id;
        ELSE
            RAISE NOTICE 'Creating partition "%" for download ID %', target_table_name, partition_downloads_id;

            SELECT (partition_downloads_id / chunk_size) * chunk_size INTO downloads_id_start;
            SELECT ((partition_downloads_id / chunk_size) + 1) * chunk_size INTO downloads_id_end;

            EXECUTE '
                CREATE TABLE ' || target_table_name || '
                    PARTITION OF ' || base_table_name || '
                    FOR VALUES FROM (' || downloads_id_start || ')
                               TO   (' || downloads_id_end   || ');
            ';

            EXECUTE '
                CREATE TRIGGER ' || target_table_name || '_test_referenced_download_trigger
                    BEFORE INSERT OR UPDATE ON ' || target_table_name || '
                    FOR EACH ROW
                    EXECUTE PROCEDURE test_referenced_download_trigger(''parent'');
            ';

            -- Update owner
            SELECT u.usename AS owner
            FROM information_schema.tables AS t
                JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
                JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
            WHERE t.table_name = base_table_name
              AND t.table_schema = 'public'
            INTO target_table_owner;

            EXECUTE '
                ALTER TABLE ' || target_table_name || '
                    OWNER TO ' || target_table_owner || ';
            ';

            -- Add created partition name to the list of returned partition names
            RETURN NEXT target_table_name;

        END IF;
    END LOOP;

    RETURN;

END;
$$
LANGUAGE plpgsql;


-- Create missing "downloads_success_content" partitions
CREATE OR REPLACE FUNCTION downloads_p_success_content_create_partitions()
RETURNS VOID AS
$$

    SELECT partition_by_downloads_id_create_partitions('downloads_p_success_content');

$$
LANGUAGE SQL;

-- Create initial "downloads_success_content" partitions for empty database
SELECT downloads_p_success_content_create_partitions();


-- Create missing "downloads_success_feed" partitions
CREATE OR REPLACE FUNCTION downloads_p_success_feed_create_partitions()
RETURNS VOID AS
$$

    SELECT partition_by_downloads_id_create_partitions('downloads_p_success_feed');

$$
LANGUAGE SQL;

-- Create initial "downloads_success_feed" partitions for empty database
SELECT downloads_p_success_feed_create_partitions();


--
-- Recreate function that creates partitions to take care of partitioned
-- "downloads" too
--

-- Create missing partitions for partitioned tables
CREATE OR REPLACE FUNCTION create_missing_partitions()
RETURNS VOID AS
$$
BEGIN

    RAISE NOTICE 'Creating partitions in "downloads_p_success_content" table...';
    PERFORM downloads_p_success_content_create_partitions();

    RAISE NOTICE 'Creating partitions in "downloads_p_success_feed" table...';
    PERFORM downloads_p_success_feed_create_partitions();

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
-- Drop foreign keys pointing to the non-partitioned table, imitate them by
-- adding triggers
--

ALTER TABLE raw_downloads
    DROP CONSTRAINT raw_downloads_downloads_id_fkey;

CREATE TRIGGER raw_downloads_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON raw_downloads
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('object_id');

ALTER TABLE download_texts
    DROP CONSTRAINT download_texts_downloads_id_fkey;

CREATE TRIGGER download_texts_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON download_texts
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('downloads_id');

-- "cached_extractor_results" didn't have a foreign key reference to "downloads"

CREATE TRIGGER cached_extractor_results_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON cached_extractor_results
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('downloads_id');

ALTER TABLE cache.s3_raw_downloads_cache
    DROP CONSTRAINT s3_raw_downloads_cache_object_id_fkey;

CREATE TRIGGER s3_raw_downloads_cache_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON cache.s3_raw_downloads_cache
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('object_id');


--
-- Move a chunk of downloads from a non-partitioned "downloads_np" to a
-- partitioned "downloads_p".
--
-- Expects starting and ending "downloads_id" instead of a chunk size in order
-- to avoid index bloat that would happen when reading rows in sequential
-- chunks.
--
-- Returns number of rows that were moved.
--
-- Call this repeatedly to migrate all the data to the partitioned table.
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

    -- Kill all autovacuums before proceeding with DDL changes
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
        'Finished moving downloads of downloads_id BETWEEN % AND % to the partitioned table, moved % rows.',
        start_downloads_id, end_downloads_id, moved_row_count;

    RETURN moved_row_count;

END;
$$
LANGUAGE plpgsql;
