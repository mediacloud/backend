--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4519 and 4520.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4519, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4520, import this SQL file:
--
--     psql mediacloud < mediawords-4519-4520.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


ALTER TABLE bitly_processing_results
    ADD COLUMN collect_date TIMESTAMP NULL DEFAULT NOW();

-- Set to NULL for all the current data because we don't know the exact collection date
UPDATE bitly_processing_results
    SET collect_date = NULL;


--
-- Bit.ly total story click counts
--

-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE bitly_clicks_total (
    bitly_clicks_id   BIGSERIAL NOT NULL,
    stories_id        INT       NOT NULL,

    -- Date when click data was collected (usually 3 days or 30 days since stories.publish_date)
    -- (NULL for Bit.ly click data that was collected for controversies)
    collect_date      DATE      NULL,

    -- Total click count that was aggregated at "collect_date"
    click_count       INT       NOT NULL
);

-- Automatic Bit.ly total click count partitioning to stories_id chunks of 1m rows
CREATE OR REPLACE FUNCTION bitly_clicks_total_partition_by_stories_id_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_total_000001")
    target_table_owner TEXT;      -- partition table owner (e.g. "mediaclouduser")

    chunk_size CONSTANT INT := 1000000;           -- 1m stories in a chunk
    to_char_format CONSTANT TEXT := '000000';     -- Up to 1m of chunks, suffixed as "_000001", ..., "_999999"

    stories_id_chunk_number INT;  -- millions part of stories_id (e.g. 30 for stories_id = 30,000,000)
    stories_id_start INT;         -- stories_id chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_end INT;           -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
BEGIN

    SELECT NEW.stories_id / chunk_size INTO stories_id_chunk_number;
    SELECT 'bitly_clicks_total_' || trim(leading ' ' from to_char(stories_id_chunk_number, to_char_format))
        INTO target_table_name;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables 
        WHERE table_schema = current_schema()
          AND table_name = target_table_name
    ) THEN

        SELECT (NEW.stories_id / chunk_size) * chunk_size INTO stories_id_start;
        SELECT ((NEW.stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

        EXECUTE '
            CREATE TABLE ' || target_table_name || ' (
                CHECK (
                    stories_id >= ''' || stories_id_start || '''
                AND stories_id <  ''' || stories_id_end   || ''')
            ) INHERITS (bitly_clicks_total);
        ';

        EXECUTE '
            ALTER TABLE ' || target_table_name || '
                ADD CONSTRAINT ' || target_table_name || '_stories_id_fkey
                FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL;
        ';

        EXECUTE '
            CREATE UNIQUE INDEX ' || target_table_name || '_stories_id
            ON ' || target_table_name || ' (stories_id);
        ';

        -- Update owner
        SELECT u.usename AS owner
        FROM information_schema.tables AS t
            JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
            JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
        WHERE t.table_name = 'bitly_clicks_total'
          AND t.table_schema = 'public'
        INTO target_table_owner;

        EXECUTE 'ALTER TABLE ' || target_table_name || ' OWNER TO ' || target_table_owner || ';';

    END IF;

    EXECUTE '
        INSERT INTO ' || target_table_name || ' (stories_id, collect_date, click_count)
        VALUES ($1, $2, $3);
    ' USING NEW.stories_id, NEW.collect_date, NEW.click_count;

    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER bitly_clicks_total_partition_by_stories_id_insert_trigger
    BEFORE INSERT ON bitly_clicks_total
    FOR EACH ROW EXECUTE PROCEDURE bitly_clicks_total_partition_by_stories_id_insert_trigger();


-- Helper to INSERT / UPDATE story's Bit.ly statistics
CREATE OR REPLACE FUNCTION upsert_bitly_clicks_total (
    param_stories_id INT,
    param_collect_date DATE,
    param_click_count INT
) RETURNS VOID AS
$$
BEGIN
    LOOP
        -- Try UPDATing
        UPDATE bitly_clicks_total
            SET click_count = param_click_count,
                collect_date = param_collect_date
            WHERE stories_id = param_stories_id;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO bitly_clicks_total (stories_id, collect_date, click_count)
            VALUES (param_stories_id, param_collect_date, param_click_count);
            RETURN;
        EXCEPTION WHEN UNIQUE_VIOLATION THEN
            -- If someone else INSERTs the same key concurrently,
            -- we will get a unique-key failure. In that case, do
            -- nothing and loop to try the UPDATE again.
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;


--
-- Bit.ly daily story click counts
--

-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE bitly_clicks_daily (
    bitly_clicks_id   BIGSERIAL NOT NULL,
    stories_id        INT       NOT NULL,

    -- Day
    day               DATE      NOT NULL,

    -- Click count for that day
    click_count       INT       NOT NULL
);

-- Automatic Bit.ly daily click count partitioning to stories_id chunks of 1m rows
CREATE OR REPLACE FUNCTION bitly_clicks_daily_partition_by_stories_id_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_daily_000001")
    target_table_owner TEXT;      -- partition table owner (e.g. "mediaclouduser")

    chunk_size CONSTANT INT := 1000000;           -- 1m stories in a chunk
    to_char_format CONSTANT TEXT := '000000';     -- Up to 1m of chunks, suffixed as "_000001", ..., "_999999"

    stories_id_chunk_number INT;  -- millions part of stories_id (e.g. 30 for stories_id = 30,000,000)
    stories_id_start INT;         -- stories_id chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_end INT;           -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
BEGIN

    SELECT NEW.stories_id / chunk_size INTO stories_id_chunk_number;
    SELECT 'bitly_clicks_daily_' || trim(leading ' ' from to_char(stories_id_chunk_number, to_char_format))
        INTO target_table_name;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables 
        WHERE table_schema = current_schema()
          AND table_name = target_table_name
    ) THEN

        SELECT (NEW.stories_id / chunk_size) * chunk_size INTO stories_id_start;
        SELECT ((NEW.stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

        EXECUTE '
            CREATE TABLE ' || target_table_name || ' (
                CHECK (
                    stories_id >= ''' || stories_id_start || '''
                AND stories_id <  ''' || stories_id_end   || ''')
            ) INHERITS (bitly_clicks_daily);
        ';

        EXECUTE '
            ALTER TABLE ' || target_table_name || '
                ADD CONSTRAINT ' || target_table_name || '_stories_id_fkey
                FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL;
        ';

        EXECUTE '
            CREATE UNIQUE INDEX ' || target_table_name || '_stories_id
            ON ' || target_table_name || ' (stories_id);
        ';

        -- To ensure uniqueness
        EXECUTE '
            CREATE UNIQUE INDEX ' || target_table_name || '_stories_id_day
            ON ' || target_table_name || ' (stories_id, day);
        ';

        -- Update owner
        SELECT u.usename AS owner
        FROM information_schema.tables AS t
            JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
            JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
        WHERE t.table_name = 'bitly_clicks_daily'
          AND t.table_schema = 'public'
        INTO target_table_owner;

        EXECUTE 'ALTER TABLE ' || target_table_name || ' OWNER TO ' || target_table_owner || ';';

    END IF;

    EXECUTE '
        INSERT INTO ' || target_table_name || ' (stories_id, day, click_count)
        VALUES ($1, $2, $3);
    ' USING NEW.stories_id, NEW.day, NEW.click_count;

    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER bitly_clicks_daily_partition_by_stories_id_insert_trigger
    BEFORE INSERT ON bitly_clicks_daily
    FOR EACH ROW EXECUTE PROCEDURE bitly_clicks_daily_partition_by_stories_id_insert_trigger();


-- Helper to INSERT / UPDATE story's Bit.ly statistics
CREATE OR REPLACE FUNCTION upsert_bitly_clicks_daily (
    param_stories_id INT,
    param_day DATE,
    param_click_count INT
) RETURNS VOID AS
$$
BEGIN
    LOOP
        -- Try UPDATing
        UPDATE bitly_clicks_daily
            SET click_count = param_click_count
            WHERE stories_id = param_stories_id
              AND day = param_day;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO bitly_clicks_daily (stories_id, day, click_count)
            VALUES (param_stories_id, param_day, param_click_count);
            RETURN;
        EXCEPTION WHEN UNIQUE_VIOLATION THEN
            -- If someone else INSERTs the same key concurrently,
            -- we will get a unique-key failure. In that case, do
            -- nothing and loop to try the UPDATE again.
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;


-- Helper to return a number of stories for which we don't have Bit.ly statistics yet
DROP FUNCTION num_controversy_stories_without_bitly_statistics(INT);
CREATE FUNCTION num_controversy_stories_without_bitly_statistics (param_controversies_id INT) RETURNS INT AS
$$
DECLARE
    controversy_exists BOOL;
    num_stories_without_bitly_statistics INT;
BEGIN

    SELECT 1 INTO controversy_exists
    FROM controversies
    WHERE controversies_id = param_controversies_id
      AND process_with_bitly = 't';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Controversy % does not exist or is not set up for Bit.ly processing.', param_controversies_id;
        RETURN FALSE;
    END IF;

    SELECT COUNT(stories_id) INTO num_stories_without_bitly_statistics
    FROM controversy_stories
    WHERE controversies_id = param_controversies_id
      AND stories_id NOT IN (
        SELECT stories_id
        FROM bitly_clicks_total
    )
    GROUP BY controversies_id;
    IF NOT FOUND THEN
        num_stories_without_bitly_statistics := 0;
    END IF;

    RETURN num_stories_without_bitly_statistics;
END;
$$
LANGUAGE plpgsql;


-- Migrate old data to the new partitioned table infrastructure and drop it afterwards
-- (might take up ~6 minutes or so)
DROP FUNCTION IF EXISTS upsert_story_bitly_statistics(INT, INT);
DROP FUNCTION IF EXISTS upsert_story_bitly_statistics(INT, INT, INT);

INSERT INTO bitly_clicks_total (stories_id, collect_date, click_count)
    SELECT stories_id, NULL, bitly_click_count
    FROM story_bitly_statistics;

DROP TABLE story_bitly_statistics;



CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4520;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

