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
ALTER TYPE download_type
    RENAME TO download_type_before_removing_spider;
CREATE TYPE download_type AS ENUM ('Calais', 'calais', 'content', 'feed');
ALTER TABLE downloads
    ALTER COLUMN type TYPE download_type USING type::text::download_type;
DROP TYPE download_type_before_removing_spider;


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

