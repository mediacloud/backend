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

-- list of tweet counts and fetching statuses for each day of each topic
create table topic_tweet_days (
    topic_tweet_days_id     serial primary key,
    topics_id               int not null references topics on delete cascade,
    day                     date not null,
    num_tweets              int not null,
    tweets_fetched          boolean not null default false
);

create unique index topic_tweet_days_td on topic_tweet_days ( topics_id, day );

-- list of tweets associated with a given topic
create table topic_tweets (
    topic_tweets_id         serial primary key,
    topics_id               int not null references topics on delete cascade,
    data                    json not null,
    tweet_id                varchar(256) not null,
    content                 text not null,
    publish_date            timestamp not null
);

create unique index topic_tweets_id on topic_tweets( topics_id, tweet_id );
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
