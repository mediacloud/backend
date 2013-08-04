--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4419 and 4420.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4419, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4420, import this SQL file:
--
--     psql mediacloud < mediawords-4419-4420.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--


create table controversy_dump_tags (
    controversy_dump_tags_id    serial primary key,
    controversies_id            int not null references controversies on delete cascade,
    tags_id                     int not null references tags
);

alter table controversy_dump_time_slices add tags_id int references tags;

alter table cd.controversy_links_cross_media drop media_name;
alter table cd.controversy_links_cross_media drop ref_media_name;
alter table cd.stories drop description;

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4420;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


