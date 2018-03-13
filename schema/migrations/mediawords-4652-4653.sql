--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4652 and 4653.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4652, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4653, import this SQL file:
--
--     psql mediacloud < mediawords-4652-4653.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


--
-- Snapshot word2vec models
--
CREATE TABLE snap.word2vec_models (
    word2vec_models_id  SERIAL      PRIMARY KEY,
    object_id           INTEGER     NOT NULL REFERENCES snapshots (snapshots_id) ON DELETE CASCADE,
    creation_date       TIMESTAMP   NOT NULL DEFAULT NOW()
);

-- We'll need to find the latest word2vec model
CREATE INDEX snap_word2vec_models_object_id_creation_date ON snap.word2vec_models (object_id, creation_date);

CREATE TABLE snap.word2vec_models_data (
    word2vec_models_data_id SERIAL      PRIMARY KEY,
    object_id               INTEGER     NOT NULL
                                            REFERENCES snap.word2vec_models (word2vec_models_id)
                                            ON DELETE CASCADE,
    raw_data                BYTEA       NOT NULL
);
CREATE UNIQUE INDEX snap_word2vec_models_data_object_id ON snap.word2vec_models_data (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE snap.word2vec_models_data
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4653;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
