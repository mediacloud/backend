--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4524 and 4525.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4524, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4525, import this SQL file:
--
--     psql mediacloud < mediawords-4524-4525.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


CREATE OR REPLACE FUNCTION update_live_story() returns trigger as $update_live_story$
    begin

        IF NOT story_triggers_enabled() then
	  RETURN NEW;
        END IF;

        update cd.live_stories set
                media_id = NEW.media_id,
                url = NEW.url,
                guid = NEW.guid,
                title = NEW.title,
                description = NEW.description,
                publish_date = NEW.publish_date,
                collect_date = NEW.collect_date,
                full_text_rss = NEW.full_text_rss,
                language = NEW.language,
                db_row_last_updated = NEW.db_row_last_updated,
                ap_syndicated = (
                    SELECT ap_syndicated
                    FROM stories
                    WHERE stories_id = NEW.stories_id
                )
            where
                stories_id = NEW.stories_id;

        return NEW;
    END;
$update_live_story$ LANGUAGE plpgsql;


--
-- 2 of 2. Reset the database version.
--
CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4525;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
