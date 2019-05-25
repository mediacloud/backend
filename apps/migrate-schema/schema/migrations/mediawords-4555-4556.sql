--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4555 and 4556.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4555, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4556, import this SQL file:
--
--     psql mediacloud < mediawords-4555-4556.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Create index if it doesn't exist already
--
-- Should be removed after migrating to PostgreSQL 9.5 because it supports
-- CREATE INDEX IF NOT EXISTS natively.
CREATE OR REPLACE FUNCTION create_index_if_not_exists(schema_name TEXT, table_name TEXT, index_name TEXT, index_sql TEXT)
RETURNS void AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM   pg_class c
        JOIN   pg_namespace n ON n.oid = c.relnamespace
        WHERE  c.relname = index_name
        AND    n.nspname = schema_name
    ) THEN
        EXECUTE 'CREATE INDEX ' || index_name || ' ON ' || schema_name || '.' || table_name || ' ' || index_sql;
    END IF;
END
$$
LANGUAGE plpgsql VOLATILE;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4556;

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

