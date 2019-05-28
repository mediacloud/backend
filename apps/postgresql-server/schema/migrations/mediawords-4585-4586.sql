--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4585 and 4586.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4585, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4586, import this SQL file:
--
--     psql mediacloud < mediawords-4585-4586.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

DROP VIEW media_with_media_types;   -- will recreate right afterwards

ALTER TABLE media
    DROP COLUMN use_pager,
    DROP COLUMN unpaged_stories;

CREATE VIEW media_with_media_types AS
    SELECT m.*, mtm.tags_id media_type_tags_id, t.label media_type
    FROM
        media m
        LEFT JOIN (
            tags t
            JOIN tag_sets ts ON ( ts.tag_sets_id = t.tag_sets_id AND ts.name = 'media_type' )
            JOIN media_tags_map mtm ON ( mtm.tags_id = t.tags_id )
        ) ON ( m.media_id = mtm.media_id );


SET search_path = snap, pg_catalog;

ALTER TABLE media
    DROP COLUMN use_pager,
    DROP COLUMN unpaged_stories;


SET search_path = public, pg_catalog;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4586;

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

