--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4493 and 4494.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4493, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4494, import this SQL file:
--
--     psql mediacloud < mediawords-4493-4494.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


--
-- CoreNLP annotations
--
CREATE TABLE corenlp_annotations (
    corenlp_annotations_id  SERIAL    PRIMARY KEY,
    object_id               INTEGER   NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    raw_data                BYTEA     NOT NULL
);
CREATE UNIQUE INDEX corenlp_annotations_object_id ON corenlp_annotations (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE corenlp_annotations
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;


--
-- Bit.ly processing results
--
CREATE TABLE bitly_processing_results (
    bitly_processing_results_id   SERIAL    PRIMARY KEY,
    object_id                     INTEGER   NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    raw_data                      BYTEA     NOT NULL
);
CREATE UNIQUE INDEX bitly_processing_results_object_id ON bitly_processing_results (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE bitly_processing_results
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;



CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4494;
    
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

