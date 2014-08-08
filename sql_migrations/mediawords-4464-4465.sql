--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4464 and 4465.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4464, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4465, import this SQL file:
--
--     psql mediacloud < mediawords-4464-4465.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Temporarily drop views that depend on "downloads.type" column
DROP VIEW story_extracted_texts;
DROP VIEW downloads_sites;
DROP VIEW downloads_non_media;
DROP VIEW downloads_media;
DROP VIEW daily_stats;
DROP VIEW downloads_to_be_extracted;
DROP VIEW downloads_with_error_in_past_day;
DROP VIEW downloads_in_past_day;


-- Update constraints to not include obsolete enum values
ALTER TABLE downloads
    DROP CONSTRAINT downloads_feed_id_valid;
ALTER TABLE downloads
    ADD CONSTRAINT downloads_feed_id_valid check (feeds_id is not null);

ALTER TABLE downloads
    DROP CONSTRAINT downloads_story;
ALTER TABLE downloads
    ADD CONSTRAINT downloads_story check (((type = 'feed') and stories_id is null) or (stories_id is not null));

-- Drop obsolete indices
DROP INDEX downloads_spider_urls;
DROP INDEX downloads_spider_download_errors_to_clear;
DROP INDEX downloads_queued_spider;

-- Remove old values from "download_type" enum
SELECT enum.enum_del('download_type', 'spider_blog_home');
SELECT enum.enum_del('download_type', 'spider_posting');
SELECT enum.enum_del('download_type', 'spider_rss');
SELECT enum.enum_del('download_type', 'spider_blog_friends_list');
SELECT enum.enum_del('download_type', 'spider_validation_blog_home');
SELECT enum.enum_del('download_type', 'spider_validation_rss');
SELECT enum.enum_del('download_type', 'archival_only');

-- Recreate the views
CREATE VIEW story_extracted_texts AS
    SELECT stories_id, array_to_string(array_agg(download_text), ' ') as extracted_text 
    FROM (select * from downloads natural join download_texts order by downloads_id) as downloads
    GROUP BY stories_id;

CREATE VIEW downloads_media AS
    SELECT d.*, f.media_id as _media_id
    FROM downloads d, feeds f
    WHERE d.feeds_id = f.feeds_id;

CREATE VIEW downloads_sites AS
    SELECT site_from_host( host ) as site, *
    FROM downloads_media;

CREATE VIEW downloads_non_media AS
    SELECT d.*
    FROM downloads d
    WHERE d.feeds_id is null;

CREATE VIEW downloads_in_past_day AS
    SELECT *
    FROM downloads
    WHERE download_time > now() - interval '1 day';

CREATE VIEW downloads_with_error_in_past_day AS
    SELECT *
    FROM downloads_in_past_day
    WHERE state = 'error';

CREATE VIEW downloads_to_be_extracted AS
    SELECT *
    FROM downloads
    WHERE extracted = 'f' and state = 'success' and type = 'content';

CREATE VIEW daily_stats AS
    SELECT *
    FROM (SELECT count(*) as daily_downloads from downloads_in_past_day) as dd,
         (SELECT count(*) as daily_stories from stories_collected_in_past_day) as ds,
         (SELECT count(*) as downloads_to_be_extracted from downloads_to_be_extracted) as dex,
         (SELECT count(*) as download_errors from downloads_with_error_in_past_day ) as er;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4465;
    
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

