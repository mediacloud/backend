--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4481 and 4482.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4481, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4482, import this SQL file:
--
--     psql mediacloud < mediawords-4481-4482.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4482;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION insert_ss_media_stats() returns trigger as $$
begin


    IF NOT story_triggers_enabled() THEN
      RETURN NULL;
    END IF;

    update media_stats set num_sentences = num_sentences + 1
        where media_id = NEW.media_id and stat_date = date_trunc( 'day', NEW.publish_date );

    return NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_ss_media_stats() returns trigger as $$
declare
    new_date date;
    old_date date;
begin

    IF NOT story_triggers_enabled() THEN
       RETURN NULL;
    END IF;
    
    select date_trunc( 'day', NEW.publish_date ) into new_date;
    select date_trunc( 'day', OLD.publish_date ) into old_date;
    
    IF ( new_date <> old_date ) THEN
        update media_stats set num_sentences = num_sentences - 1
            where media_id = NEW.media_id and stat_date = old_date;
        update media_stats set num_sentences = num_sentences + 1
            where media_id = NEW.media_id and stat_date = new_date;
    END IF;

    return NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION delete_ss_media_stats() returns trigger as $$
begin

    IF NOT story_triggers_enabled() THEN
       RETURN NULL;
    END IF;
    
    update media_stats set num_sentences = num_sentences - 1
    where media_id = OLD.media_id and stat_date = date_trunc( 'day', OLD.publish_date );

    return NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION insert_story_media_stats() returns trigger as $insert_story_media_stats$
begin

    IF NOT story_triggers_enabled() THEN
       RETURN NULL;
    END IF;
    
    insert into media_stats ( media_id, num_stories, num_sentences, stat_date )
        select NEW.media_id, 0, 0, date_trunc( 'day', NEW.publish_date )
            where not exists (
                select 1 from media_stats where media_id = NEW.media_id and stat_date = date_trunc( 'day', NEW.publish_date ) );

    update media_stats set num_stories = num_stories + 1
        where media_id = NEW.media_id and stat_date = date_trunc( 'day', NEW.publish_date );

    return NEW;
END;
$insert_story_media_stats$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_story_media_stats() returns trigger as $update_story_media_stats$
declare
    new_date date;
    old_date date;
begin

    IF NOT story_triggers_enabled() THEN
       RETURN NULL;
    END IF;
    
    select date_trunc( 'day', NEW.publish_date ) into new_date;
    select date_trunc( 'day', OLD.publish_date ) into old_date;
    
    IF ( new_date <> old_date ) THEN
        update media_stats set num_stories = num_stories - 1
            where media_id = NEW.media_id and stat_date = old_date;

        insert into media_stats ( media_id, num_stories, num_sentences, stat_date )
            select NEW.media_id, 0, 0, date_trunc( 'day', NEW.publish_date )
                where not exists (
                    select 1 from media_stats where media_id = NEW.media_id and stat_date = date_trunc( 'day', NEW.publish_date ) );

        update media_stats set num_stories = num_stories + 1
            where media_id = NEW.media_id and stat_date = new_date;
            
        update story_sentences set publish_date = new_date where stories_id = OLD.stories_id;
    END IF;

    return NEW;
END;
$update_story_media_stats$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION delete_story_media_stats() returns trigger as $delete_story_media_stats$
begin
    
    IF NOT story_triggers_enabled() THEN
       RETURN NULL;
    END IF;

    update media_stats set num_stories = num_stories - 1
    where media_id = OLD.media_id and stat_date = date_trunc( 'day', OLD.publish_date );

    return NEW;
END;
$delete_story_media_stats$ LANGUAGE plpgsql;

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

