--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4659 and 4660.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4659, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4660, import this SQL file:
--
--     psql mediacloud < mediawords-4659-4660.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DROP TRIGGER stories_tags_map_partition_by_stories_id_insert_trigger ON stories_tags_map;

DROP FUNCTION stories_tags_map_partition_by_stories_id_insert_trigger();


CREATE OR REPLACE FUNCTION stories_tags_map_partition_upsert_trigger() RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "stories_tags_map_01")
BEGIN
    SELECT stories_partition_name( 'stories_tags_map', NEW.stories_id ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ON CONFLICT (stories_id, tags_id) DO NOTHING
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER stories_tags_map_partition_upsert_trigger
	BEFORE INSERT ON stories_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE stories_tags_map_partition_upsert_trigger();


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4660;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();

