--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4752 and 4753.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4752, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4753, import this SQL file:
--
--     psql mediacloud < mediawords-4752-4753.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

CREATE TABLE IF NOT EXISTS celery_groups (
    id          INTEGER                     NOT NULL    PRIMARY KEY,
    taskset_id  CHARACTER VARYING(155)      NULL        UNIQUE,
    result      BYTEA                       NULL,
    date_done   TIMESTAMP WITHOUT TIME ZONE NULL
);

CREATE TABLE IF NOT EXISTS celery_tasks (
    id          INTEGER                     NOT NULL    PRIMARY KEY,
    task_id     CHARACTER VARYING(155)      NULL        UNIQUE,
    status      CHARACTER VARYING(50)       NULL,
    result      BYTEA                       NULL,
    date_done   TIMESTAMP WITHOUT TIME ZONE NULL,
    traceback   TEXT                        NULL
);

CREATE SEQUENCE IF NOT EXISTS task_id_sequence AS BIGINT;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4753;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
