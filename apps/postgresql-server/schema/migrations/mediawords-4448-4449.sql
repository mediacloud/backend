--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4448 and 4449.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4448, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4449, import this SQL file:
--
--     psql mediacloud < mediawords-4448-4449.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


CREATE OR REPLACE FUNCTION story_is_annotatable_with_corenlp(corenlp_stories_id INT) RETURNS boolean AS $$
BEGIN

    IF EXISTS (

        SELECT 1
        FROM stories
            INNER JOIN media ON stories.media_id = media.media_id
        WHERE stories.stories_id = corenlp_stories_id

          -- We don't check if the story has been extracted here because the
          -- CoreNLP worker might get to it sooner than the extractor (i.e. the
          -- extractor might not be fast enough to set extracted = 't' before
          -- CoreNLP annotation begins)

          -- Media is marked for CoreNLP annotation
          AND media.annotate_with_corenlp = 't'

          -- English language stories only because they're the only ones
          -- supported by CoreNLP at the time.
          -- Stories with language field set to NULL are the ones fetched
          -- before introduction of the multilanguage support, so they are
          -- assumed to be in English
          AND (stories.language = 'en' OR stories.language IS NULL)

          -- Story not yet marked as "processed"
          AND NOT EXISTS (
            SELECT 1
            FROM processed_stories
            WHERE stories.stories_id = processed_stories.stories_id
          )

    ) THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
    
END;
$$
LANGUAGE 'plpgsql';


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4449;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
