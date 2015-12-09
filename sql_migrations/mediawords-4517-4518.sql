--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4517 and 4518.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4517, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4518, import this SQL file:
--
--     psql mediacloud < mediawords-4517-4518.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DROP FUNCTION upsert_story_bitly_statistics(param_stories_id INT, param_bitly_click_count INT, param_bitly_referrer_count INT);
CREATE OR REPLACE FUNCTION upsert_story_bitly_statistics(param_stories_id INT, param_bitly_click_count INT) RETURNS VOID AS
$$
BEGIN
    LOOP
        -- Try UPDATing
        UPDATE story_bitly_statistics
            SET bitly_click_count = param_bitly_click_count
            WHERE stories_id = param_stories_id;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO story_bitly_statistics (stories_id, bitly_click_count)
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

ALTER TABLE story_bitly_statistics
	DROP COLUMN bitly_referrer_count;

ALTER TABLE cd.story_link_counts
    DROP COLUMN bitly_referrer_count;

ALTER TABLE cd.medium_link_counts
    DROP COLUMN bitly_referrer_count;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4518;

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

