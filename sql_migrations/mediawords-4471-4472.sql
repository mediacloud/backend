--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4471 and 4472.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4471, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4472, import this SQL file:
--
--     psql mediacloud < mediawords-4471-4472.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


ALTER TABLE controversies
    ADD COLUMN process_with_bitly BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN controversies.process_with_bitly
    IS 'Enable processing controversy''s stories with Bit.ly; enqueue all new controversy stories for Bit.ly processing';

-- Recreate view because otherwise it doesn't return the "process_with_bitly" column
DROP VIEW controversies_with_dates;
CREATE VIEW controversies_with_dates AS
    SELECT c.*, 
        to_char( cd.start_date, 'YYYY-MM-DD' ) start_date, 
        to_char( cd.end_date, 'YYYY-MM-DD' ) end_date
    FROM 
        controversies c 
        JOIN controversy_dates cd ON ( c.controversies_id = cd.controversies_id )
    WHERE cd.boundary;


-- Bit.ly stats
-- (values can be NULL if Bit.ly is not enabled / configured for a controversy)
ALTER TABLE cd.story_link_counts
    ADD COLUMN bitly_click_count    INT NULL,
    ADD COLUMN bitly_referrer_count INT NULL;

-- Bit.ly (aggregated) stats
-- (values can be NULL if Bit.ly is not enabled / configured for a controversy)
ALTER TABLE cd.medium_link_counts
    ADD COLUMN bitly_click_count    INT NULL,
    ADD COLUMN bitly_referrer_count INT NULL;


-- Bit.ly stats for stories
CREATE TABLE cd.story_bitly_statistics (
    story_bitly_statistics_id   SERIAL  PRIMARY KEY,
    stories_id                  INT     NOT NULL UNIQUE REFERENCES public.stories ON DELETE CASCADE,

    -- Bit.ly stats
    bitly_click_count           INT     NOT NULL,
    bitly_referrer_count        INT     NOT NULL
);
CREATE UNIQUE INDEX story_bitly_statistics_stories_id
    ON cd.story_bitly_statistics ( stories_id );

-- Helper to INSERT / UPDATE story's Bit.ly statistics
CREATE FUNCTION cd.upsert_story_bitly_statistics (
    param_stories_id INT,
    param_bitly_click_count INT,
    param_bitly_referrer_count INT
) RETURNS VOID AS
$$
BEGIN
    LOOP
        -- Try UPDATing
        UPDATE cd.story_bitly_statistics
            SET bitly_click_count = param_bitly_click_count,
                bitly_referrer_count = param_bitly_referrer_count
            WHERE stories_id = param_stories_id;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO cd.story_bitly_statistics (stories_id, bitly_click_count, bitly_referrer_count)
            VALUES (param_stories_id, param_bitly_click_count, param_bitly_referrer_count);
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

-- Helper to test if all controversy's stories have aggregated Bit.ly stats already
CREATE FUNCTION cd.all_controversy_stories_have_bitly_statistics (param_controversies_id INT) RETURNS BOOL AS
$$
DECLARE
    controversy_exists BOOL;
    stories_without_bitly_statistics INT;
BEGIN

    SELECT 1 INTO controversy_exists
    FROM controversies
    WHERE controversies_id = param_controversies_id
      AND process_with_bitly = 't';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Controversy % does not exist or is not set up for Bit.ly processing.', param_controversies_id;
        RETURN FALSE;
    END IF;

    SELECT COUNT(stories_id) INTO stories_without_bitly_statistics
    FROM controversy_stories
    WHERE controversies_id = param_controversies_id
      AND stories_id NOT IN (
        SELECT stories_id
        FROM cd.story_bitly_statistics
    )
    GROUP BY controversies_id;
    IF FOUND THEN
        RAISE NOTICE 'Some stories (% of them) still don''t have aggregated Bit.ly statistics for controversy %.', stories_without_bitly_statistics, param_controversies_id;
        RETURN FALSE;
    END IF;

    RETURN TRUE;

END;
$$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4472;
    
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
