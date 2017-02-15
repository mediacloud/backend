--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4391 and 4392.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4391, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4392, import this SQL file:
--
--     psql mediacloud < mediawords-4391-4392.sql
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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4392;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION media_set_retains_sw_data_for_date(v_media_sets_id int, test_date date, default_start_day date, default_end_day date) RETURNS BOOLEAN AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
    start_date   date;
    end_date     date;
BEGIN
    current_time := timeofday()::timestamp;

    -- RAISE NOTICE 'time - %', current_time;

   media_rec = media_set_sw_data_retention_dates( v_media_sets_id, default_start_day,  default_end_day ); -- INTO (media_rec);

   start_date = media_rec.start_date; 
   end_date = media_rec.end_date;

    -- RAISE NOTICE 'start date - %', start_date;
    -- RAISE NOTICE 'end date - %', end_date;

    return  ( ( start_date is null )  OR ( start_date <= test_date ) ) AND ( (end_date is null ) OR ( end_date >= test_date ) );
END;
$$
LANGUAGE 'plpgsql' STABLE
 ;

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

