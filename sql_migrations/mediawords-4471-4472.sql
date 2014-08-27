--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4471 and 4472.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4471, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4472, import this SQL file:
--
--     psql mediacloud < mediawords-4471-4472.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


ALTER TABLE controversies
    ADD COLUMN process_with_bitly BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN controversies.process_with_bitly
    IS 'Enable processing controversy''s stories with Bit.ly; enqueue all new controversy stories for Bit.ly processing';

-- Recreate view because otherwise it doesn't return the "process_with_bitly" column
DROP VIEW controversies_with_dates;
CREATE VIEW controversies_with_dates AS
    SELECT c.*, 
        to_char( cd.start_date, 'YYYY-MM-DD' ) start_date, 
        to_char( cd.end_date, 'YYYY-MM-DD' ) end_date
    FROM 
        controversies c 
        JOIN controversy_dates cd ON ( c.controversies_id = cd.controversies_id )
    WHERE cd.boundary;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4472;
    
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
