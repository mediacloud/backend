--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4574 and 4575.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4574, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4575, import this SQL file:
--
--     psql mediacloud < mediawords-4574-4575.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Recreate the trigger in case it doesn't exist
CREATE OR REPLACE FUNCTION bitly_clicks_total_partition_by_stories_id_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;
BEGIN
    SELECT bitly_get_partition_name( NEW.stories_id, 'bitly_clicks_total' ) INTO target_table_name;
    EXECUTE 'INSERT INTO ' || target_table_name || ' SELECT $1.*;' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS bitly_clicks_total_partition_by_stories_id_insert_trigger ON bitly_clicks_total;
CREATE TRIGGER bitly_clicks_total_partition_by_stories_id_insert_trigger
    BEFORE INSERT ON bitly_clicks_total
    FOR EACH ROW EXECUTE PROCEDURE bitly_clicks_total_partition_by_stories_id_insert_trigger();


-- Move data that errorneously got into the master table to partitions
CREATE TEMPORARY TABLE temp_bitly_clicks_total_master_table (
    stories_id BIGINT NOT NULL,
    click_count INT NOT NULL
);
INSERT INTO temp_bitly_clicks_total_master_table (stories_id, click_count)
    SELECT stories_id, click_count
    FROM ONLY bitly_clicks_total;   -- ONLY the master table, not partitions
TRUNCATE ONLY bitly_clicks_total;   -- ONLY the master table, not partitions
-- VACUUM FULL ANALYZE bitly_clicks_total; -- Free up used space

-- In case some click counts are to be UPDATEd
DELETE FROM bitly_clicks_total WHERE stories_id IN (
    SELECT stories_id
    FROM temp_bitly_clicks_total_master_table
);

INSERT INTO bitly_clicks_total (stories_id, click_count)
    SELECT DISTINCT stories_id, click_count
    FROM temp_bitly_clicks_total_master_table;

DROP TABLE temp_bitly_clicks_total_master_table;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4575;

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

