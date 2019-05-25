--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4466 and 4467.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4466, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4467, import this SQL file:
--
--     psql mediacloud < mediawords-4466-4467.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

drop view controversies_with_dates;
create view controversies_with_dates as
    select c.*, 
            to_char( cd.start_date, 'YYYY-MM-DD' ) start_date, 
            to_char( cd.end_date, 'YYYY-MM-DD' ) end_date
        from 
            controversies c 
            join controversy_dates cd on ( c.controversies_id = cd.controversies_id )
        where 
            cd.boundary;

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4467;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


