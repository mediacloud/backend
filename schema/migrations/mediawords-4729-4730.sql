--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4729 and 4730.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4729, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4730, import this SQL file:
--
--     psql mediacloud < mediawords-4729-4730.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--
create type topic_platform_type AS enum ( 'web', 'twitter', 'generic_post', 'mediacloud_topic' );
create type topic_mode_type AS enum ( 'web', 'url_sharing' );
create type topic_source_type AS enum ( 'mediacloud', 'crimson_hexagon', 'archive_org', 'csv' );

alter table topics add mode                    topic_mode_type not null default 'web';

alter table timespans rename column tweet_count to post_count;

alter table snap.story_link_counts rename column simple_tweet_count to post_count;

alter table topic_tweet_days rename to topic_post_days;

alter table topic_post_days rename column topic_tweet_days_id to topic_post_days_id;
alter table topic_post_days rename column num_tweets to num_posts;
alter table topic_post_days rename columb tweets_fetched to posts_fetched;

alter table rename topic_tweets to topic_posts;
alter table topic_posts rename topic_tweets_id to topic_posts_id;
alter table topic_posts rename topic_tweet_days_id to topic_post_days_id;
alter table topic_posts rename tweet_id to post_id;
alter table topic_posts rename twitter_user to author;
alter table topic_posts add channel varchar( 1024 ) not null;
alter table topic_posts add url text null;

create index topic_post_topic_channel on topic_posts( topic_post_days_id, channel );

alter table topic_tweet_urls renanme to topic_post_urls;
alter table topic_post_urls rename topic_tweet_urls_id to topic_post_urls_id;
alter table topic_post_urls rename topic_tweets_id to topic_posts_id;

drop view topic_tweet_full_urls;
create view topic_post_full_urls as
    select distinct
            t.topics_id,
            tt.topic_posts_id, tt.content, tt.publish_date, tt.author,
            ttd.day, ttd.num_posts, ttd.posts_fetched,
            ttu.url, tsu.stories_id
        from
            topics t
            join topic_post_days ttd on ( t.topics_id = ttd.topics_id )
            join topic_posts tt using ( topic_post_days_id )
            join topic_post_urls ttu using ( topic_posts_id )
            left join topic_seed_urls tsu
                on ( tsu.topics_id = t.topics_id and ttu.url = tsu.url );

alter table snap.timespan_tweets rename to snap.timespan_posts;
alter table snap.timespan_posts rename topic_tweets_id to topic_posts_id;

alter table snap.tweet_stories rename to snap.post_stories;
alter table snap.post_stories rename topic_tweets_id to topic_posts_id;
alter table snap.post_stories rename twitter_user to author;
alter table snap.post_stories rename num_tweets to num_posts;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4730;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


