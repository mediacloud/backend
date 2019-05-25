--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4612 and 4613.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4612, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4613, import this SQL file:
--
--     psql mediacloud < mediawords-4612-4613.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--
create type topics_job_queue_type AS ENUM ( 'mc', 'public' );

alter table topics add job_queue topics_job_queue_type;
update topics set job_queue = 'mc';
alter table topics alter job_queue set not null;

alter table topics add max_stories int null;

create temporary table topic_num_stories as
     select t.topics_id, max( ts.story_count ) num_stories
        from topics t
            join snapshots s using ( topics_id )
            join timespans ts using ( snapshots_id )
        group by t.topics_id;

update topics set max_stories = 200000;
update topics t set max_stories = tns.num_stories * 2
    from topic_num_stories tns
    where
        t.topics_id = tns.topics_id and
        tns.num_stories > 100000;

alter table topics alter max_stories set not null;

alter table topics add max_stories_reached boolean not null default false;

alter table auth_users add max_topic_stories int not null default 100000;

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4613;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
