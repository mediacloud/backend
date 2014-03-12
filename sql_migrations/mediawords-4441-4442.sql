--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4441 and 4442.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4441, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4442, import this SQL file:
--
--     psql mediacloud < mediawords-4441-4442.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

CREATE TABLE story_sentences_tags_map (
	story_sentences_tags_map_id bigserial  primary key,
	story_sentences_id bigint     not null references story_sentences on delete cascade,
	tags_id int     not null references tags on delete cascade,
	db_row_last_updated timestamp with time zone NOT NULL
);

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4442;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE INDEX story_sentences_tags_map_db_row_last_updated ON story_sentences_tags_map ( db_row_last_updated );

CREATE UNIQUE INDEX story_sentences_tags_map_story ON story_sentences_tags_map (story_sentences_id, tags_id);

CREATE INDEX story_sentences_tags_map_tag ON story_sentences_tags_map (tags_id);

CREATE INDEX story_sentences_tags_map_story_id ON story_sentences_tags_map USING btree (story_sentences_id);

CREATE TRIGGER story_sentences_tags_map_last_updated_trigger
	BEFORE INSERT OR UPDATE ON story_sentences_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger() ;

CREATE TRIGGER story_sentences_tags_map_update_story_sentences_last_updated_trigger
	AFTER INSERT OR UPDATE OR DELETE ON story_sentences_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE update_stories_updated_time_by_stories_id_trigger();

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

