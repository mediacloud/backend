--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4626 and 4627.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4626, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4627, import this SQL file:
--
--     psql mediacloud < mediawords-4626-4627.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DROP FUNCTION upsert_bitly_clicks_total(param_stories_id INT, param_click_count INT);

CREATE OR REPLACE FUNCTION bitly_clicks_total_partition_by_stories_id_insert_trigger() RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_total_000001")
BEGIN
    SELECT bitly_get_partition_name( NEW.stories_id, 'bitly_clicks_total' ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ON CONFLICT (stories_id) DO UPDATE
            SET click_count = EXCLUDED.click_count
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4627;

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

