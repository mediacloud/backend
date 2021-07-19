--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4758 and 4759.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4758, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4759, import this SQL file:
--
--     psql mediacloud < mediawords-4758-4759.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

CREATE OR REPLACE FUNCTION partition_by_stories_id_create_partitions(base_table_name TEXT)
RETURNS SETOF TEXT AS
$$
DECLARE
    chunk_size INT;
    max_stories_id INT;
    partition_stories_id INT;

    -- Partition table name (e.g. "stories_tags_map_01")
    target_table_name TEXT;

    -- Partition table owner (e.g. "mediaclouduser")
    target_table_owner TEXT;

    -- "stories_id" chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_start BIGINT;

    -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
    stories_id_end BIGINT;
BEGIN

    SELECT partition_by_stories_id_chunk_size() INTO chunk_size;

    -- Create +1 partition for future insertions
    SELECT COALESCE(MAX(stories_id), 0) + chunk_size FROM stories INTO max_stories_id;

    SELECT 1 INTO partition_stories_id;
    WHILE partition_stories_id <= max_stories_id LOOP
        SELECT partition_by_stories_id_partition_name(
            base_table_name := base_table_name,
            stories_id := partition_stories_id
        ) INTO target_table_name;
        IF table_exists(target_table_name) THEN
            RAISE NOTICE 'Partition "%" for story ID % already exists.', target_table_name, partition_stories_id;
        ELSE
            RAISE NOTICE 'Creating partition "%" for story ID %', target_table_name, partition_stories_id;

            SELECT (partition_stories_id / chunk_size) * chunk_size INTO stories_id_start;
            SELECT ((partition_stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

            -- Kill all autovacuums before proceeding with DDL changes
            PERFORM pid
            FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
            WHERE backend_type = 'autovacuum worker'
              AND query ~ 'stories';

            EXECUTE '
                CREATE TABLE ' || target_table_name || ' (

                    PRIMARY KEY (' || base_table_name || '_id),

                    -- Partition by stories_id
                    CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id CHECK (
                        stories_id >= ''' || stories_id_start || '''
                    AND stories_id <  ''' || stories_id_end   || '''),

                    -- Foreign key to stories.stories_id
                    CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id_fkey
                        FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL ON DELETE CASCADE

                ) INHERITS (' || base_table_name || ');
            ';

            -- Update owner
            SELECT u.usename AS owner
            FROM information_schema.tables AS t
                JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
                JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
            WHERE t.table_name = base_table_name
              AND t.table_schema = 'public'
            INTO target_table_owner;

            EXECUTE 'ALTER TABLE ' || target_table_name || ' OWNER TO ' || target_table_owner || ';';

            -- Add created partition name to the list of returned partition names
            RETURN NEXT target_table_name;

        END IF;

        SELECT partition_stories_id + chunk_size INTO partition_stories_id;
    END LOOP;

    RETURN;

END;
$$
LANGUAGE plpgsql;


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

    SELECT 1 INTO partition_downloads_id;
    WHILE partition_downloads_id <= max_downloads_id LOOP
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

            -- Kill all autovacuums before proceeding with DDL changes
            PERFORM pid
            FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
            WHERE backend_type = 'autovacuum worker'
              AND query ~ 'downloads';

            EXECUTE '
                CREATE TABLE ' || target_table_name || '
                    PARTITION OF ' || base_table_name || '
                    FOR VALUES FROM (' || downloads_id_start || ')
                               TO   (' || downloads_id_end   || ');
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

        SELECT partition_downloads_id + chunk_size INTO partition_downloads_id;
    END LOOP;

    RETURN;

END;
$$
LANGUAGE plpgsql;

>>>>>>> origin/master

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4759;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
