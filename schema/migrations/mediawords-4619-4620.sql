--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4619 and 4620.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4619, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4620, import this SQL file:
--
--     psql mediacloud < mediawords-4619-4620.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


ALTER FUNCTION generate_api_token()
    RENAME TO generate_api_key;

ALTER INDEX auth_users_token
    RENAME TO auth_users_api_key;

ALTER INDEX auth_user_ip_tokens_token
    RENAME TO auth_user_ip_tokens_api_key_ip_address;

ALTER TABLE auth_users
    RENAME COLUMN api_token TO api_key;

ALTER TABLE auth_user_ip_tokens
    RENAME TO auth_user_ip_address_api_keys;

ALTER TABLE auth_user_ip_address_api_keys
    RENAME COLUMN auth_user_ip_tokens_id TO auth_user_ip_address_api_keys_id;
ALTER TABLE auth_user_ip_address_api_keys
    RENAME COLUMN api_token TO api_key;

ALTER INDEX auth_user_ip_tokens_api_key_ip_address
    RENAME TO auth_user_ip_address_api_keys_api_key_ip_address;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4620;

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
