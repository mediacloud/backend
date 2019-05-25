--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4662 and 4663.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4662, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4663, import this SQL file:
--
--     psql mediacloud < mediawords-4662-4663.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Update "db_row_last_updated" column to trigger Solr (re)imports for given
-- row; no update gets done if "db_row_last_updated" is set explicitly in
-- INSERT / UPDATE (e.g. when copying between tables)
CREATE OR REPLACE FUNCTION last_updated_trigger() RETURNS trigger AS $$

BEGIN

    IF TG_OP = 'INSERT' THEN
        IF NEW.db_row_last_updated IS NULL THEN
            NEW.db_row_last_updated = NOW();
        END IF;

    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.db_row_last_updated = OLD.db_row_last_updated THEN
            NEW.db_row_last_updated = NOW();
        END IF;
    END IF;

    RETURN NEW;

END;

$$ LANGUAGE 'plpgsql';


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4663;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
