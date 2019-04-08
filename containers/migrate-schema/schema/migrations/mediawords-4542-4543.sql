--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4542 and 4543.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4542, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4543, import this SQL file:
--
--     psql mediacloud < mediawords-4542-4543.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


--
-- Stories without Readability tag
--
CREATE TABLE IF NOT EXISTS stories_without_readability_tag (
    stories_id BIGINT NOT NULL REFERENCES stories (stories_id)
);
CREATE INDEX stories_without_readability_tag_stories_id
    ON stories_without_readability_tag (stories_id);

-- Fill in the table manually with:
--
-- INSERT INTO scratch.stories_without_readability_tag (stories_id)
--     SELECT stories.stories_id
--     FROM stories
--         LEFT JOIN stories_tags_map
--             ON stories.stories_id = stories_tags_map.stories_id

--             -- "extractor_version:readability-lxml-0.3.0.5"
--             AND stories_tags_map.tags_id = 8929188

--     -- No Readability tag
--     WHERE stories_tags_map.tags_id IS NULL
--     ;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4543;

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

