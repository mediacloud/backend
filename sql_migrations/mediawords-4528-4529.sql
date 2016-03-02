--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4528 and 4529.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4528, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4529, import this SQL file:
--
--     psql mediacloud < mediawords-4528-4529.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


ALTER TABLE solr_import_stories
    RENAME TO solr_import_extra_stories;

ALTER INDEX solr_import_stories_story
    RENAME TO solr_import_extra_stories_story;

INSERT INTO solr_import_extra_stories (stories_id)
    SELECT DISTINCT bitly_clicks_total.stories_id
    FROM bitly_clicks_total
    WHERE NOT EXISTS (
        SELECT 1
        FROM solr_import_extra_stories
        WHERE solr_import_extra_stories.stories_id = bitly_clicks_total.stories_id
    );


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4529;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();

