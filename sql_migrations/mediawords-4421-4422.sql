--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4421 and 4422.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4421, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4422, import this SQL file:
--
--     psql mediacloud < mediawords-4421-4422.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

ALTER TABLE media_edits
	ADD COLUMN media_id INT         NOT NULL REFERENCES media(media_id)
                                    
                                    ON DELETE NO ACTION ON UPDATE NO ACTION DEFERRABLE;

CREATE INDEX media_edits_media_id ON media_edits (media_id);
CREATE INDEX media_edits_edited_field ON media_edits (edited_field);
CREATE INDEX media_edits_users_email ON media_edits (users_email);
CREATE INDEX story_edits_stories_id ON story_edits (stories_id);
CREATE INDEX story_edits_edited_field ON story_edits (edited_field);
CREATE INDEX story_edits_users_email ON story_edits (users_email);


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4422;
    
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

