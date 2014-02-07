--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4420 and 4421.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4420, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4421, import this SQL file:
--
--     psql mediacloud < mediawords-4420-4421.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

ALTER TABLE story_sentences
	ADD COLUMN last_updated timestamp with time zone NOT NULL DEFAULT now();

ALTER TABLE story_sentences
        ALTER COLUMN last_updated DROP DEFAULT;

CREATE OR REPLACE FUNCTION story_sentences_last_updated_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';                                                                                                                            

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') then

      	 NEW.last_updated = now();
      ELSE
               -- RAISE NOTICE 'NO path change % = %', OLD.path, NEW.path;                                                                                  
      END IF;

      RETURN NEW;
   END;
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER story_sentences_last_updated_trigger
	BEFORE INSERT OR UPDATE ON story_sentences
	FOR EACH ROW
	EXECUTE PROCEDURE story_sentences_last_updated_trigger() ;

create table controversy_ignore_redirects (
    controversy_ignore_redirects_id     serial primary key,
    url                                 varchar( 1024 )
);

create index controversy_ignore_redirects_url on controversy_ignore_redirects ( url );


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4421;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
