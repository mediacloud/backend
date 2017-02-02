--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4598 and 4599.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4598, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4599, import this SQL file:
--
--     psql mediacloud < mediawords-4598-4599.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


ALTER TABLE stories_superglue_metadata
    ADD COLUMN video_url VARCHAR NOT NULL DEFAULT '';

-- Copy story (video) URLs to metadata table
UPDATE stories_superglue_metadata
SET video_url = superglue_stories.url
FROM (
    SELECT stories_id,
           url
    FROM stories
    WHERE stories_id IN (
        SELECT stories_id
        FROM feeds_stories_map
        WHERE feeds_id IN (
            SELECT feeds_id
            FROM feeds
            WHERE feed_type = 'superglue'
        )
    )
) AS superglue_stories
WHERE stories_superglue_metadata.stories_id = superglue_stories.stories_id;

-- Remove URLs (set to GUID) from "stories" table
UPDATE stories
SET url = guid
WHERE stories_id IN (
    SELECT stories_id
    FROM feeds_stories_map
    WHERE feeds_id IN (
        SELECT feeds_id
        FROM feeds
        WHERE feed_type = 'superglue'
    )
);

ALTER TABLE stories_superglue_metadata
    ALTER COLUMN video_url DROP DEFAULT;



CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4599;

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

