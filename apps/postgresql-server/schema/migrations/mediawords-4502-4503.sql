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


CREATE TABLE extra_corenlp_stories (
	extra_corenlp_stories_id SERIAL  PRIMARY KEY,
	stories_id INTEGER NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE
);
CREATE INDEX extra_corenlp_stories_stories_id ON extra_corenlp_stories (stories_id);


--
-- Returns true if the story can + should be annotated with CoreNLP
--
CREATE OR REPLACE FUNCTION story_is_annotatable_with_corenlp(corenlp_stories_id INT) RETURNS boolean AS $$
BEGIN

    -- FIXME this function is not really optimized for performance

    -- Check "media.annotate_with_corenlp" and "extra_corenlp_stories"
    IF NOT EXISTS (

        SELECT 1
        FROM stories
            INNER JOIN media ON stories.media_id = media.media_id
        WHERE stories.stories_id = corenlp_stories_id
          AND media.annotate_with_corenlp = 't'

    ) AND NOT EXISTS (

        SELECT 1
        FROM extra_corenlp_stories
        WHERE extra_corenlp_stories.stories_id = corenlp_stories_id

    ) THEN
        RAISE NOTICE 'Story % is not annotatable with CoreNLP because it is not enabled for annotation.', corenlp_stories_id;
        RETURN FALSE;

    -- Check if the story is extracted
    ELSEIF EXISTS (

        SELECT 1
        FROM downloads
        WHERE stories_id = corenlp_stories_id
          AND type = 'content'
          AND extracted = 'f'

    ) THEN
        RAISE NOTICE 'Story % is not annotatable with CoreNLP because it is not extracted.', corenlp_stories_id;
        RETURN FALSE;

    -- Annotate English language stories only because they're the only ones
    -- supported by CoreNLP at the time.
    ELSEIF NOT EXISTS (

        SELECT 1
        FROM stories
        WHERE stories_id = corenlp_stories_id

        -- Stories with language field set to NULL are the ones fetched before
        -- introduction of the multilanguage support, so they are assumed to be
        -- English.
          AND ( stories.language = 'en' OR stories.language IS NULL )

    ) THEN
        RAISE NOTICE 'Story % is not annotatable with CoreNLP because it is not in English.', corenlp_stories_id;
        RETURN FALSE;

    -- Check if story has sentences
    ELSEIF NOT EXISTS (

        SELECT 1
        FROM story_sentences
        WHERE stories_id = corenlp_stories_id

    ) THEN
        RAISE NOTICE 'Story % is not annotatable with CoreNLP because it has no sentences.', corenlp_stories_id;
        RETURN FALSE;

    -- Things are fine
    ELSE
        RETURN TRUE;

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

