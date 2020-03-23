--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4742 and 4743.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4742, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4743, import this SQL file:
--
--     psql mediacloud < mediawords-4742-4743.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table focal_sets alter focal_technique type text;
alter table focal_set_definitions alter focal_technique type text;

drop type focal_technique_type;

create type focal_technique_type as enum ( 'Boolean Query', 'URL Sharing' );

alter table focal_sets alter focal_technique type focal_technique_type using focal_technique::focal_technique_type;
alter table focal_set_definitions alter focal_technique type focal_technique_type
    using focal_technique::focal_technique_type;

drop view topic_post_full_urls;

create view topic_post_stories as
    select 
            tsq.topics_id,
            tp.topic_posts_id, tp.content, tp.publish_date, tp.author, tp.channel, tp.data,
            tpd.topic_seed_queries_id,
            ts.stories_id,
            tpu.url
        from
            topic_seed_queries tsq
            join topic_post_days tpd using ( topic_seed_queries_id )
            join topic_posts tp using ( topic_post_days_id )
            join topic_post_urls tpu using ( topic_posts_id )
            join topic_seed_urls tsu
                on ( tsu.topics_id = tsq.topics_id and tsu.url = tpu.url )
            join topic_stories ts 
                on ( ts.topics_id = tsq.topics_id and ts.stories_id = tsu.stories_id );

drop table snap.post_stories;
--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4743;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


