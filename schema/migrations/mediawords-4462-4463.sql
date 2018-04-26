--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4462 and 4463.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4462, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4463, import this SQL file:
--
--     psql mediacloud < mediawords-4462-4463.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

drop view controversies_with_search_info;

alter table controversy_dates add boundary boolean  not null default 'false';

create view controversies_with_dates as
    select c.*,
            to_char( cd.start_date, 'YYYY-MM-DD' ) start_date,
            to_char( cd.end_date, 'YYYY-MM-DD' ) end_date
        from
            controversies c
            join controversy_dates cd on ( c.controversies_id = cd.controversies_id )
        where
            cd.boundary;

create temporary table boundary_controversy_dates as
    select controversy_dates_id
        from (
            select controversy_dates_id,
                    rank() over (
                        partition by controversies_id
                        order by ( end_date - start_date ) desc
                    ) date_range_rank
                from controversy_dates
            ) q
        where q.date_range_rank = 1;

update controversy_dates set boundary = 't'
    where controversy_dates_id in ( select controversy_dates_id from boundary_controversy_dates );

create view media_with_media_types as
    select m.*, mtm.tags_id media_type_tags_id, t.label media_type
    from
        media m
        left join (
            tags t
            join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id and ts.name = 'media_type' )
            join media_tags_map mtm on ( mtm.tags_id = t.tags_id )
        ) on ( m.media_id = mtm.media_id );

create temporary table media_type_tags ( name text, label text, description text );
insert into media_type_tags values
    ( 'Not Typed', 'Not Typed', 'The medium has not yet been typed.' ),
    ( 'Other', 'Other', 'The medium does not fit in any listed type.' );

insert into tags ( tag_sets_id, tag, label, description )
    select ts.tag_sets_id, mtt.name, mtt.name, mtt.description
        from tag_sets ts cross join media_type_tags mtt
        where ts.name = 'media_type';

discard temp;

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4463;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
