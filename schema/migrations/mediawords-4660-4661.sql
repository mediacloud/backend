--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4660 and 4661.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4660, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4661, import this SQL file:
--
--     psql mediacloud < mediawords-4660-4661.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


CREATE OR REPLACE FUNCTION last_updated_trigger() RETURNS trigger AS $$

BEGIN
    IF (TG_OP = 'UPDATE') OR (TG_OP = 'INSERT') then
        NEW.db_row_last_updated = NOW();
    END IF;

    RETURN NEW;
END;

$$ LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_trigger() RETURNS trigger AS $$

BEGIN
    UPDATE story_sentences
    SET db_row_last_updated = NOW()
    WHERE stories_id = NEW.stories_id
      AND before_last_solr_import( db_row_last_updated );

    RETURN NULL;
END;

$$ LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION update_stories_updated_time_by_stories_id_trigger() RETURNS trigger AS $$

DECLARE
    reference_stories_id integer default null;

BEGIN

    IF TG_OP = 'INSERT' THEN
        -- The "old" record doesn't exist
        reference_stories_id = NEW.stories_id;
    ELSIF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
        reference_stories_id = OLD.stories_id;
    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;
    END IF;

    UPDATE stories
    SET db_row_last_updated = now()
    WHERE stories_id = reference_stories_id
      AND before_last_solr_import( db_row_last_updated );

    RETURN NULL;

END;

$$ LANGUAGE 'plpgsql';


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4661;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
