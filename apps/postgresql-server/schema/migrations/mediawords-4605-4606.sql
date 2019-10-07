--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4605 and 4606.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4605, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4606, import this SQL file:
--
--     psql mediacloud < mediawords-4605-4606.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table topics add start_date date;
alter table topics add end_date date;

update topics t set start_date = td.start_date, end_date = td.end_date
        from topic_dates td
        where
            t.topics_id = td.topics_id and
            td.boundary;

alter table topics alter start_date set not null;
alter table topics alter end_date set not null;

drop view topics_with_dates;
drop table if exists snapshot_tags;

create table topics_media_map (
    topics_id       int not null references topics on delete cascade,
    media_id        int not null references media on delete cascade
);

create index topics_media_map_topic on topics_media_map ( topics_id );

create table topics_media_tags_map (
    topics_id       int not null references topics on delete cascade,
    tags_id         int not null references tags on delete cascade
);

create index topics_media_tags_map_topic on topics_media_tags_map ( topics_id );


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4606;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
