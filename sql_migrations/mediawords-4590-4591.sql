--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4590 and 4591.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4590, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4591, import this SQL file:
--
--     psql mediacloud < mediawords-4590-4591.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table topics add ch_monitor_id bigint null;
alter table topics add twitter_parent_topics_id int null references topics on delete set null;

alter table topic_dead_links alter stories_id set not null;

alter table snap.story_link_counts add simple_tweet_count int null;
alter table snap.story_link_counts add normalized_tweet_count int null;

alter table snap.medium_link_counts add facebook_share_count int null;
alter table snap.medium_link_counts add simple_tweet_count int null;
alter table snap.medium_link_counts add normalized_tweet_count int null;

-- list of tweet counts and fetching statuses for each day of each topic
create table topic_tweet_days (
    topic_tweet_days_id     serial primary key,
    topics_id               int not null references topics on delete cascade,
    day                     date not null,
    tweet_count             int not null,
    num_ch_tweets           int not null,
    tweets_fetched          boolean not null default false
);

create unique index topic_tweet_days_td on topic_tweet_days ( topics_id, day );

-- list of tweets associated with a given topic
create table topic_tweets (
    topic_tweets_id         serial primary key,
    topic_tweet_days_id     int not null references topic_tweet_days on delete cascade,
    data                    json not null,
    tweet_id                varchar(256) not null,
    content                 text not null,
    publish_date            timestamp not null,
    twitter_user            varchar( 1024 ) not null
);

create unique index topic_tweets_id on topic_tweets( topic_tweet_days_id, tweet_id );
create index topic_tweet_topic_user on topic_tweets( topic_tweet_days_id, twitter_user );

-- urls parsed from topic tweets and imported into topic_seed_urls
create table topic_tweet_urls (
    topic_tweet_urls_id     serial primary key,
    topic_tweets_id         int not null references topic_tweets on delete cascade,
    url                     varchar (1024) not null
);

create index topic_tweet_urls_url on topic_tweet_urls ( url );
create unique index topic_tweet_urls_tt on topic_tweet_urls ( topic_tweets_id, url );

-- view that joins together the related topic_tweets, topic_tweet_days, topic_tweet_urls, and topic_seed_urls tables
-- tables for convenient querying of topic twitter url data
create view topic_tweet_full_urls as
    select
            t.topics_id parent_topics_id, twt.topics_id twitter_topics_id,
            tt.topic_tweets_id, tt.content, tt.publish_date, tt.twitter_user,
            ttd.day, ttd.tweet_count, ttd.num_ch_tweets, ttd.tweets_fetched,
            ttu.url, tsu.topic_seed_urls_id, tsu.stories_id
        from
            topics t
            join topics twt on ( t.topics_id = twt.twitter_parent_topics_id )
            join topic_tweet_days ttd on ( t.topics_id = ttd.topics_id )
            join topic_tweets tt using ( topic_tweet_days_id )
            join topic_tweet_urls ttu using ( topic_tweets_id )
            left join topic_seed_urls tsu on ( tsu.topics_id = twt.topics_id and ttu.url = tsu.url );

-- copy structure of topic_tweet_full_urls for snapshot table
create table snap.topic_tweet_full_urls as select * from topic_tweet_full_urls where false;
alter table snap.topic_tweet_full_urls add snapshots_id int references snapshots on delete cascade;

create index snap_topic_tweet_full_urls_snap_story on snap.topic_tweet_full_urls( snapshots_id, stories_id );
create index snap_topic_tweet_full_urls_snap_user on snap.topic_tweet_full_urls( snapshots_id, twitter_user );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4591;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
