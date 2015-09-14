--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4423 and 4424.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4423, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4424, import this SQL file:
--
--     psql mediacloud < mediawords-4423-4424.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

CREATE OR REPLACE FUNCTION last_updated_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') then

      	 NEW.db_row_last_updated = now();

      END IF;

      RETURN NEW;
   END;
$$
LANGUAGE 'plpgsql';

ALTER TABLE media_tags_map
	ADD COLUMN db_row_last_updated timestamp with time zone default now();

ALTER TABLE media_tags_map
	ALTER COLUMN db_row_last_updated SET NOT NULL;

create index media_tags_map_db_row_last_updated on media_tags_map ( db_row_last_updated );

ALTER TABLE stories_tags_map
	ADD COLUMN db_row_last_updated timestamp with time zone default now();

ALTER TABLE stories_tags_map
	ALTER COLUMN db_row_last_updated SET NOT NULL;

CREATE TRIGGER media_tags_last_updated_trigger
	BEFORE INSERT OR UPDATE ON media_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger() ;

CREATE TRIGGER stories_tags_map_last_updated_trigger
	BEFORE INSERT OR UPDATE ON stories_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger() ;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4424;

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
