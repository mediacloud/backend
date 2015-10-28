--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4500 and 4501.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4500, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4501, import this SQL file:
--
--     psql mediacloud < mediawords-4500-4501.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

DROP VIEW story_similarities_transitive;

DROP TABLE queries_media_sets_map;

DROP TABLE top_ten_tags_for_media;

DROP TABLE daily_country_counts;

DROP TABLE queries_dashboard_topics_map;

DROP TABLE story_similarities;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4501;
    
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

