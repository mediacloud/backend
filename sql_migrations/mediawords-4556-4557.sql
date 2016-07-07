--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4556 and 4557.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4556, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4557, import this SQL file:
--
--     psql mediacloud < mediawords-4556-4557.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Returns first 64 bits (16 characters) of MD5 hash
--
-- Useful for reducing index sizes (e.g. in story_sentences.sentence) where
-- 64 bits of entropy is enough.
CREATE OR REPLACE FUNCTION half_md5(string TEXT) RETURNS bytea AS $$
    SELECT SUBSTRING(digest(string, 'md5'::text), 0, 9);
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4557;

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

