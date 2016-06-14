--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4546 and 4547.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4546, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4547, import this SQL file:
--
--     psql mediacloud < mediawords-4546-4547.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DROP VIEW media_sets_tt2_locale_format;

DROP VIEW dashboard_topics_tt2_locale_format;

DROP TABLE IF EXISTS controversy_query_story_searches_imported_stories_map;

DROP TABLE IF EXISTS query_story_searches_stories_map;

DROP TABLE IF EXISTS query_story_searches;

DROP TABLE queries_country_counts_json;

DROP TABLE queries;

DROP TABLE dashboard_media_sets;

DROP TABLE story_subsets_processed_stories_map;

DROP TABLE story_subsets;

DROP TABLE media_sets_media_map;

DROP TABLE media_sets;

DROP TABLE dashboard_topics;

DROP TABLE dashboards;


DELETE FROM auth_roles WHERE role = 'query-create';


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4547;

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

