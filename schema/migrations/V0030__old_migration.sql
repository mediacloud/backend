


CREATE UNIQUE INDEX stories_tags_map_pkey ON stories_tags_map (stories_tags_map_id);
ALTER TABLE stories_tags_map ADD PRIMARY KEY USING INDEX stories_tags_map_pkey;


-- Create missing stories_tags_map partitions
CREATE OR REPLACE FUNCTION stories_tags_map_create_partitions()
RETURNS VOID AS
$$
DECLARE
    chunk_size INT;
    max_stories_id BIGINT;
    partition_stories_id BIGINT;

    target_table_name TEXT;       -- partition table name (e.g. "stories_tags_map_01")
    target_table_owner TEXT;      -- partition table owner (e.g. "mediaclouduser")

    stories_id_start INT;         -- stories_id chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_end INT;           -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
BEGIN

    SELECT stories_tags_map_partition_chunk_size() INTO chunk_size;

    -- Create +1 partition for future insertions
    SELECT COALESCE(MAX(stories_id), 0) + chunk_size FROM stories INTO max_stories_id;

    FOR partition_stories_id IN 1..max_stories_id BY chunk_size LOOP
        SELECT stories_tags_map_get_partition_name( partition_stories_id, 'stories_tags_map' ) INTO target_table_name;
        IF table_exists(target_table_name) THEN
            RAISE NOTICE 'Partition "%" for story ID % already exists.', target_table_name, partition_stories_id;
        ELSE
            RAISE NOTICE 'Creating partition "%" for story ID %', target_table_name, partition_stories_id;

            SELECT (partition_stories_id / chunk_size) * chunk_size INTO stories_id_start;
            SELECT ((partition_stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

            EXECUTE '
                CREATE TABLE ' || target_table_name || ' (

                    PRIMARY KEY (stories_tags_map_id),

                    -- Partition by stories_id
                    CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id CHECK (
                        stories_id >= ''' || stories_id_start || '''
                    AND stories_id <  ''' || stories_id_end   || '''),

                    -- Foreign key to stories.stories_id
                    CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id_fkey
                        FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL ON DELETE CASCADE,

                    -- Foreign key to tags.tags_id
                    CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_tags_id_fkey
                        FOREIGN KEY (tags_id) REFERENCES tags (tags_id) MATCH FULL ON DELETE CASCADE,

                    -- Unique duplets
                    CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id_tags_id_unique
                        UNIQUE (stories_id, tags_id)

                ) INHERITS (stories_tags_map);
            ';

            -- Update owner
            SELECT u.usename AS owner
            FROM information_schema.tables AS t
                JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
                JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
            WHERE t.table_name = 'stories_tags_map'
              AND t.table_schema = 'public'
            INTO target_table_owner;

            EXECUTE 'ALTER TABLE ' || target_table_name || ' OWNER TO ' || target_table_owner || ';';

        END IF;
    END LOOP;

END;
$$
LANGUAGE plpgsql;



