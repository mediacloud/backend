--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4745 and 4746.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4745, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4746, import this SQL file:
--
--     psql mediacloud < mediawords-4745-4746.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

drop table if exists timespan_files;
create table timespan_files (
    timespan_files_id                   serial primary key,
    timespans_id                        int not null references timespans on delete cascade,
    name                                text,
    url                                 text
);

create unique index timespan_files_timespan_name on timespan_files ( timespans_id, name );

drop table if exists snapshot_files;
create table snapshot_files (
    snapshot_files_id                       serial primary key,
    snapshots_id                        int not null references snapshots on delete cascade,
    name                                text,
    url                                 text
);

create unique index snapshot_files_snapshot_name on snapshot_files ( snapshots_id, name );


-- table for object types used for mediawords.util.public_store
create schema public_store;


create table public_store.timespan_files (
    timespan_files_id   bigserial   primary key,
    object_id           bigint not null,
    raw_data            bytea not null
);

create unique index timespan_files_id on public_store.timespan_files ( object_id );

create table public_store.snapshot_files (
    snapshot_files_id   bigserial   primary key,
    object_id           bigint not null,
    raw_data            bytea not null
);

create unique index snapshot_files_id on public_store.snapshot_files ( object_id );

create table public_store.timespan_maps (
    timespan_maps_id   bigserial   primary key,
    object_id           bigint not null,
    raw_data            bytea not null
);

create unique index timespan_maps_id on public_store.timespan_maps ( object_id );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4746;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


