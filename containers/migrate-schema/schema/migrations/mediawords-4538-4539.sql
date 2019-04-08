--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4538 and 4539.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4538, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4539, import this SQL file:
--
--     psql mediacloud < mediawords-4538-4539.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

CREATE OR REPLACE FUNCTION update_media_last_updated () RETURNS trigger AS
$$
   DECLARE
   BEGIN

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
      	 update media set db_row_last_updated = now()
             where media_id = NEW.media_id;
      END IF;

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
      	 update media set db_row_last_updated = now()
              where media_id = OLD.media_id;
      END IF;

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
        RETURN NEW;
      ELSE
        RETURN OLD;
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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4539;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
