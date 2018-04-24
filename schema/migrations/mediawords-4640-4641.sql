--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4640 and 4641.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4640, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4641, import this SQL file:
--
--     psql mediacloud < mediawords-4640-4641.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


CREATE OR REPLACE FUNCTION table_exists(target_table_name VARCHAR) RETURNS BOOLEAN AS $$
DECLARE
    schema_position INT;
    schema VARCHAR;
BEGIN

    SELECT POSITION('.' IN target_table_name) INTO schema_position;

    -- "." at string index 0 would return position 1
    IF schema_position = 0 THEN
        schema := CURRENT_SCHEMA();
    ELSE
        schema := SUBSTRING(target_table_name FROM 1 FOR schema_position - 1);
        target_table_name := SUBSTRING(target_table_name FROM schema_position + 1);
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = schema
          AND table_name = target_table_name
    );

END;
$$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4641;

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
