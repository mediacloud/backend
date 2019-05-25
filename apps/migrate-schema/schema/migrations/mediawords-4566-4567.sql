--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4566 and 4567.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4566, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4567, import this SQL file:
--
--     psql mediacloud < mediawords-4566-4567.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

CREATE OR REPLACE FUNCTION bitly_partition_chunk_size()
RETURNS integer AS $$
BEGIN
    RETURN 1000000;
END; $$
LANGUAGE plpgsql IMMUTABLE;

create or replace function bitly_get_partition_name( stories_id int, table_name text )
returns text as $$
declare
    to_char_format CONSTANT TEXT := '000000';     -- Up to 1m of chunks, suffixed as "_000001", ..., "_999999"

    stories_id_chunk_number int;

    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_daily_000001")

begin
    select stories_id / bitly_partition_chunk_size() INTO stories_id_chunk_number;

    select table_name || '_' || trim(leading ' ' from to_char(stories_id_chunk_number, to_char_format))
        into target_table_name;

    return target_table_name;
END;
$$
LANGUAGE plpgsql;

-- Automatic Bit.ly total click count partitioning to stories_id chunks of 1m rows
CREATE OR REPLACE FUNCTION bitly_clicks_total_partition_by_stories_id_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_total_000001")
    target_table_owner TEXT;      -- partition table owner (e.g. "mediaclouduser")

    stories_id_start INT;         -- stories_id chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_end INT;           -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
BEGIN

    select bitly_get_partition_name( NEW.stories_id, 'bitly_clicks_total' ) into target_table_name;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = current_schema()
          AND table_name = target_table_name
    ) THEN

        SELECT (NEW.stories_id / bitly_partition_chunk_size() ) * bitly_partition_chunk_size() INTO stories_id_start;
        SELECT ((NEW.stories_id / bitly_partition_chunk_size()) + 1) * bitly_partition_chunk_size() INTO stories_id_end;

        EXECUTE '
            CREATE TABLE ' || target_table_name || ' (

                -- Primary key
                CONSTRAINT ' || target_table_name || '_pkey
                    PRIMARY KEY (bitly_clicks_id),

                -- Partition by stories_id
                CONSTRAINT ' || target_table_name || '_stories_id CHECK (
                    stories_id >= ''' || stories_id_start || '''
                AND stories_id <  ''' || stories_id_end   || '''),

                -- Foreign key to stories.stories_id
                CONSTRAINT ' || target_table_name || '_stories_id_fkey
                    FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL,

                -- Unique duplets
                CONSTRAINT ' || target_table_name || '_stories_id_unique
                    UNIQUE (stories_id)

            ) INHERITS (bitly_clicks_total);
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
        INSERT INTO ' || target_table_name || '
            SELECT $1.*;
    ' USING NEW;

    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

-- Helper to INSERT / UPDATE story's Bit.ly statistics
CREATE OR REPLACE FUNCTION upsert_bitly_clicks_total (
    param_stories_id INT,
    param_click_count INT
) RETURNS VOID AS
$$
DECLARE
    partition_name text;
    update_count int;
BEGIN

    select bitly_get_partition_name( param_stories_id, 'bitly_clicks_total' ) into partition_name;

    LOOP
        EXECUTE '
            UPDATE ' || partition_name || '
                SET click_count = ' || param_click_count || '
                WHERE stories_id = ' || param_stories_id;
        get diagnostics update_count = ROW_COUNT;
        IF update_count > 0 THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            EXECUTE '
                INSERT INTO ' || partition_name || ' (stories_id, click_count)
                VALUES (' || param_stories_id || ', ' || param_click_count || ')';
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


CREATE OR REPLACE FUNCTION bitly_clicks_daily_partition_by_stories_id_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_daily_000001")
    target_table_owner TEXT;      -- partition table owner (e.g. "mediaclouduser")

    stories_id_start INT;         -- stories_id chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_end INT;           -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
BEGIN

    select bitly_get_partition_name( NEW.stories_id, 'bitly_clicks_daily' ) into target_table_name;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = current_schema()
          AND table_name = target_table_name
    ) THEN

        SELECT (NEW.stories_id / bitly_partition_chunk_size() ) * bitly_partition_chunk_size() INTO stories_id_start;
        SELECT ((NEW.stories_id / bitly_partition_chunk_size() ) + 1) * bitly_partition_chunk_size() INTO stories_id_end;

        EXECUTE '
            CREATE TABLE ' || target_table_name || ' (

                -- Primary key
                CONSTRAINT ' || target_table_name || '_pkey
                    PRIMARY KEY (bitly_clicks_id),

                -- Partition by stories_id
                CONSTRAINT ' || target_table_name || '_stories_id CHECK (
                    stories_id >= ''' || stories_id_start || '''
                AND stories_id <  ''' || stories_id_end   || '''),

                -- Foreign key to stories.stories_id
                CONSTRAINT ' || target_table_name || '_stories_id_fkey
                    FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL,

                -- Unique duplets
                CONSTRAINT ' || target_table_name || '_stories_id_day_unique
                    UNIQUE (stories_id, day)

            ) INHERITS (bitly_clicks_daily);
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
        INSERT INTO ' || target_table_name || '
            SELECT $1.*;
    ' USING NEW;

    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

-- Helper to INSERT / UPDATE story's Bit.ly statistics
CREATE OR REPLACE FUNCTION upsert_bitly_clicks_daily (
    param_stories_id INT,
    param_day DATE,
    param_click_count INT
) RETURNS VOID AS
$$
DECLARE
    partition_name text;
    update_count int;
BEGIN

    select bitly_get_partition_name( param_stories_id, 'bitly_clicks_daily' ) into partition_name;

    LOOP
        EXECUTE '
            UPDATE ' || partition_name || '
                SET click_count = ' || param_click_count || '
                WHERE stories_id = ' || param_stories_id || '
                  AND day = ''' || param_day || '''';
          get diagnostics update_count = ROW_COUNT;
          IF update_count > 0 THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            EXECUTE '
                INSERT INTO ' || partition_name || ' (stories_id, day, click_count)
                VALUES ( ' || param_stories_id || ', ''' || param_day || ''', ' || param_click_count || ')';
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
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4567;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
