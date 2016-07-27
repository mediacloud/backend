--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4570 and 4571.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4570, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4571, import this SQL file:
--
--     psql mediacloud < mediawords-4570-4571.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


CREATE OR REPLACE FUNCTION bitly_partition_chunk_size() RETURNS integer AS $$
BEGIN
    RETURN 100 * 1000 * 1000;   -- 100m rows in each partition
END; $$
LANGUAGE plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION bitly_get_partition_name(stories_id INT, table_name TEXT) RETURNS TEXT AS $$
DECLARE
    to_char_format CONSTANT TEXT := '00';     -- Up to 100 partitions, suffixed as "_00", "_01" ..., "_99"
                                              -- (having more of them is not feasible)
    stories_id_chunk_number INT;

    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_total_000001")
BEGIN
    SELECT stories_id / bitly_partition_chunk_size() INTO stories_id_chunk_number;

    SELECT table_name || '_' || trim(leading ' ' FROM to_char(stories_id_chunk_number, to_char_format))
        INTO target_table_name;

    RETURN target_table_name;
END;
$$
LANGUAGE plpgsql;


-- Migrate old 1m partitions to the new 100m ones
DO $$
DECLARE
    final_table_name CONSTANT TEXT := 'bitly_clicks_total';
    temp_table_name CONSTANT TEXT  := 'temp_bitly_clicks_total';

    chunk_size INT;
    max_stories_id BIGINT;

    target_temp_table_name TEXT;        -- partition table name (e.g. "temp_bitly_clicks_total_000001")
    target_final_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_total_000001")

    target_table_owner TEXT;      -- partition table owner (e.g. "mediaclouduser")

    stories_id_start INT;         -- stories_id chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_end INT;           -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
BEGIN

    SELECT bitly_partition_chunk_size() INTO chunk_size;

    -- Create +1 partition for future insertions
    SELECT COALESCE(MAX(stories_id), 0) + chunk_size FROM stories INTO max_stories_id;
    RAISE NOTICE 'Will create partitions for storing up to % stories.', max_stories_id;
   
    RAISE NOTICE 'Creating temporary master table...';
    EXECUTE 'DROP TABLE IF EXISTS ' || temp_table_name || ' CASCADE;';
    EXECUTE '
        CREATE TABLE ' || temp_table_name || ' (
            bitly_clicks_id   BIGSERIAL NOT NULL,
            stories_id        INT       NOT NULL,
            click_count       INT       NOT NULL
        );
    ';

    RAISE NOTICE 'Creating temporary partitions...';
    FOR partition_stories_id IN 1..max_stories_id BY chunk_size LOOP

        SELECT bitly_get_partition_name( partition_stories_id, temp_table_name ) INTO target_temp_table_name;

        RAISE NOTICE 'Creating partition "%" for story ID %', target_temp_table_name, partition_stories_id;

        SELECT (partition_stories_id / chunk_size) * chunk_size INTO stories_id_start;
        SELECT ((partition_stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

        EXECUTE 'DROP TABLE IF EXISTS ' || target_temp_table_name || ';';
        EXECUTE '
            CREATE TABLE ' || target_temp_table_name || ' (

                -- Primary key
                CONSTRAINT ' || target_temp_table_name || '_pkey
                    PRIMARY KEY (bitly_clicks_id),

                -- Partition by stories_id
                CONSTRAINT ' || target_temp_table_name || '_stories_id CHECK (
                    stories_id >= ''' || stories_id_start || '''
                AND stories_id <  ''' || stories_id_end   || ''')

            ) INHERITS (' || temp_table_name || ');
        ';

        -- Update owner
        SELECT u.usename AS owner
        FROM information_schema.tables AS t
            JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
            JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
        WHERE t.table_name = final_table_name
          AND t.table_schema = 'public'
        INTO target_table_owner;

        EXECUTE 'ALTER TABLE ' || target_temp_table_name || ' OWNER TO ' || target_table_owner || ';';

        RAISE NOTICE 'Copying stories [%; %) from old table...', stories_id_start, stories_id_end;
        EXECUTE '
            INSERT INTO ' || target_temp_table_name || ' (stories_id, click_count)
            SELECT stories_id, click_count FROM ' || final_table_name || '
            WHERE stories_id >= ''' || stories_id_start || '''
              AND stories_id <  ''' || stories_id_end   || ''';
        ';

        RAISE NOTICE 'Creating unique index on "stories_id"...';
        EXECUTE '
            CREATE UNIQUE INDEX ' || target_temp_table_name || '_stories_id_unique
            ON ' || target_temp_table_name || ' (stories_id);
        ';

        RAISE NOTICE 'Creating foreign key to "stories"...';
        EXECUTE '
            ALTER TABLE ' || target_temp_table_name || '
            ADD CONSTRAINT ' || target_temp_table_name || '_stories_id_fkey
            FOREIGN KEY (stories_id) REFERENCES stories (stories_id);
        ';

    END LOOP;

    RAISE NOTICE 'Dropping main table...';
    EXECUTE 'DROP TABLE ' || final_table_name || ' CASCADE';

    RAISE NOTICE 'Renaming temporary table to main table...';
    EXECUTE 'ALTER TABLE ' || temp_table_name || ' RENAME TO ' || final_table_name || ';';
    EXECUTE '
        ALTER SEQUENCE ' || temp_table_name || '_bitly_clicks_id_seq
        RENAME TO ' || final_table_name || '_bitly_clicks_id_seq;
    ';

    RAISE NOTICE 'Renaming partitions...';
    FOR partition_stories_id IN 1..max_stories_id BY chunk_size LOOP

        SELECT bitly_get_partition_name( partition_stories_id, temp_table_name ) INTO target_temp_table_name;
        SELECT bitly_get_partition_name( partition_stories_id, final_table_name ) INTO target_final_table_name;

        RAISE NOTICE 'Renaming partition "%" to "%"...', target_temp_table_name, target_final_table_name;
        EXECUTE '
            ALTER TABLE ' || target_temp_table_name || '
            RENAME CONSTRAINT ' || target_temp_table_name || '_stories_id
            TO ' || target_final_table_name || '_stories_id;
        ';
        EXECUTE '
            ALTER TABLE ' || target_temp_table_name || '
            RENAME CONSTRAINT ' || target_temp_table_name || '_stories_id_fkey
            TO ' || target_final_table_name || '_stories_id_fkey;
        ';
        EXECUTE '
            ALTER INDEX ' || target_temp_table_name || '_pkey
            RENAME TO ' || target_final_table_name || '_pkey;
        ';
        EXECUTE '
            ALTER INDEX ' || target_temp_table_name || '_stories_id_unique
            RENAME TO ' || target_final_table_name || '_stories_id_unique;
        ';
        EXECUTE 'ALTER TABLE ' || target_temp_table_name || ' RENAME TO ' || target_final_table_name || ';';

    END LOOP;

END$$;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4571;

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

