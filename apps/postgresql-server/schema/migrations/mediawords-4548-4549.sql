--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4548 and 4549.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4548, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4549, import this SQL file:
--
--     psql mediacloud < mediawords-4548-4549.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Will recreate right after
DROP VIEW IF EXISTS daily_stats;
DROP VIEW IF EXISTS downloads_sites;
DROP VIEW IF EXISTS downloads_media;
DROP VIEW IF EXISTS downloads_non_media;
DROP VIEW IF EXISTS downloads_to_be_extracted;
DROP VIEW IF EXISTS downloads_with_error_in_past_day;
DROP VIEW IF EXISTS downloads_in_past_day;


DROP TRIGGER IF EXISTS download_relative_file_path_trigger ON downloads;

DROP FUNCTION IF EXISTS get_relative_file_path("path" text);

DROP FUNCTION IF EXISTS download_relative_file_path_trigger();

DROP INDEX IF EXISTS file_status_downloads_time_new_format;

DROP INDEX IF EXISTS relative_file_paths_new_format_to_verify;

DROP INDEX IF EXISTS relative_file_paths_to_verify;


ALTER TABLE downloads
	DROP COLUMN old_download_time,
	DROP COLUMN old_state,
	DROP COLUMN file_status,
	DROP COLUMN relative_file_path;


create view downloads_media as select d.*, f.media_id as _media_id from downloads d, feeds f where d.feeds_id = f.feeds_id;
create view downloads_non_media as select d.* from downloads d where d.feeds_id is null;
CREATE VIEW downloads_sites as select site_from_host( host ) as site, * from downloads_media;
CREATE VIEW downloads_to_be_extracted as select * from downloads where extracted = 'f' and state = 'success' and type = 'content';
CREATE VIEW downloads_in_past_day as select * from downloads where download_time > now() - interval '1 day';
CREATE VIEW downloads_with_error_in_past_day as select * from downloads_in_past_day where state = 'error';

CREATE VIEW daily_stats AS
    SELECT *
    FROM (
            SELECT COUNT(*) AS daily_downloads
            FROM downloads_in_past_day
         ) AS dd,
         (
            SELECT COUNT(*) AS daily_stories
            FROM stories_collected_in_past_day
         ) AS ds,
         (
            SELECT COUNT(*) AS downloads_to_be_extracted
            FROM downloads_to_be_extracted
         ) AS dex,
         (
            SELECT COUNT(*) AS download_errors
            FROM downloads_with_error_in_past_day
         ) AS er,
         (
            SELECT COALESCE( SUM( num_stories ), 0  ) AS solr_stories
            FROM solr_imports WHERE import_date > now() - interval '1 day'
         ) AS si;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4549;

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

