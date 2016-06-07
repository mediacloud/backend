--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4543 and 4544.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4543, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4544, import this SQL file:
--
--     psql mediacloud < mediawords-4543-4544.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Will recreate afterwards
DROP VIEW media_with_media_types;


DROP FUNCTION IF EXISTS purge_story_sentences(date, date);

DROP FUNCTION IF EXISTS media_set_sw_data_retention_dates(int, date, date);

DROP FUNCTION media_set_retains_sw_data_for_date(int, date, date, date);

DROP VIEW media_sets_explict_sw_data_dates;


SET search_path = cd, pg_catalog;
ALTER TABLE media
    DROP COLUMN sw_data_start_date,
    DROP COLUMN sw_data_end_date;


SET search_path = public, pg_catalog;
ALTER TABLE media
	DROP COLUMN sw_data_start_date,
	DROP COLUMN sw_data_end_date;


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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4544;

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

