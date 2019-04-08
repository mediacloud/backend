--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4603 and 4604.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4603, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4604, import this SQL file:
--
--     psql mediacloud < mediawords-4603-4604.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

-- job states as implemented in MediaWords::AbstractJob
create table job_states (
    job_states_id           serial primary key,

    --MediaWords::Job::* class implementing the job
    class                   varchar( 1024 ) not null,

    -- short class specific state
    state                   varchar( 1024 ) not null,

    -- optional longer message describing the state, such as a stack trace for an error
    message                 text,

    -- last time this job state was updated
    last_updated            timestamp not null default now(),

    -- details about the job
    args                    json not null,
    priority                text not  null,

    -- the hostname and process_id of the running process
    hostname                text not null,
    process_id              int not null
);

create index job_states_class_date on job_states( class, last_updated );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4604;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
