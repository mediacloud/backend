--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4699 and 4700.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4699, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4700, import this SQL file:
--
--     psql mediacloud < mediawords-4699-4700.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DO $$
DECLARE
    tables CURSOR FOR
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename LIKE 'stories_tags_map_%'
        ORDER BY tablename;
    new_table_name TEXT;
BEGIN
    FOR table_record IN tables LOOP
        SELECT REPLACE(table_record.tablename, 'stories_tags_map_', 'stories_tags_map_p_') INTO new_table_name;
        EXECUTE '
            ALTER TABLE ' || table_record.tablename || '
                RENAME TO ' || new_table_name || ';';
        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_pkey
                RENAME TO ' || new_table_name || '_pkey;';
        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_stories_id_tags_id_unique
                RENAME TO ' || new_table_name || '_stories_id_tags_id_unique;';
        EXECUTE '
            ALTER TABLE ' || new_table_name || '
                RENAME CONSTRAINT ' || table_record.tablename || '_stories_id
                TO ' || new_table_name || '_stories_id';
        EXECUTE '
            ALTER TABLE ' || new_table_name || '
                RENAME CONSTRAINT ' || table_record.tablename || '_stories_id_fkey
                TO ' || new_table_name || '_stories_id_fkey';
        EXECUTE '
            ALTER TABLE ' || new_table_name || '
                RENAME CONSTRAINT ' || table_record.tablename || '_tags_id_fkey
                TO ' || new_table_name || '_tags_id_fkey';

    END LOOP;
END
$$;


ALTER TABLE stories_tags_map
    RENAME TO stories_tags_map_p;

ALTER SEQUENCE stories_tags_map_stories_tags_map_id_seq
    RENAME TO stories_tags_map_p_stories_tags_map_p_id_seq;

ALTER INDEX stories_tags_map_pkey
    RENAME TO stories_tags_map_p_pkey;

ALTER TABLE stories_tags_map_p
    RENAME COLUMN stories_tags_map_id TO stories_tags_map_p_id;


CREATE OR REPLACE FUNCTION stories_tags_map_create_partitions() RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_stories_id_create_partitions('stories_tags_map_p'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;
        
        -- Add extra foreign keys / constraints to the newly created partitions
        EXECUTE '
            ALTER TABLE ' || partition || '

                -- Foreign key to tags.tags_id
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_tags_id_fkey
                    FOREIGN KEY (tags_id) REFERENCES tags (tags_id) MATCH FULL ON DELETE CASCADE,

                -- Unique duplets
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_stories_id_tags_id_unique
                    UNIQUE (stories_id, tags_id);
        ';

    END LOOP;

END;
$$
LANGUAGE plpgsql;


-- Rename trigger
DROP TRIGGER stm_insert_solr_import_story ON stories_tags_map_p;

CREATE TRIGGER stories_tags_map_p_insert_solr_import_story
    BEFORE INSERT OR UPDATE OR DELETE ON stories_tags_map_p
    FOR EACH ROW
    EXECUTE PROCEDURE insert_solr_import_story();



DROP TRIGGER stories_tags_map_partition_upsert_trigger ON stories_tags_map_p;

DROP FUNCTION stories_tags_map_partition_upsert_trigger();

CREATE OR REPLACE FUNCTION stories_tags_map_p_upsert_trigger() RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "stories_tags_map_01")
BEGIN
    SELECT partition_by_stories_id_partition_name(
        base_table_name := 'stories_tags_map_p',
        stories_id := NEW.stories_id
    ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ON CONFLICT (stories_id, tags_id) DO NOTHING
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER stories_tags_map_p_upsert_trigger
    BEFORE INSERT ON stories_tags_map_p
    FOR EACH ROW
    EXECUTE PROCEDURE stories_tags_map_p_upsert_trigger();


CREATE OR REPLACE VIEW stories_tags_map AS

    SELECT
        stories_tags_map_p_id AS stories_tags_map_id,
        stories_id,
        tags_id
    FROM stories_tags_map_p;


-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW stories_tags_map
    ALTER COLUMN stories_tags_map_id
    SET DEFAULT nextval(pg_get_serial_sequence('stories_tags_map_p', 'stories_tags_map_p_id'));

-- Prevent the next INSERT from failing
SELECT nextval(pg_get_serial_sequence('stories_tags_map_p', 'stories_tags_map_p_id'));


-- Trigger that implements INSERT / UPDATE / DELETE behavior on "stories_tags_map" view
CREATE OR REPLACE FUNCTION stories_tags_map_view_insert_update_delete() RETURNS trigger AS $$
BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- By INSERTing into the master table, we're letting triggers choose
        -- the correct partition.
        INSERT INTO stories_tags_map_p SELECT NEW.*;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE stories_tags_map_p
            SET stories_id = NEW.stories_id,
                tags_id = NEW.tags_id
            WHERE stories_id = OLD.stories_id
              AND tags_id = OLD.tags_id;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        DELETE FROM stories_tags_map_p
            WHERE stories_id = OLD.stories_id
              AND tags_id = OLD.tags_id;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER stories_tags_map_view_insert_update_delete
    INSTEAD OF INSERT OR UPDATE OR DELETE ON stories_tags_map
    FOR EACH ROW EXECUTE PROCEDURE stories_tags_map_view_insert_update_delete();


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4700;
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
