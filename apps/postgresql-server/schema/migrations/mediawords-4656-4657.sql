--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4656 and 4657.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4656, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4657, import this SQL file:
--
--     psql mediacloud < mediawords-4656-4657.sql
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
    -- pgcrypto's functions are being referred with public schema prefix to make pg_upgrade work
    SELECT SUBSTRING(public.digest(string, 'md5'::text), 0, 9);
$$ LANGUAGE SQL;


-- Generate random API key
CREATE OR REPLACE FUNCTION generate_api_key() RETURNS VARCHAR(64) LANGUAGE plpgsql AS $$
DECLARE
    api_key VARCHAR(64);
BEGIN
    -- pgcrypto's functions are being referred with public schema prefix to make pg_upgrade work
    SELECT encode(public.digest(public.gen_random_bytes(256), 'sha256'), 'hex') INTO api_key;
    RETURN api_key;
END;
$$;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4657;

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

