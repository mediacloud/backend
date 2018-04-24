--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4572 and 4573.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4572, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4573, import this SQL file:
--
--     psql mediacloud < mediawords-4572-4573.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4573;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();

create type focal_technique_type as enum ( 'Boolean Query' );

create table focal_set_definitions (
    focal_set_definitions_id    serial primary key,
    topics_id                   int not null references topics on delete cascade,
    name                        text not null,
    description                 text null,
    focal_technique             focal_technique_type not null
);

create unique index focal_set_definitions_topic_name on focal_set_definitions ( topics_id, name );

create table focus_definitions (
    focus_definitions_id        serial primary key,
    focal_set_definitions_id    int not null references focal_set_definitions on delete cascade,
    name                        text not null,
    description                 text null,
    arguments                   json not null
);

create unique index focus_definition_set_name on focus_definitions ( focal_set_definitions_id, name );

create table focal_sets (
    focal_sets_id               serial primary key,
    snapshots_id                int not null references snapshots,
    name                        text not null,
    description                 text null,
    focal_technique             focal_technique_type not null
);

create unique index focal_set_snapshot on focal_sets ( snapshots_id, name );

alter table foci alter name type text;
alter table foci drop column all_timespans;
alter table foci add focal_sets_id int references focal_sets on delete cascade;
alter table foci add description text null;

alter table foci rename query to arguments;
update foci set arguments = '{ "query": ' || to_json( arguments ) || ' }';
alter table foci alter arguments type json using arguments::json;

create unique index foci_set_name on foci ( focal_sets_id, name );

-- remove on delete set null from timespans.foci_id
alter table timespans rename foci_id to foci_id_tmp;
alter table timespans add foci_id int null references foci;
update timespans set foci_id = foci_id_tmp;
alter table timespans drop column foci_id_tmp;

insert into focal_set_definitions ( topics_id, name, focal_technique )
    select
            t.topics_id, 'Queries', 'Boolean Query'
        from topics t
        where
            exists ( select 1 from foci f where f.topics_id = t.topics_id );

insert into focus_definitions ( focal_set_definitions_id, name, arguments )
    select
            fsd.focal_set_definitions_id, f.name, f.arguments
        from focal_set_definitions fsd
            join foci f using ( topics_id );

insert into focal_sets ( snapshots_id, name, focal_technique )
    select
            q.snapshots_id, fsd.name, fsd.focal_technique
        from focal_set_definitions fsd
            join ( select distinct topics_id, snapshots_id from timespans t join foci f using ( foci_id ) ) q using ( topics_id );

update foci f set focal_sets_id = fs.focal_sets_id
    from focal_sets fs join snapshots s using ( snapshots_id )
    where f.topics_id = s.topics_id;

alter table foci alter focal_sets_id set not null;
alter table foci drop column topics_id;

delete from timespans where is_shell;

alter table timespans drop column is_shell;
