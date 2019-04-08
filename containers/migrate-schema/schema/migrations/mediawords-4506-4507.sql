--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4506 and 4507.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4506, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4507, import this SQL file:
--
--     psql mediacloud < mediawords-4506-4507.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Dropping temporarily; will recreate afterwards
drop view media_with_media_types;

-- Dropping to recreate with a different list of columns
DROP VIEW media_with_collections;

ALTER TABLE public.media
    DROP COLUMN feeds_added;
ALTER TABLE cd.media
    DROP COLUMN feeds_added;

-- Recreating with a different list of columns
CREATE VIEW media_with_collections AS
    SELECT t.tag,
           m.media_id,
           m.url,
           m.name,
           m.moderated,
           m.moderation_notes,
           m.full_text_rss
    FROM media m,
         tags t,
         tag_sets ts,
         media_tags_map mtm
    WHERE ts.name::text = 'collection'::text
      AND ts.tag_sets_id = t.tag_sets_id
      AND mtm.tags_id = t.tags_id
      AND mtm.media_id = m.media_id
    ORDER BY m.media_id;

-- Recreating temporarily dropped views
create view media_with_media_types as
    select m.*, mtm.tags_id media_type_tags_id, t.label media_type
    from
        media m
        left join (
            tags t
            join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id and ts.name = 'media_type' )
            join media_tags_map mtm on ( mtm.tags_id = t.tags_id )
        ) on ( m.media_id = mtm.media_id );


CREATE OR REPLACE FUNCTION media_has_active_syndicated_feeds(param_media_id INT) RETURNS boolean AS $$
BEGIN

    -- Check if media exists
    IF NOT EXISTS (

        SELECT 1
        FROM media
        WHERE media_id = param_media_id

    ) THEN
        RAISE EXCEPTION 'Media % does not exist.', param_media_id;
        RETURN FALSE;
    END IF;

    -- Check if media has feeds
    IF EXISTS (

        SELECT 1
        FROM feeds
        WHERE media_id = param_media_id
          AND feed_status = 'active'

          -- Website might introduce RSS feeds later
          AND feed_type = 'syndicated'

    ) THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
    
END;
$$
LANGUAGE 'plpgsql';


-- Media feed rescraping state
CREATE TABLE media_rescraping (
    media_id            int                       NOT NULL UNIQUE REFERENCES media ON DELETE CASCADE,

    -- Disable periodic rescraping?
    disable             BOOLEAN                   NOT NULL DEFAULT 'f',

    -- Timestamp of last rescrape; NULL means that media was never scraped at all
    last_rescrape_time  TIMESTAMP WITH TIME ZONE  NULL
);

CREATE UNIQUE INDEX media_rescraping_media_id on media_rescraping(media_id);
CREATE INDEX media_rescraping_last_rescrape_time on media_rescraping(last_rescrape_time);

-- Insert new rows to "media_rescraping" for each new row in "media"
CREATE OR REPLACE FUNCTION media_rescraping_add_initial_state_trigger() RETURNS trigger AS
$$
    BEGIN
        INSERT INTO media_rescraping (media_id, disable, last_rescrape_time)
        VALUES (NEW.media_id, 'f', NULL);
        RETURN NEW;
   END;
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER media_rescraping_add_initial_state_trigger
    AFTER INSERT ON media
    FOR EACH ROW EXECUTE PROCEDURE media_rescraping_add_initial_state_trigger();


-- Set the initial rescraping state for all existing media types
INSERT INTO media_rescraping (media_id, disable, last_rescrape_time)
    SELECT media_id,
           'f',
           -- Span across 1 year so that all media doesn't get rescraped at the same time
           (NOW() - RANDOM() * (NOW() - (NOW() - INTERVAL '1 year')))
    FROM media
    WHERE NOT EXISTS (
        SELECT 1
        FROM media_rescraping
        WHERE media_rescraping.media_id = media.media_id
    );


-- Feeds for media item that were found after (re)scraping
CREATE TABLE feeds_after_rescraping (
    feeds_after_rescraping_id   SERIAL          PRIMARY KEY,
    media_id                    INT             NOT NULL REFERENCES media ON DELETE CASCADE,
    name                        VARCHAR(512)    NOT NULL,
    url                         VARCHAR(1024)   NOT NULL,
    feed_type                   feed_feed_type  NOT NULL DEFAULT 'syndicated'
);
CREATE INDEX feeds_after_rescraping_media_id ON feeds_after_rescraping(media_id);
CREATE INDEX feeds_after_rescraping_name ON feeds_after_rescraping(name);
CREATE UNIQUE INDEX feeds_after_rescraping_url ON feeds_after_rescraping(url, media_id);


-- Feed is "stale" (hasn't provided a new story in some time)
-- Not to be confused with "stale feeds" in extractor!
CREATE OR REPLACE FUNCTION feed_is_stale(param_feeds_id INT) RETURNS boolean AS $$
BEGIN

    -- Check if feed exists at all
    IF NOT EXISTS (
        SELECT 1
        FROM feeds
        WHERE feeds.feeds_id = param_feeds_id
    ) THEN
        RAISE EXCEPTION 'Feed % does not exist.', param_feeds_id;
        RETURN FALSE;
    END IF;

    -- Check if feed is active
    IF EXISTS (
        SELECT 1
        FROM feeds
        WHERE feeds.feeds_id = param_feeds_id
          AND (
              feeds.last_new_story_time IS NULL
           OR feeds.last_new_story_time < NOW() - INTERVAL '6 months'
          )
    ) THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;

END;
$$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4507;
    
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
