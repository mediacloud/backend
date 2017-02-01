--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4606 and 4607.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4606, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4607, import this SQL file:
--
--     psql mediacloud < mediawords-4606-4607.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table topics drop topic_tags_sets_id;
alter table topics drop has_been_spidered;
alter table topics drop has_been _dumped;
alter table topics rename error_message to message;

update topics set state = 'queued' where state = 'created but not queued';
update topics set state = 'completed' where state = 'ready';
update topics set state = 'running', message = state where length( state ) > 25;

alter table snapshots rename error_message to message;

update snapshots set state = 'error' where state like '%failed';
update snapshots set state = 'error', message = state where state ne 'completed';

drop trigger topic_tag_set on topics;
drop function insert_topic_tag_set();

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4607;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
