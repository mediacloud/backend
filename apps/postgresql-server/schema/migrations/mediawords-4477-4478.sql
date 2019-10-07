--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4477 and 4478.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4477, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4478, import this SQL file:
--
--     psql mediacloud < mediawords-4477-4478.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

create table controversy_query_slices (
    controversy_query_slices_id     serial primary key,
    controversies_id                int not null references controversies on delete cascade,
    name                            varchar ( 1024 ) not null,
    query                           text not null,
    all_time_slices                 boolean not null
);

alter table controversy_dump_time_slices
    add controversy_query_slices_id int null references controversy_query_slices on delete set null;
    
alter table controversy_dump_time_slices add is_shell boolean not null default false;
    
--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4478;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


