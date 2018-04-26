--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4414 and 4415.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4414, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4415, import this SQL file:
--
--     psql mediacloud < mediawords-4414-4415.sql
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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4415;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';


begin;

alter table controversy_dump_time_slices add story_count int;
alter table controversy_dump_time_slices add story_link_count int;
alter table controversy_dump_time_slices add medium_count int;
alter table controversy_dump_time_slices add medium_link_count int;

update controversy_dump_time_slices cdts set story_count = q.count
    from ( 
        select count(*) count, c.controversy_dump_time_slices_id
            from cd.story_link_counts c
            group by c.controversy_dump_time_slices_id
    ) q
    where
        q.controversy_dump_time_slices_id = cdts.controversy_dump_time_slices_id;

update controversy_dump_time_slices set story_count = 0 where story_count is null;

update controversy_dump_time_slices cdts set story_link_count = q.count
    from ( 
        select count(*) count, c.controversy_dump_time_slices_id
            from cd.story_links c
            group by c.controversy_dump_time_slices_id
    ) q
    where
        q.controversy_dump_time_slices_id = cdts.controversy_dump_time_slices_id;

update controversy_dump_time_slices set story_link_count = 0 where story_link_count is null;

update controversy_dump_time_slices cdts set medium_count = q.count
    from ( 
        select count(*) count, c.controversy_dump_time_slices_id
            from cd.medium_link_counts c
            group by c.controversy_dump_time_slices_id
    ) q
    where
        q.controversy_dump_time_slices_id = cdts.controversy_dump_time_slices_id;

update controversy_dump_time_slices set medium_count = 0 where medium_count is null;

update controversy_dump_time_slices cdts set medium_link_count = q.count
    from ( 
        select count(*) count, c.controversy_dump_time_slices_id
            from cd.medium_links c
            group by c.controversy_dump_time_slices_id
    ) q
    where
        q.controversy_dump_time_slices_id = cdts.controversy_dump_time_slices_id;

update controversy_dump_time_slices set medium_link_count = 0 where medium_link_count is null;

alter table controversy_dump_time_slices alter story_count set not null;
alter table controversy_dump_time_slices alter story_link_count set not null;
alter table controversy_dump_time_slices alter medium_count set not null;
alter table controversy_dump_time_slices alter medium_link_count set not null;

commit; 

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();
