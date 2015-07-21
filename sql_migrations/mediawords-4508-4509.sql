--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4508 and 4509.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4508, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4509, import this SQL file:
--
--     psql mediacloud < mediawords-4508-4509.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

create table controversy_communities (
    controversy_communities_id      serial primary key,
    controversies_id                int not null references controversies on delete cascade,
    name                            text not null,
    creation_date                   timestamp not null default now()
);

create index controversy_communities_controversy on controversy_communities( controversies_id );
create unique index controversy_communities_name on controversy_communities( name );

create table controversy_communities_media_map (
    controversies_id        int not null references controversies on delete cascade,
    media_id                int not null references media on delete cascade
);

create index controversy_communities_media_map_c on controversy_communities_media_map ( controvoversies_id );
create index controversy_communities_media_map_m on controversy_communities_media_map ( media_id );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4509;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
