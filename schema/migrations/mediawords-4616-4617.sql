--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4616 and 4617.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4616, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4617, import this SQL file:
--
--     psql mediacloud < mediawords-4616-4617.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--


-- assume default num_partitions of 5

alter table retweeter_scores add num_partitions int;
update retweeter_scores set num_partitions = 5;
alter table retweeter_scores alter num_partitions set not null;

alter table retweeter_media add partition float;
update retweeter_media set partition = floor( ( score + 1 ) * 2.4999 );
alter table retweeter_media alter partition set not null;

create table retweeter_partition_matrix (
    retweeter_partition_matrix_id       serial primary key,
    retweeter_scores_id                 int not null references retweeter_scores on delete cascade,
    retweeter_groups_id                 int not null references retweeter_groups on delete cascade,
    group_name                          text not null,
    share_count                         int not null,
    group_proportion                    float not null,
    partition                           int not null
);

create index retweeter_partition_matrix_score on retweeter_partition_matrix ( retweeter_scores_id );

insert into retweeter_partition_matrix
    ( retweeter_scores_id, share_count, group_proportion, partition, retweeter_groups_id, group_name )
    with rpm as (
        select
                rs.retweeter_scores_id,
                sum( rs.share_count ) share_count,
                rm.partition,
                rg.retweeter_groups_id,
                rg.name group_name
            from retweeter_stories rs
                join retweeter_groups_users_map rgum
                    on ( rgum.retweeted_user = rs.retweeted_user and
                            rs.retweeter_scores_id = rgum.retweeter_scores_id )
                join retweeter_groups rg using ( retweeter_groups_id )
                join stories s using ( stories_id )
                join retweeter_media rm
                    on ( s.media_id = rm.media_id and rm.retweeter_scores_id = rs.retweeter_scores_id )
            group by rs.retweeter_scores_id, rg.retweeter_groups_id, rm.partition
    ),

    rpm_totals as (
        select
                sum( share_count ) group_share_count,
                retweeter_groups_id
            from rpm
            group by retweeter_groups_id
    )

    select
            rpm.retweeter_scores_id,
            rpm.share_count,
            ( rpm.share_count::float / rpm_totals.group_share_count::float )::float group_proprtion,
            rpm.partition,
            rpm.retweeter_groups_id,
            rpm.group_name
        from rpm
            join rpm_totals using ( retweeter_groups_id );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4617;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
