--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4594 and 4595.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4594, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4595, import this SQL file:
--
--     psql mediacloud < mediawords-4594-4595.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- ALTER TYPE ... ADD VALUE doesn't work in a transaction or a multi-line
-- query, so the new enum value gets added in Schema.pm manually.

--ALTER TYPE feed_feed_type ADD VALUE 'superglue';


--- Superglue (TV) stories metadata -->
CREATE TABLE stories_superglue_metadata (
    stories_superglue_metadata_id   SERIAL    PRIMARY KEY,
    stories_id                      INT       NOT NULL REFERENCES stories ON DELETE CASCADE,
    thumbnail_url                   VARCHAR   NOT NULL,
    segment_duration                NUMERIC   NOT NULL
);

CREATE UNIQUE INDEX stories_superglue_metadata_stories_id
    ON stories_superglue_metadata (stories_id);


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4595;

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

