--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4661 and 4662.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4661, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4662, import this SQL file:
--
--     psql mediacloud < mediawords-4661-4662.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Kill all autovacuums before proceeding with DDL changes
SELECT pid
FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
WHERE backend_type = 'autovacuum worker';


DROP TRIGGER stories_last_updated_trigger ON stories;
DROP TRIGGER stories_update_story_sentences_last_updated_trigger ON stories;
DROP TRIGGER story_sentences_last_updated_trigger ON story_sentences;


CREATE OR REPLACE FUNCTION last_updated_trigger() RETURNS trigger AS $$

BEGIN
    NEW.db_row_last_updated = NOW();
    RETURN NEW;
END;

$$ LANGUAGE 'plpgsql';


CREATE TRIGGER stories_last_updated_trigger
	BEFORE INSERT OR UPDATE ON stories
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger();

CREATE TRIGGER stories_update_story_sentences_last_updated_trigger
	AFTER INSERT OR UPDATE ON stories
	FOR EACH ROW
	EXECUTE PROCEDURE update_story_sentences_updated_time_trigger();

CREATE TRIGGER story_sentences_last_updated_trigger
	BEFORE INSERT OR UPDATE ON story_sentences
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger();


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4662;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();

