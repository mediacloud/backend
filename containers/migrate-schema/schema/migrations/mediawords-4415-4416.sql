--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4415 and 4416.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4415, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4416, import this SQL file:
--
--     psql mediacloud < mediawords-4415-4416.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4416;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';


begin;

create table cdts_files (
    cdts_files_id                   serial primary key,
    controversy_dump_time_slices_id int not null references controversy_dump_time_slices on delete cascade,
    file_name                       text,
    file_content                    text
);

create index cdts_files_cdts on cdts_files ( controversy_dump_time_slices_id );

create table cd_files (
    cd_files_id                     serial primary key,
    controversy_dumps_id            int not null references controversy_dumps on delete cascade,
    file_name                       text,
    file_content                    text
);

create index cd_files_cd on cd_files ( controversy_dumps_id );

insert into cdts_files
    ( controversy_dump_time_slices_id, file_name, file_content )
    select controversy_dump_time_slices_id, 'stories.csv', stories_csv
        from controversy_dump_time_slices;

insert into cdts_files
    ( controversy_dump_time_slices_id, file_name, file_content )
    select controversy_dump_time_slices_id, 'story_links.csv', story_links_csv
        from controversy_dump_time_slices;

insert into cdts_files
    ( controversy_dump_time_slices_id, file_name, file_content )
    select controversy_dump_time_slices_id, 'media.csv', media_csv
        from controversy_dump_time_slices;

insert into cdts_files
    ( controversy_dump_time_slices_id, file_name, file_content )
    select controversy_dump_time_slices_id, 'medium_links.csv', medium_links_csv
        from controversy_dump_time_slices;

insert into cdts_files
    ( controversy_dump_time_slices_id, file_name, file_content )
    select controversy_dump_time_slices_id, 'media.gexf', gexf
        from controversy_dump_time_slices;

insert into cd_files
    ( controversy_dumps_id, file_name, file_content )
    select controversy_dumps_id, 'daily_counts.csv', daily_counts_csv
        from controversy_dumps;

insert into cd_files
    ( controversy_dumps_id, file_name, file_content )
    select controversy_dumps_id, 'weekly_counts.csv', weekly_counts_csv
        from controversy_dumps;

alter table controversy_dump_time_slices drop stories_csv;
alter table controversy_dump_time_slices drop story_links_csv;
alter table controversy_dump_time_slices drop media_csv;
alter table controversy_dump_time_slices drop medium_links_csv;
alter table controversy_dump_time_slices drop gexf;

alter table controversy_dumps drop daily_counts_csv;
alter table controversy_dumps drop weekly_counts_csv;

commit; 

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();
