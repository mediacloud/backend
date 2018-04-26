--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4452 and 4453.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4452, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4453, import this SQL file:
--
--     psql mediacloud < mediawords-4452-4453.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

ALTER TABLE tags
	ADD COLUMN label varchar(512),
	ADD COLUMN description text;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4453;
    
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

