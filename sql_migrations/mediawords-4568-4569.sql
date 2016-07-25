--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4568 and 4569.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4568, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4569, import this SQL file:
--
--     psql mediacloud < mediawords-4568-4569.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


CREATE OR REPLACE FUNCTION table_exists(target_table_name VARCHAR) RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = CURRENT_SCHEMA()
          AND table_name = target_table_name
    );
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bitly_clicks_total_partition_by_stories_id_insert_trigger() RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_total_000001")
BEGIN
    SELECT bitly_get_partition_name( NEW.stories_id, 'bitly_clicks_total' ) INTO target_table_name;
    EXECUTE 'INSERT INTO ' || target_table_name || ' SELECT $1.*;' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bitly_clicks_total_create_partitions() RETURNS VOID AS
$$
DECLARE
    chunk_size INT;
    max_stories_id BIGINT;
    partition_stories_id BIGINT;

    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_total_000001")
    target_table_owner TEXT;      -- partition table owner (e.g. "mediaclouduser")

    stories_id_start INT;         -- stories_id chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_end INT;           -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
BEGIN

    SELECT bitly_partition_chunk_size() INTO chunk_size;

    -- Create +1 partition for future insertions
    SELECT COALESCE(MAX(stories_id), 0) + chunk_size FROM stories INTO max_stories_id;

    FOR partition_stories_id IN 1..max_stories_id BY chunk_size LOOP
        SELECT bitly_get_partition_name( partition_stories_id, 'bitly_clicks_total' ) INTO target_table_name;
        IF table_exists(target_table_name) THEN
            RAISE NOTICE 'Partition "%" for story ID % already exists.', target_table_name, partition_stories_id;
        ELSE
            RAISE NOTICE 'Creating partition "%" for story ID %', target_table_name, partition_stories_id;

            SELECT (partition_stories_id / chunk_size) * chunk_size INTO stories_id_start;
            SELECT ((partition_stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

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
    END LOOP;

END;
$$
LANGUAGE plpgsql;

-- Create initial partitions for empty database
SELECT bitly_clicks_total_create_partitions();


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4569;

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

