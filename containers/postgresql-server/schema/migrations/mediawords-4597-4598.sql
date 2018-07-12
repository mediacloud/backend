--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4597 and 4598.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4597, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4598, import this SQL file:
--
--     psql mediacloud < mediawords-4597-4598.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

create table snap.tweet_stories (
    snapshots_id        int not null references snapshots on delete cascade,
    topic_tweets_id     int not null references topic_tweets on delete cascade,
    publish_date        date not null,
    twitter_user        varchar( 1024 ) not null,
    stories_id          int not null,
    media_id            int not null,
    num_ch_tweets       int not null,
    tweet_count         int not null
);

create index snap_tweet_stories on snap.tweet_stories ( snapshots_id );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4598;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
