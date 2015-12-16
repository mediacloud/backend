--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4518 and 4519.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4518, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4519, import this SQL file:
--
--     psql mediacloud < mediawords-4518-4519.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


ALTER TABLE bitly_processing_results
    ADD COLUMN collect_date TIMESTAMP NULL DEFAULT NOW();

-- Set to NULL for all the current data because we don't know the exact collection date
UPDATE bitly_processing_results
    SET collect_date = NULL;


-- Rename table and function to be clear that we're dealing with controversies here
DROP FUNCTION upsert_story_bitly_statistics(INT, INT);

ALTER TABLE story_bitly_statistics
    RENAME TO controversy_stories_bitly_statistics;
ALTER TABLE controversy_stories_bitly_statistics
    RENAME COLUMN story_bitly_statistics_id TO controversy_stories_bitly_statistics_id;
ALTER INDEX story_bitly_statistics_stories_id
    RENAME TO controversy_stories_bitly_statistics_stories_id;

-- Helper to INSERT / UPDATE story's Bit.ly statistics
CREATE FUNCTION upsert_controversy_stories_bitly_statistics (
    param_stories_id INT,
    param_bitly_click_count INT
) RETURNS VOID AS
$$
BEGIN
    LOOP
        -- Try UPDATing
        UPDATE controversy_stories_bitly_statistics
            SET bitly_click_count = param_bitly_click_count
            WHERE stories_id = param_stories_id;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO controversy_stories_bitly_statistics (stories_id, bitly_click_count)
            VALUES (param_stories_id, param_bitly_click_count);
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


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4519;

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

