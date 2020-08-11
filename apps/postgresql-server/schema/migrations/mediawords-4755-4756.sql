--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4755 and 4756.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4755, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4756, import this SQL file:
--
--     psql mediacloud < mediawords-4755-4756.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--


-- There's nothing worth preserving in both of these tables
DROP TABLE celery_groups;
DROP TABLE celery_tasks;

CREATE TABLE celery_groups (
    id          BIGINT                      NOT NULL    PRIMARY KEY,
    taskset_id  CHARACTER VARYING(155)      NULL        UNIQUE,
    result      BYTEA                       NULL,
    date_done   TIMESTAMP WITHOUT TIME ZONE NULL
);

CREATE TABLE celery_tasks (
    id          BIGINT                      NOT NULL    PRIMARY KEY,
    task_id     CHARACTER VARYING(155)      NULL        UNIQUE,
    status      CHARACTER VARYING(50)       NULL,
    result      BYTEA                       NULL,
    date_done   TIMESTAMP WITHOUT TIME ZONE NULL,
    traceback   TEXT                        NULL
);


-- This refers to the 4754-4755 migration, but we might want to rerun it in
-- production
ALTER TABLE story_sentences_p ALTER COLUMN publish_date DROP NOT NULL;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4756;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
