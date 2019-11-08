--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4731 and 4732.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4731, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4732, import this SQL file:
--
--     psql mediacloud < mediawords-4731-4732.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--


ALTER TABLE auth_user_limits
    ADD COLUMN max_topic_stories INTEGER NOT NULL DEFAULT 100000;

UPDATE auth_user_limits
SET max_topic_stories = auth_users.max_topic_stories
FROM public.auth_users
WHERE auth_user_limits.auth_users_id = auth_users.auth_users_id;

ALTER TABLE auth_users
    DROP COLUMN max_topic_stories;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4732;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
