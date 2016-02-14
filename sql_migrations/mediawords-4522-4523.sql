--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4522 and 4523.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4522, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4523, import this SQL file:
--
--     psql mediacloud < mediawords-4522-4523.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

create table controversy_tweet_searches (
    controversy_tweet_searches_id           serial primary key,
    controversies_id                        int not null references controversies on delete cascade,
    ch_monitor_id                           bigint not null,
    start_date                              date not null,
    end_date                                date not null,
    tweet_count                             int not null
);

create unique index controversy_tweet_searches_controversy_date
    on controversy_tweet_searches ( controversies_id, start_date, end_date );

create table controversy_tweets (
    controversy_tweets_id                   serial primary key,
    controversy_tweet_searches_id           int not null references controversy_tweet_searches on delete cascade,
    tweet_id                                bigint not null
);

create index controversy_tweets_search on controversy_tweets ( controversy_tweet_searches_id );


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4523;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
