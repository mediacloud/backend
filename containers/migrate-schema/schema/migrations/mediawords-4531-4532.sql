--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4531 and 4532.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4531, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4532, import this SQL file:
--
--     psql mediacloud < mediawords-4531-4532.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DO $$
BEGIN
    IF NOT EXISTS (

        -- No raw_downloads.object_id => downloads.downloads_id foreign key?
        SELECT 1
        FROM information_schema.table_constraints tc
            INNER JOIN information_schema.constraint_column_usage ccu
                USING (constraint_catalog, constraint_schema, constraint_name)
            INNER JOIN information_schema.key_column_usage kcu
                USING (constraint_catalog, constraint_schema, constraint_name)
        WHERE constraint_type = 'FOREIGN KEY'
          AND tc.table_name = 'raw_downloads'
          AND kcu.column_name = 'object_id'
          AND ccu.table_name = 'downloads'
          AND ccu.column_name = 'downloads_id'

    ) THEN

        -- Re-add foreign key
        ALTER TABLE raw_downloads
            ADD CONSTRAINT raw_downloads_downloads_id_fkey
            FOREIGN KEY (object_id) REFERENCES downloads(downloads_id) ON DELETE CASCADE;

    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4532;

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

