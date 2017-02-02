--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4433 and 4434.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4433, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4434, import this SQL file:
--
--     psql mediacloud < mediawords-4433-4434.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

CREATE TABLE raw_downloads (
	raw_downloads_id   SERIAL  PRIMARY KEY,
	downloads_id       INTEGER NOT NULL REFERENCES downloads ON DELETE CASCADE,
	raw_data           BYTEA   NOT NULL         
);
CREATE UNIQUE INDEX raw_downloads_downloads_id ON raw_downloads (downloads_id);


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4434;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();

