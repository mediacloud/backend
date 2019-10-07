--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4475 and 4476.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4475, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4476, import this SQL file:
--
--     psql mediacloud < mediawords-4475-4476.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

-- stats for various externally dervied statistics about a story.  keeping this separate for now
-- from the bitly stats for simplicity sake during implementatino and testing
create table story_statistics (
    story_statistics_id             serial  primary key,
    stories_id                      int     not null references stories on delete cascade,
    twitter_url_tweet_count         int     null,
    twitter_url_tweet_count_error   text    null,
    facebook_share_count            int     null,
    facebook_share_count_error      text    null
);

create unique index story_statistics_story on story_statistics ( stories_id );


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4476;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


