--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4479 and 4480.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4479, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4480, import this SQL file:
--
--     psql mediacloud < mediawords-4479-4480.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

ALTER TABLE story_statistics
    RENAME COLUMN twitter_url_tweet_count_error TO twitter_api_error;
ALTER TABLE story_statistics
    RENAME COLUMN facebook_share_count_error TO facebook_api_error;

ALTER TABLE story_statistics
    ADD COLUMN facebook_comment_count INT NULL,
    ADD COLUMN twitter_api_collect_date TIMESTAMP NULL,
    ADD COLUMN facebook_api_collect_date TIMESTAMP NULL;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4480;
    
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
