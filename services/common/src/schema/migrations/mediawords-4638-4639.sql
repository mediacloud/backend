--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4638 and 4639.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4638, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4639, import this SQL file:
--
--     psql mediacloud < mediawords-4638-4639.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Will recreate later
DROP VIEW IF EXISTS daily_stats;
DROP VIEW IF EXISTS stories_collected_in_past_day;


CREATE OR REPLACE FUNCTION last_updated_trigger() RETURNS trigger AS $$

DECLARE
    path_change boolean;

BEGIN
    IF (TG_OP = 'UPDATE') OR (TG_OP = 'INSERT') then
        NEW.db_row_last_updated = NOW();
    END IF;

    RETURN NEW;
END;

$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_trigger() RETURNS trigger AS $$

DECLARE
    path_change boolean;

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
    path_change boolean;
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

CREATE OR REPLACE FUNCTION insert_ss_media_stats() RETURNS trigger AS $$
BEGIN

    UPDATE media_stats
    SET num_sentences = num_sentences + 1
    WHERE media_id = NEW.media_id
      AND stat_date = date_trunc( 'day', NEW.publish_date );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_ss_media_stats() RETURNS trigger AS $$

DECLARE
    new_date DATE;
    old_date DATE;

BEGIN
    SELECT date_trunc( 'day', NEW.publish_date ) INTO new_date;
    SELECT date_trunc( 'day', OLD.publish_date ) INTO old_date;

    IF ( new_date != old_date ) THEN

        UPDATE media_stats
        SET num_sentences = num_sentences - 1
        WHERE media_id = NEW.media_id
          AND stat_date = old_date;

        UPDATE media_stats
        SET num_sentences = num_sentences + 1
        WHERE media_id = NEW.media_id
          AND stat_date = new_date;

    END IF;

    RETURN NEW;
END;

$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION delete_ss_media_stats() RETURNS trigger AS $$
BEGIN

    UPDATE media_stats
    SET num_sentences = num_sentences - 1
    WHERE media_id = OLD.media_id
      AND stat_date = date_trunc( 'day', OLD.publish_date );

    RETURN NEW;

END;

$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION insert_story_media_stats() RETURNS trigger AS $$
BEGIN

    INSERT INTO media_stats ( media_id, num_stories, num_sentences, stat_date )
        SELECT NEW.media_id, 0, 0, date_trunc( 'day', NEW.publish_date )
        WHERE NOT EXISTS (
            SELECT 1
            FROM media_stats
            WHERE media_id = NEW.media_id
              AND stat_date = date_trunc( 'day', NEW.publish_date )
        );

    UPDATE media_stats
    SET num_stories = num_stories + 1
    WHERE media_id = NEW.media_id
      AND stat_date = date_trunc( 'day', NEW.publish_date );

    RETURN NEW;

END;

$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_story_media_stats() RETURNS trigger AS $$

DECLARE
    new_date DATE;
    old_date DATE;

BEGIN

    SELECT date_trunc( 'day', NEW.publish_date ) INTO new_date;
    SELECT date_trunc( 'day', OLD.publish_date ) INTO old_date;

    IF ( new_date != old_date ) THEN

        UPDATE media_stats
        SET num_stories = num_stories - 1
        WHERE media_id = NEW.media_id
          AND stat_date = old_date;

        INSERT INTO media_stats ( media_id, num_stories, num_sentences, stat_date )
            SELECT NEW.media_id, 0, 0, date_trunc( 'day', NEW.publish_date )
            WHERE NOT EXISTS (
                SELECT 1
                FROM media_stats
                WHERE media_id = NEW.media_id
                  AND stat_date = date_trunc( 'day', NEW.publish_date )
            );

        UPDATE media_stats
        SET num_stories = num_stories + 1
        WHERE media_id = NEW.media_id
          AND stat_date = new_date;

        UPDATE story_sentences
        SET publish_date = new_date
        WHERE stories_id = OLD.stories_id;

    END IF;

    RETURN NEW;
END;

$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION delete_story_media_stats() RETURNS trigger AS $$
BEGIN

    UPDATE media_stats
    SET num_stories = num_stories - 1
    WHERE media_id = OLD.media_id
      AND stat_date = date_trunc( 'day', OLD.publish_date );

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


DROP FUNCTION story_triggers_enabled();

DROP FUNCTION enable_story_triggers();

DROP FUNCTION disable_story_triggers();

-- Not used
DROP FUNCTION update_story_sentences_updated_time_by_story_sentences_id_trigger();


ALTER TABLE stories
	DROP COLUMN disable_triggers;

ALTER TABLE story_sentences
	DROP COLUMN disable_triggers;

ALTER TABLE processed_stories
	DROP COLUMN disable_triggers;


-- Recreate views
CREATE VIEW stories_collected_in_past_day AS
    SELECT *
    FROM stories
    WHERE collect_date > now() - interval '1 day';

CREATE VIEW daily_stats AS
    SELECT *
    FROM (
            SELECT COUNT(*) AS daily_downloads
            FROM downloads_in_past_day
         ) AS dd,
         (
            SELECT COUNT(*) AS daily_stories
            FROM stories_collected_in_past_day
         ) AS ds,
         (
            SELECT COUNT(*) AS downloads_to_be_extracted
            FROM downloads_to_be_extracted
         ) AS dex,
         (
            SELECT COUNT(*) AS download_errors
            FROM downloads_with_error_in_past_day
         ) AS er,
         (
            SELECT COALESCE( SUM( num_stories ), 0  ) AS solr_stories
            FROM solr_imports WHERE import_date > now() - interval '1 day'
         ) AS si;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4639;

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

