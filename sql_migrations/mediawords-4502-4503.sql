--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4502 and 4503.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4502, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4503, import this SQL file:
--
--     psql mediacloud < mediawords-4502-4503.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Dropping temporarily; will recreate afterwards
drop view media_with_media_types;

-- Dropping to recreate with a different list of columns
DROP VIEW media_with_collections;

ALTER TABLE public.media
    DROP COLUMN feeds_added;
ALTER TABLE cd.media
    DROP COLUMN feeds_added;

-- Recreating with a different list of columns
CREATE VIEW media_with_collections AS
    SELECT t.tag,
           m.media_id,
           m.url,
           m.name,
           m.moderated,
           m.moderation_notes,
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

-- Recreating temporarily dropped views
create view media_with_media_types as
    select m.*, mtm.tags_id media_type_tags_id, t.label media_type
    from
        media m
        left join (
            tags t
            join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id and ts.name = 'media_type' )
            join media_tags_map mtm on ( mtm.tags_id = t.tags_id )
        ) on ( m.media_id = mtm.media_id );


CREATE OR REPLACE FUNCTION media_has_feeds(param_media_id INT) RETURNS boolean AS $$
BEGIN

    -- Check if media exists
    IF NOT EXISTS (

        SELECT 1
        FROM media
        WHERE media_id = param_media_id

    ) THEN
        RAISE EXCEPTION 'Media % does not exist.', param_media_id;
        RETURN FALSE;
    END IF;

    -- Check if media has feeds
    IF EXISTS (

        SELECT 1
        FROM feeds
        WHERE media_id = param_media_id

    ) THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
    
END;
$$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4503;
    
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

