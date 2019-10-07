--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4644 and 4645.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4644, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4645, import this SQL file:
--
--     psql mediacloud < mediawords-4644-4645.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--
create index media_normalized_urls_db_row_last_updated on media_normalized_urls(db_row_last_updated);

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4645;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
