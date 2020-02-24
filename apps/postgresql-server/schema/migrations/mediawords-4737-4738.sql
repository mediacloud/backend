--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4737 and 4738.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4737, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4738, import this SQL file:
--
--     psql mediacloud < mediawords-4737-4738.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4738;

BEGIN

    create unique index database_variables_name on database_variables ( name );

    drop index media_stats_medium;
    create unique index media_stats_medium_date on media_stats( media_id, stat_date );

    drop function if exists insert_story_media_stats cascade;
    drop function if exists update_story_media_stats cascade;
    drop function if exists delete_story_media_stats cascade;


    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


