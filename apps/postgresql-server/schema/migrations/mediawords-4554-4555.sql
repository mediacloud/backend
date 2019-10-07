--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4554 and 4555.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4554, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4555, import this SQL file:
--
--     psql mediacloud < mediawords-4554-4555.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table cd.story_link_counts add facebook_share_count int null;

update cd.story_link_counts slc set facebook_share_count = ss.facebook_share_count
    from story_statistics ss where ss.stories_id = slc.stories_id;

drop view controversies_with_dates;
alter table controversies drop column process_with_bitly;
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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4555;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
