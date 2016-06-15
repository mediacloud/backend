--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4523 and 4524.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4523, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4524, import this SQL file:
--
--     psql mediacloud < mediawords-4523-4524.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table cd.live_stories add ap_syndicated boolean null;

create or replace function insert_live_story() returns trigger as $insert_live_story$
    begin

        insert into cd.live_stories
            ( controversies_id, controversy_stories_id, stories_id, media_id, url, guid, title, description,
                publish_date, collect_date, full_text_rss, language,
                db_row_last_updated, ap_syndicated )
            select NEW.controversies_id, NEW.controversy_stories_id, NEW.stories_id, s.media_id, s.url, s.guid,
                    s.title, s.description, s.publish_date, s.collect_date, s.full_text_rss, s.language,
                    s.db_row_last_updated, s.ap_syndicated
                from controversy_stories cs
                    join stories s on ( cs.stories_id = s.stories_id )
                where
                    cs.stories_id = NEW.stories_id and
                    cs.controversies_id = NEW.controversies_id;

        return NEW;
    END;
$insert_live_story$ LANGUAGE plpgsql;

create or replace function update_live_story() returns trigger as $update_live_story$
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
                ap_syndicated = NEW.ap_syndicated
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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4524;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
