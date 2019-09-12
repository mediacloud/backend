--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4728 and 4729.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4728, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4729, import this SQL file:
--
--     psql mediacloud < mediawords-4728-4729.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table topics add respider_stories        boolean not null default false;
alter table topics add respider_start_date     date null;
alter table topics add respider_end_date       date null;

alter table timespans alter snapshots_id drop not null;
alter table timespans add archive_snapshots_id            int null references snapshots on delete cascade;
alter table timespans add constraint topics_snapshot 
    check ( ( snapshots_id is null and archive_snapshots_id is not null ) or 
        ( snapshots_id is not null and archive_snapshots_id is null ) );


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4729;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


