--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4702 and 4703.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4702, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4703, import this SQL file:
--
--     psql mediacloud < mediawords-4702-4703.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- ALTER TABLE raw_downloads ADD column might have worked too, but the table is
-- empty in production or very small in development environments, so to
-- preserve the column order let's just recreate everything


-- Rename "raw_downloads" to "raw_downloads_int"
ALTER TABLE raw_downloads
    RENAME TO raw_downloads_int;
ALTER SEQUENCE raw_downloads_raw_downloads_id_seq
    RENAME TO raw_downloads_int_raw_downloads_id_seq;
ALTER INDEX raw_downloads_pkey
    RENAME TO raw_downloads_int_pkey;
ALTER INDEX raw_downloads_object_id
    RENAME TO raw_downloads_int_object_id;
ALTER TRIGGER raw_downloads_test_referenced_download_trigger
    ON raw_downloads_int
    RENAME TO raw_downloads_int_test_referenced_download_trigger;

-- Create "raw_downloads" with a BIGINT "object_id"
CREATE TABLE raw_downloads (
    raw_downloads_id    BIGSERIAL   PRIMARY KEY,

    -- "downloads_id" from "downloads"
    object_id           BIGINT      NOT NULL,

    raw_data            BYTEA       NOT NULL
);
CREATE UNIQUE INDEX raw_downloads_object_id
    ON raw_downloads (object_id);
ALTER TABLE raw_downloads
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;
CREATE TRIGGER raw_downloads_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON raw_downloads
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('object_id');

-- Copy the data
INSERT INTO raw_downloads (object_id, raw_data)
    SELECT object_id::bigint, raw_data
    FROM raw_downloads_int;

-- Drop old table
DROP TABLE raw_downloads_int;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4703;
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
