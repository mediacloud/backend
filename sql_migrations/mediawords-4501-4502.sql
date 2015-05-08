--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4501 and 4502.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4501, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4502, import this SQL file:
--
--     psql mediacloud < mediawords-4501-4502.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

ALTER TABLE media add constraint media_dup_media_id_fkey_deferrable FOREIGN KEY (dup_media_id) REFERENCES media(media_id) ON DELETE SET NULL DEFERRABLE;
ALTER table media DROP CONSTRAINT media_dup_media_id_fkey;
ALTER TABLE media add constraint media_dup_media_id_fkey FOREIGN KEY (dup_media_id) REFERENCES media(media_id) ON DELETE SET NULL DEFERRABLE;
ALTER table media DROP CONSTRAINT media_dup_media_id_fkey_deferrable;


ALTER TABLE media
	ALTER COLUMN dup_media_id TYPE int             null references media on delete set null deferrable /* TYPE change - table: media original: int             null references media on delete set new: int             null references media on delete set null deferrable */;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4502;
    
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

