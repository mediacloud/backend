


--
-- Rename unpartitioned table
--
ALTER TABLE feeds_stories_map
    RENAME TO feeds_stories_map_unpartitioned;


--
-- Create partitions
--

-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE feeds_stories_map_partitioned (

    -- PRIMARY KEY on master table needed for database handler's primary_key_column() method to work
    feeds_stories_map_partitioned_id    BIGSERIAL   PRIMARY KEY NOT NULL,

    feeds_id                            INT         NOT NULL,
    stories_id                          INT         NOT NULL
);

-- Note: "INSERT ... RETURNING *" doesn't work with the trigger, please use
-- "feeds_stories_map" view instead
CREATE OR REPLACE FUNCTION feeds_stories_map_partitioned_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "feeds_stories_map_01")
BEGIN
    SELECT partition_by_stories_id_partition_name('feeds_stories_map_partitioned', NEW.stories_id ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER feeds_stories_map_partitioned_insert_trigger
    BEFORE INSERT ON feeds_stories_map_partitioned
    FOR EACH ROW EXECUTE PROCEDURE feeds_stories_map_partitioned_insert_trigger();


-- Create missing "feeds_stories_map_partitioned" partitions
CREATE OR REPLACE FUNCTION feeds_stories_map_create_partitions()
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_stories_id_create_partitions('feeds_stories_map_partitioned'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;
        
        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_feeds_id_fkey
                FOREIGN KEY (feeds_id) REFERENCES feeds (feeds_id) MATCH FULL ON DELETE CASCADE;

            CREATE UNIQUE INDEX ' || partition || '_feeds_id_stories_id
                ON ' || partition || ' (feeds_id, stories_id);

            CREATE INDEX ' || partition || '_stories_id
                ON ' || partition || ' (stories_id);
        ';

    END LOOP;

END;
$$
LANGUAGE plpgsql;

-- Create initial "feeds_stories_map_partitioned" partitions for empty database
SELECT feeds_stories_map_create_partitions();


-- Proxy view to "feeds_stories_map_partitioned" to make RETURNING work
CREATE OR REPLACE VIEW feeds_stories_map AS

    SELECT
        feeds_stories_map_partitioned_id AS feeds_stories_map_id,
        feeds_id,
        stories_id
    FROM feeds_stories_map_partitioned;


-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW feeds_stories_map
    ALTER COLUMN feeds_stories_map_id
    SET DEFAULT nextval(pg_get_serial_sequence('feeds_stories_map_partitioned', 'feeds_stories_map_partitioned_id')) + 1;


-- Trigger that implements INSERT / UPDATE / DELETE behavior on "feeds_stories_map" view
CREATE OR REPLACE FUNCTION feeds_stories_map_view_insert_update_delete() RETURNS trigger AS $$

BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- By INSERTing into the master table, we're letting triggers choose
        -- the correct partition.
        INSERT INTO feeds_stories_map_partitioned SELECT NEW.*;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE feeds_stories_map_partitioned
            SET feeds_id = NEW.feeds_id,
                stories_id = NEW.stories_id
            WHERE feeds_id = OLD.feeds_id
              AND stories_id = OLD.stories_id;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        DELETE FROM feeds_stories_map_partitioned
            WHERE feeds_id = OLD.feeds_id
              AND stories_id = OLD.stories_id;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER feeds_stories_map_view_insert_update_delete_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE ON feeds_stories_map
    FOR EACH ROW EXECUTE PROCEDURE feeds_stories_map_view_insert_update_delete();


CREATE OR REPLACE FUNCTION create_missing_partitions() RETURNS VOID AS
$$
BEGIN

    RAISE NOTICE 'Creating partitions in "stories_tags_map" table...';
    PERFORM stories_tags_map_create_partitions();

    RAISE NOTICE 'Creating partitions in "story_sentences_partitioned" table...';
    PERFORM story_sentences_create_partitions();

    RAISE NOTICE 'Creating partitions in "feeds_stories_map_partitioned" table...';
    PERFORM feeds_stories_map_create_partitions();

END;
$$
LANGUAGE plpgsql;


--
-- Copy rows from unpartitioned table to the partitioned one
--
INSERT INTO feeds_stories_map (feeds_id, stories_id)
    SELECT feeds_id, stories_id
    FROM feeds_stories_map_unpartitioned;


--
-- Drop unpartitioned table
--
DROP TABLE feeds_stories_map_unpartitioned;




