--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4552 and 4553.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4552, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4553, import this SQL file:
--
--     psql mediacloud < mediawords-4552-4553.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table controversies add has_been_spidered boolean not null default false;
alter table controversies add has_been_dumped boolean not null default false;

alter table controversies add state text not null default 'created but not queued';
alter table controversies add error_message text null;

alter table controversy_dumps add state text not null default 'queued';
alter table controversy_dumps add error_message text null;

update controversies c set has_been_spidered = true where not exists (
    select 1 from controversy_stories cs
        where iteration < 15 and link_mined = false and c.controversies_id = cs.controversies_id
);

update controversies set state = 'spidering completed' where has_been_spidered;
update controversies set state = 'unknown' where state != 'spidering completed';

update controversy_dumps set state = 'completed' where exists (
    select 1 from controversy_dump_time_slices cdts
        where cdts.controversy_dumps_id = cdts.controversy_dumps_id and cdts.period = 'overall'
);

update controversies c set has_been_dumped = true where exists (
    select 1 from controversy_dumps cd where c.controversies_id = cd.controversies_id and cd.state = 'completed'
);

drop view controversies_with_dates;
create view controversies_with_dates as
    select c.*,
            to_char( cd.start_date, 'YYYY-MM-DD' ) start_date,
            to_char( cd.end_date, 'YYYY-MM-DD' ) end_date
        from
            controversies c
            join controversy_dates cd on ( c.controversies_id = cd.controversies_id )
        where
            cd.boundary;

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4553;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
