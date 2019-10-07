--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4677 and 4678.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4677, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4678, import this SQL file:
--
--     psql mediacloud < mediawords-4677-4678.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- To be recreated later
DROP VIEW media_with_collections;
DROP VIEW media_with_media_types;

DROP INDEX media_moderated;

ALTER TABLE media
    DROP COLUMN moderated,
    DROP COLUMN moderation_notes;

ALTER TABLE snap.media
    DROP COLUMN moderated,
    DROP COLUMN moderation_notes;

CREATE VIEW media_with_collections AS
    SELECT t.tag,
           m.media_id,
           m.url,
           m.name,
           m.full_text_rss
    FROM media m,
         tags t,
         tag_sets ts,
         media_tags_map mtm
    WHERE ts.name::text = 'collection'::text
      AND ts.tag_sets_id = t.tag_sets_id
      AND mtm.tags_id = t.tags_id
      AND mtm.media_id = m.media_id
    ORDER BY m.media_id;

create view media_with_media_types as
    select m.*, mtm.tags_id media_type_tags_id, t.label media_type
    from
        media m
        left join (
            tags t
            join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id and ts.name = 'media_type' )
            join media_tags_map mtm on ( mtm.tags_id = t.tags_id )
        ) on ( m.media_id = mtm.media_id );


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4678;

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

