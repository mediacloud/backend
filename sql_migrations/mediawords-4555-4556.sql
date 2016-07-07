--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4555 and 4556.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4555, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4556, import this SQL file:
--
--     psql mediacloud < mediawords-4555-4556.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table cd.story_link_counts add media_inlink_count int;
alter table cd.medium_link_counts add media_inlink_count int;
alter table cd.medium_link_counts add sum_media_inlink_count int;

update cd.story_link_counts set media_inlink_count = 0;
update cd.medium_link_counts set media_inlink_count = 0, sum_media_inlink_count = 0;

create temporary table story_media_links as
    SELECT
        count(*) source_media_link_count,
        s.media_id source_media_id,
        sl.ref_stories_id ref_stories_id,
        sl.controversy_dump_time_slices_id
    FROM cd.story_links sl
        join controversy_dump_time_slices cdts using ( controversy_dump_time_slices_id )
        join cd.stories s on ( s.stories_id = sl.source_stories_id and s.controversy_dumps_id = cdts.controversy_dumps_id )
    group by s.media_id, sl.ref_stories_id, sl.controversy_dump_time_slices_id;

create temporary table story_media_link_counts as
    select
        count(*) media_inlink_count,
        sml.ref_stories_id stories_id,
        sml.controversy_dump_time_slices_id
    from
        story_media_links sml
    group by sml.ref_stories_id, sml.controversy_dump_time_slices_id;

update cd.story_link_counts slc set media_inlink_count = smlc.media_inlink_count
    from story_media_link_counts smlc
    where
        slc.stories_id = smlc.stories_id and
        slc.controversy_dump_time_slices_id = smlc.controversy_dump_time_slices_id;

create temporary table medium_media_link_counts as
    select
            count(*) media_inlink_count,
            ml.ref_media_id as media_id,
            ml.controversy_dump_time_slices_id
        from
            cd.medium_links ml
        group by ml.ref_media_id, ml.controversy_dump_time_slices_id;

create temporary table medium_sum_media_link_counts as
    select
            sum( media_inlink_count ) sum_media_inlink_count,
            s.media_id,
            smlc.controversy_dump_time_slices_id
        from
            story_media_link_counts smlc
            join controversy_dump_time_slices using ( controversy_dump_time_slices_id )
            join cd.stories s using ( stories_id, controversy_dumps_id )
        group by s.media_id, smlc.controversy_dump_time_slices_id;


update cd.medium_link_counts mlc set
        media_inlink_count = mmlc.media_inlink_count,
        sum_media_inlink_count = msmlc.sum_media_inlink_count
    from
        medium_media_link_counts mmlc,
        medium_sum_media_link_counts msmlc
    where
    mmlc.media_id = mlc.media_id and
    mmlc.controversy_dump_time_slices_id = mlc.controversy_dump_time_slices_id and
    msmlc.media_id = mlc.media_id and
    msmlc.controversy_dump_time_slices_id = mlc.controversy_dump_time_slices_id;


alter table cd.story_link_counts alter media_inlink_count set not null;
alter table cd.medium_link_counts alter media_inlink_count set not null;
alter table cd.medium_link_counts alter sum_media_inlink_count set not null;

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4556;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
