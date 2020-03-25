--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4743 and 4744.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4743, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4744, import this SQL file:
--
--     psql mediacloud < mediawords-4743-4744.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table snap.story_link_counts rename post_count to author_count;
alter table snap.story_link_counts add post_count int null;
alter table snap.story_link_counts add channel_count int null;

create index story_link_counts_fb on snap.story_link_counts ( timespans_id, facebook_share_count desc nulls last );
create index story_link_counts_post on snap.story_link_counts ( timespans_id, post_count desc nulls last);
create index story_link_counts_author on snap.story_link_counts ( timespans_id, author_count desc nulls last);
create index story_link_counts_channel on snap.story_link_counts ( timespans_id, channel_count desc nulls last);

alter table snap.medium_link_counts rename post_count to sum_author_count;
alter table sanp.medium_link_counts add sum_post_count int null;
alter table snap.medium_link_counts add sum_channel_count int null;

create index medium_link_counts_fb on snap.medium_link_counts ( timespans_id, facebook_share_count desc nulls last);
create index medium_link_counts_sum_post on snap.medium_link_counts ( timespans_id, sum_post_count desc nulls last);
create index medium_link_counts_sum_author on snap.medium_link_counts ( timespans_id, sum_author_count desc nulls last);
create index medium_link_counts_sum_channel on snap.medium_link_counts ( timespans_id, sum_channel_count desc nulls last);

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4744;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


