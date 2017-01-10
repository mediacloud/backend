--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4435 and 4436.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4435, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4436, import this SQL file:
--
--     psql mediacloud < mediawords-4435-4436.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4436;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE INDEX media_name_trgm ON media USING gin (name gin_trgm_ops);

CREATE INDEX media_url_trgm ON media USING gin (url gin_trgm_ops);

CREATE INDEX dashboards_name_trgm ON dashboards USING gin (name gin_trgm_ops);

CREATE INDEX media_sets_name_trgm ON media_sets USING gin (name gin_trgm_ops);

CREATE INDEX media_sets_description_trgm ON media_sets USING gin (description gin_trgm_ops);

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

