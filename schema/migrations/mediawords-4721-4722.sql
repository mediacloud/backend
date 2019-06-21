--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4721 and 4722.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4721, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4722, import this SQL file:
--
--     psql mediacloud < mediawords-4721-4722.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table topics drop twitter_topics_id;

create type topic_platform_type AS enum ( 'web', 'twitter' );
alter table topics add platform topic_platform_type not null default 'web';

create type topic_source_type AS enum ( 'mediacloud', 'crimson_hexagon', 'archive_org' );
create table topic_seed_queries (
    topic_seed_queries_id   serial primary key,
    topics_id               int not null references topics on delete cascade,
    source                  topic_source_type not null,
    platform                topic_platform_type not null,
    query                   text,
    imported_date           timestamp
);

create index topic_seed_queries_topic on topic_seed_queries( topics_id );

update topics set platform = 'twitter' where ch_monitor_id is not null;
insert into topic_seed_queries
	select topics_id, 'twitter', 'crimson_hexagon', ch_monitor_id
		from topics where ch_monitor_id is not null;

alter table topics drop ch_monitor_id;

alter table topic_tweet_days rename tweet_count to num_tweets;
alter table topic_tweet_days drop num_ch_tweets;

create view topic_tweet_full_urls as
    select distinct
            t.topics_id,
            tt.topic_tweets_id, tt.content, tt.publish_date, tt.twitter_user,
            ttd.day, ttd.num_tweets, ttd.tweets_fetched,
            ttu.url, tsu.stories_id
        from
            topics t
            join topic_tweet_days ttd on ( t.topics_id = ttd.topics_id )
            join topic_tweets tt using ( topic_tweet_days_id )
            join topic_tweet_urls ttu using ( topic_tweets_id )
            left join topic_seed_urls tsu
                on ( tsu.topics_id = t.topics_id and ttu.url = tsu.url );

alter table snap.tweet_stories rename tweet_count to num_tweets;
alter table snap.tweet_stories drop num_ch_tweets;
--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4722;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


