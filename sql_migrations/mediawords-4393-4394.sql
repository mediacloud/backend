--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4393 and 4394.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4393, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4394, import this SQL file:
--
--     psql mediacloud < mediawords-4393-4394.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

CREATE TABLE feedless_stories (
	stories_id integer,
	media_id integer
);

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4394;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION cancel_pg_process(cancel_pid integer) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
return pg_cancel_backend(cancel_pid);
END;
$$;

CREATE INDEX feedless_stories_story ON feedless_stories USING btree (stories_id);

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

