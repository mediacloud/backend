--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4515 and 4516.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4515, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4516, import this SQL file:
--
--     psql mediacloud < mediawords-4515-4516.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- stats for deprecated Twitter share counts
create table story_statistics_twitter (
    story_statistics_id         serial      primary key,
    stories_id                  int         not null references stories on delete cascade,

    twitter_url_tweet_count     int         null,
    twitter_api_collect_date    timestamp   null,
    twitter_api_error           text        null
);

create unique index story_statistics_twitter_story on story_statistics_twitter ( stories_id );


-- Migrate Twitter stats collected so far to the new table
INSERT INTO story_statistics_twitter (stories_id, twitter_url_tweet_count, twitter_api_collect_date, twitter_api_error)
    SELECT stories_id, twitter_url_tweet_count, twitter_api_collect_date, twitter_api_error
    FROM story_statistics;


ALTER TABLE story_statistics
    DROP COLUMN twitter_url_tweet_count,
    DROP COLUMN twitter_api_collect_date,
    DROP COLUMN twitter_api_error;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4516;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

