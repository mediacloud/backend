-- noinspection SqlResolveForFile @ routine/"create_distributed_table"

-- FIXME connection count limit:
--  https://docs.citusdata.com/en/v10.0/admin_guide/cluster_management.html#real-time-analytics-use-case
-- FIXME un-TOAST some columns
-- FIXME update sequences to continue on from where we left off
-- FIXME move related things together
-- FIXME write down somewhere that triggers have to be recreated on newly added workers
-- FIXME when initializing schema, some connections get dropped
-- FIXME consider making shard count configurable to make tests run faster
-- FIXME schema and tables get created as "postgres" user, should be "mediacloud"
-- FIXME enable slow query log in PostgreSQL
-- FIXME make processed_stories_stories_id index unique
-- FIXME make solr_import_stories_stories_id index unique
-- FIXME updatable views should call triggers on both old and new tables, plus
--     keep source tables read-only
-- FIXME cast enums to TEXT, then to another enum
-- FIXME copy all reference tables in a migration
-- FIXME temporarily drop indexes while moving rows
-- FIXME move very small tables in a migration


-- Rename the unsharded schema created in previous migrations
ALTER SCHEMA public RENAME TO unsharded_public;
ALTER SCHEMA public_store RENAME TO unsharded_public_store;
ALTER SCHEMA snap RENAME TO unsharded_snap;
ALTER SCHEMA cache RENAME TO unsharded_cache;


-- Recreate "public" (and later other schemas) with the sharded layout
CREATE SCHEMA public;

SET search_path = public, pg_catalog;

CREATE OR REPLACE LANGUAGE plpgsql;


-- noinspection SqlResolve @ extension/"pg_trgm"
ALTER EXTENSION pg_trgm SET SCHEMA public;
-- noinspection SqlResolve @ extension/"pgcrypto"
ALTER EXTENSION pgcrypto SET SCHEMA public;
-- noinspection SqlResolve @ extension/"citext"
ALTER EXTENSION citext SET SCHEMA public;

CREATE EXTENSION citus;


-- Move pgmigrate's table
-- noinspection SqlResolve
ALTER TABLE unsharded_public.schema_version
    SET SCHEMA public;


-- Run command on all Citus shards; if command fails on one of these, raise exception
CREATE OR REPLACE FUNCTION run_on_shards_or_raise(sharded_table REGCLASS, sql_command TEXT)

-- Not SETOF RECORD like the original run_command_on_shards()
    RETURNS TABLE
            (
                shardid BIGINT, -- NOT NULL
                success BOOL,   -- NOT NULL
                result  TEXT    -- NULL
            )
AS
$$

DECLARE
    shard_result  RECORD;
    failed_shards TEXT[];

BEGIN

    -- noinspection SqlResolve @ routine/"run_command_on_shards"
    FOR shard_result IN (
        SELECT *
        FROM run_command_on_shards(sharded_table, sql_command) AS r
    )
        LOOP

            -- noinspection SqlResolve
            IF shard_result.success = 'f' THEN
                failed_shards := failed_shards ||
                                 format('shardid=%s, result=%s', shard_result.shardid::text, shard_result.result);
            END IF;

            -- noinspection SqlResolve
            shardid := shard_result.shardid;
            -- noinspection SqlResolve
            success := shard_result.success;
            -- noinspection SqlResolve
            result := shard_result.result;

            RETURN NEXT;

        END LOOP;

    IF array_length(failed_shards, 1) > 0 THEN
        RAISE EXCEPTION E'Command failed on some shards:\n* %', array_to_string(failed_shards, E'\n* ');
    END IF;

END;
$$ LANGUAGE plpgsql;


-- Database properties (variables) table
CREATE TABLE database_variables
(
    database_variables_id BIGSERIAL PRIMARY KEY,
    name                  TEXT NOT NULL,
    value                 TEXT NOT NULL
);

-- Not distributed, not reference (used to copy to from "downloads" and generally small)

CREATE UNIQUE INDEX database_variables_name ON database_variables (name);

-- This function is needed because date_trunc('week', date) is not consider immutable
-- See http://www.mentby.com/Group/pgsql-general/datetrunc-on-date-is-immutable.html
--
CREATE OR REPLACE FUNCTION week_start_date(day DATE) RETURNS DATE AS
$$
DECLARE
    date_trunc_result DATE;
BEGIN
    date_trunc_result := date_trunc('week', day::TIMESTAMP);
    RETURN date_trunc_result;
END;
$$ LANGUAGE 'plpgsql' IMMUTABLE
                      COST 10;

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('week_start_date(DATE)');


-- Returns first 64 bits (16 characters) of MD5 hash
--
-- Useful for reducing index sizes (e.g. in story_sentences.sentence) where
-- 64 bits of entropy is enough.
CREATE OR REPLACE FUNCTION half_md5(string TEXT) RETURNS BYTEA AS
$$
    -- pgcrypto's functions are being referred with public schema prefix to make pg_upgrade work
    -- noinspection SqlResolve @ routine/"digest"
SELECT SUBSTRING(public.digest(string, 'md5'::text), 0, 9);
$$ LANGUAGE SQL IMMUTABLE;

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('half_md5(TEXT)');



CREATE TABLE media
(
    media_id          BIGSERIAL PRIMARY KEY,
    url               TEXT    NOT NULL,
    normalized_url    TEXT    NULL,
    name              TEXT    NOT NULL,
    full_text_rss     BOOLEAN NULL,

    -- It indicates that the media source includes a substantial number of
    -- links in its feeds that are not its own. These media sources cause
    -- problems for the topic mapper's spider, which finds those foreign rss links and
    -- thinks that the urls belong to the parent media source.
    foreign_rss_links BOOLEAN NOT NULL DEFAULT 'f',
    dup_media_id      BIGINT  NULL REFERENCES media (media_id) ON DELETE SET NULL DEFERRABLE,
    is_not_dup        BOOLEAN NULL,

    -- Delay content downloads for this media source this many hours
    content_delay     INT     NULL,

    -- notes for internal media cloud consumption (eg. 'added this for yochai')
    editor_notes      TEXT    NULL,

    -- notes for public consumption (eg. 'leading dissident paper in antarctica')
    public_notes      TEXT    NULL,

    -- if true, indicates that media cloud closely monitors the health of this source
    is_monitored      BOOLEAN NOT NULL DEFAULT 'f',

    CONSTRAINT media_name_not_empty CHECK (LENGTH(name) > 0),
    CONSTRAINT media_self_dup CHECK (dup_media_id IS NULL OR dup_media_id != media_id)
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('media');

CREATE UNIQUE INDEX media_name ON media (name);
CREATE UNIQUE INDEX media_url ON media (url);
CREATE INDEX media_normalized_url ON media (normalized_url);
CREATE INDEX media_name_fts ON media USING GIN (to_tsvector('english', name));
CREATE INDEX media_dup_media_id ON media (dup_media_id);


-- Media feed rescraping state
CREATE TABLE media_rescraping
(
    media_rescraping_id BIGSERIAL PRIMARY KEY,

    media_id            BIGINT                   NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,

    -- Disable periodic rescraping?
    disable             BOOLEAN                  NOT NULL DEFAULT 'f',

    -- Timestamp of last rescrape; NULL means that media was never scraped at all
    last_rescrape_time  TIMESTAMP WITH TIME ZONE NULL
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('media_rescraping');

CREATE UNIQUE INDEX media_rescraping_media_id ON media_rescraping (media_id);

CREATE INDEX media_rescraping_last_rescrape_time ON media_rescraping (last_rescrape_time);



CREATE OR REPLACE FUNCTION media_rescraping_add_initial_state_trigger() RETURNS trigger AS
$$
BEGIN
    INSERT INTO media_rescraping (media_id, disable, last_rescrape_time)
    VALUES (NEW.media_id, 'f', NULL);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('media_rescraping_add_initial_state_trigger()');


-- Insert new rows to "media_rescraping" for each new row in "media"
SELECT run_on_shards_or_raise('media', $cmd$

    CREATE TRIGGER media_rescraping_add_initial_state_trigger
        AFTER INSERT
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE media_rescraping_add_initial_state_trigger();

    $cmd$);


CREATE TABLE media_stats
(
    media_stats_id BIGSERIAL NOT NULL,
    media_id       BIGINT    NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,
    num_stories    BIGINT    NOT NULL,
    num_sentences  BIGINT    NOT NULL,
    stat_date      DATE      NOT NULL,

    PRIMARY KEY (media_stats_id, media_id)
);

-- noinspection SqlResolve @ routine/"create_distributed_table"
SELECT create_distributed_table('media_stats', 'media_id');

CREATE INDEX media_stats_media_id ON media_stats (media_id);

CREATE UNIQUE INDEX media_stats_media_id_stat_date ON media_stats (media_id, stat_date);

--
-- Returns true if media has active RSS feeds
--
CREATE OR REPLACE FUNCTION media_has_active_syndicated_feeds(param_media_id BIGINT)
    RETURNS BOOLEAN AS
$$
BEGIN

    -- Check if media exists
    IF NOT EXISTS(
            SELECT 1
            FROM media
            WHERE media_id = param_media_id
        ) THEN
        RAISE EXCEPTION 'Media % does not exist.', param_media_id;
    END IF;

    -- Check if media has feeds
    IF EXISTS(
            SELECT 1
            FROM feeds
            WHERE media_id = param_media_id
              AND active = 't'

              -- Website might introduce RSS feeds later
              AND "type" = 'syndicated'
        ) THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;

END;
$$ LANGUAGE 'plpgsql';


CREATE TYPE feed_type AS ENUM (

    -- Syndicated feed, e.g. RSS or Atom
    'syndicated',

    -- Web page feed, used when no syndicated feed was found
    'web_page',

    -- Univision.com XML feed
    'univision',

    -- custom associated press api
    'ap',

    -- Podcast feed
    'podcast'

    );

CREATE TABLE feeds
(
    feeds_id                      BIGSERIAL PRIMARY KEY,
    media_id                      BIGINT                   NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,
    name                          TEXT                     NOT NULL,
    url                           TEXT                     NOT NULL,

    -- Feed type
    type                          feed_type                NOT NULL DEFAULT 'syndicated',

    -- Whether or not feed is active (should be periodically fetched for new stories)
    active                        BOOLEAN                  NOT NULL DEFAULT 't',

    -- MD5
    last_checksum                 VARCHAR(32)              NULL,

    -- Last time the feed was *attempted* to be downloaded and parsed
    -- (null -- feed was never attempted to be downloaded and parsed)
    -- (used to allow more active feeds to be downloaded more frequently)
    last_attempted_download_time  TIMESTAMP WITH TIME ZONE NULL,

    -- Last time the feed was *successfully* downloaded and parsed
    -- (null -- feed was either never attempted to be downloaded or parsed,
    -- or feed was never successfully downloaded and parsed)
    -- (used to find feeds that are broken)
    last_successful_download_time TIMESTAMP WITH TIME ZONE NULL,

    -- Last time the feed provided a new story
    -- (null -- feed has never provided any stories)
    last_new_story_time           TIMESTAMP WITH TIME ZONE NULL

);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('feeds');

CREATE INDEX feeds_media_id ON feeds (media_id);
CREATE INDEX feeds_name ON feeds (name);
CREATE UNIQUE INDEX feeds_media_id_url ON feeds (media_id, url);
CREATE INDEX feeds_last_attempted_download_time ON feeds (last_attempted_download_time);
CREATE INDEX feeds_last_successful_download_time ON feeds (last_successful_download_time);


-- Feeds for media item that were found after (re)scraping
CREATE TABLE feeds_after_rescraping
(
    feeds_after_rescraping_id BIGSERIAL PRIMARY KEY,
    media_id                  BIGINT    NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,
    name                      TEXT      NOT NULL,
    url                       TEXT      NOT NULL,
    type                      feed_type NOT NULL DEFAULT 'syndicated'
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('feeds_after_rescraping');

CREATE INDEX feeds_after_rescraping_media_id ON feeds_after_rescraping (media_id);
CREATE INDEX feeds_after_rescraping_name ON feeds_after_rescraping (name);
CREATE UNIQUE INDEX feeds_after_rescraping_media_id_url ON feeds_after_rescraping (media_id, url);


-- Feed is "stale" (hasn't provided a new story in some time)
-- Not to be confused with "stale feeds" in extractor!
CREATE OR REPLACE FUNCTION feed_is_stale(param_feeds_id BIGINT) RETURNS boolean AS
$$
BEGIN

    -- Check if feed exists at all
    IF NOT EXISTS(
            SELECT 1
            FROM feeds
            WHERE feeds.feeds_id = param_feeds_id
        ) THEN
        RAISE EXCEPTION 'Feed % does not exist.', param_feeds_id;
    END IF;

    -- Check if feed is active
    IF EXISTS(
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
$$ LANGUAGE 'plpgsql';


CREATE TABLE tag_sets
(
    tag_sets_id     BIGSERIAL PRIMARY KEY,

    --unique identifier
    name            TEXT    NOT NULL,

    -- short human readable label
    label           TEXT    NULL,

    -- longer human readable description
    description     TEXT    NULL,

    -- should public interfaces show this as an option for searching media sources
    show_on_media   BOOLEAN NULL,

    -- should public interfaces show this as an option for search stories
    show_on_stories BOOLEAN NULL,

    CONSTRAINT tag_sets_name_not_empty CHECK (LENGTH(name) > 0)
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('tag_sets');

CREATE UNIQUE INDEX tag_sets_name ON tag_sets (name);



CREATE TABLE tags
(
    tags_id         BIGSERIAL PRIMARY KEY,
    tag_sets_id     BIGINT  NOT NULL REFERENCES tag_sets (tag_sets_id) ON DELETE CASCADE,

    -- unique identifier
    tag             TEXT    NOT NULL,

    -- short human readable label
    label           TEXT    NULL,

    -- longer human readable description
    description     TEXT    NULL,

    -- should public interfaces show this as an option for searching media sources
    show_on_media   BOOLEAN NULL,

    -- should public interfaces show this as an option for search stories
    show_on_stories BOOLEAN NULL,

    -- if true, users can expect this tag ans its associations not to change in major ways
    is_static       BOOLEAN NOT NULL DEFAULT 'f',

    CONSTRAINT no_line_feed CHECK (
            tag NOT LIKE '%' || CHR(10) || '%' AND
            tag NOT LIKE '%' || CHR(13) || '%'
        ),

    CONSTRAINT tag_not_empty CHECK (LENGTH(tag) > 0)
);

-- FIXME shard this somehow?
-- "tags" could really use some sharding itself as it has lots of rows but then
-- the foreign keys don't really work from elsewhere
-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('tags');

CREATE INDEX tags_tag_sets_id ON tags (tag_sets_id);
CREATE UNIQUE INDEX tags_tag ON tags (tag, tag_sets_id);
CREATE INDEX tags_label ON tags USING HASH (label);
-- noinspection SqlResolve
CREATE INDEX tags_fts ON tags USING GIN (to_tsvector('english'::regconfig, tag || ' ' || label));

CREATE INDEX tags_show_on_media ON tags USING HASH (show_on_media);
CREATE INDEX tags_show_on_stories ON tags USING HASH (show_on_stories);

INSERT INTO tag_sets (name, label, description)
VALUES ('media_type',
        'Media Type',
        'High level topology for media sources for use across a variety of different topics');


CREATE TABLE feeds_tags_map
(
    feeds_tags_map_id BIGSERIAL PRIMARY KEY,
    feeds_id          BIGINT NOT NULL REFERENCES feeds (feeds_id) ON DELETE CASCADE,
    tags_id           BIGINT NOT NULL REFERENCES tags (tags_id) ON DELETE CASCADE
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('feeds_tags_map');

CREATE UNIQUE INDEX feeds_tags_map_feeds_id_tags_id ON feeds_tags_map (feeds_id, tags_id);
CREATE INDEX feeds_tags_map_tags_id ON feeds_tags_map (tags_id);


CREATE TABLE media_tags_map
(
    media_tags_map_id BIGSERIAL PRIMARY KEY,
    media_id          BIGINT NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,
    tags_id           BIGINT NOT NULL REFERENCES tags (tags_id) ON DELETE CASCADE,
    tagged_date       DATE   NULL DEFAULT NOW()
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('media_tags_map');

CREATE INDEX media_tags_map_media_id ON media_tags_map (media_id);
CREATE UNIQUE INDEX media_tags_map_media_id_tags_id ON media_tags_map (media_id, tags_id);
CREATE INDEX media_tags_map_tags_id ON media_tags_map (tags_id);


CREATE TABLE color_sets
(
    color_sets_id BIGSERIAL PRIMARY KEY,
    color         TEXT NOT NULL,
    color_set     TEXT NOT NULL,
    id            TEXT NOT NULL
);

CREATE UNIQUE INDEX color_sets_set_id ON color_sets (color_set, id);

-- prefill colors for partisan_code set so that liberal is blue and conservative is red
INSERT INTO color_sets (color, color_set, id)
VALUES ('c10032', 'partisan_code', 'partisan_2012_conservative'),
       ('00519b', 'partisan_code', 'partisan_2012_liberal'),
       ('009543', 'partisan_code', 'partisan_2012_libertarian');


--
-- Stories (news articles)
--
CREATE TABLE stories
(
    stories_id            BIGSERIAL PRIMARY KEY,
    media_id              BIGINT     NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,
    url                   TEXT       NOT NULL,
    guid                  TEXT       NOT NULL,
    title                 TEXT       NOT NULL,
    normalized_title_hash UUID       NULL,
    description           TEXT       NULL,
    publish_date          TIMESTAMP  NULL,
    collect_date          TIMESTAMP  NOT NULL DEFAULT NOW(),
    full_text_rss         BOOLEAN    NOT NULL DEFAULT 'f',

    -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
    language              VARCHAR(3) NULL
);

SELECT create_distributed_table('stories', 'stories_id');

CREATE INDEX stories_media_id ON stories (media_id);

-- We can't enforce index uniqueness across shards so add_story() has to take care of that instead
CREATE INDEX stories_media_id_guid on stories (media_id, guid);

CREATE INDEX stories_url ON stories USING HASH (url);
CREATE INDEX stories_publish_date ON stories (publish_date);
CREATE INDEX stories_collect_date ON stories (collect_date);
CREATE INDEX stories_media_id_publish_day ON stories (media_id, date_trunc('day', publish_date));
CREATE INDEX stories_language ON stories USING HASH (language);
CREATE INDEX stories_title ON stories USING HASH (title);

-- Crawler currently queries for md5(title) so we have to keep this extra index
-- here while migrating rows from an unsharded table
CREATE INDEX stories_title_hash ON stories USING HASH (md5(title));

CREATE INDEX stories_publish_day ON stories (date_trunc('day', publish_date));
CREATE INDEX stories_media_id_normalized_title_hash ON stories (media_id, normalized_title_hash);


-- get normalized story title by breaking the title into parts by the separator characters :-| and  using
-- the longest single part.  longest part must be at least 32 characters cannot be the same as the media source
-- name.  also remove all html, punctuation and repeated spaces, lowercase, and limit to 1024 characters.
CREATE OR REPLACE FUNCTION get_normalized_title(title TEXT, title_media_id BIGINT)
    RETURNS TEXT
    IMMUTABLE AS
$$

DECLARE
    title_part  TEXT;
    media_title TEXT;

BEGIN

    -- Stupid simple html stripper to avoid html messing up title_parts
    SELECT INTO title REGEXP_REPLACE(title, '<[^<]*>', '', 'gi');
    SELECT INTO title REGEXP_REPLACE(title, '&#?[a-z0-9]*', '', 'gi');

    SELECT INTO title LOWER(title);
    SELECT INTO title REGEXP_REPLACE(title, '- |[:|]', 'SEPSEP', 'g');
    SELECT INTO title REGEXP_REPLACE(title, '[[:punct:]]', '', 'g');
    SELECT INTO title REGEXP_REPLACE(title, '\s+', ' ', 'g');
    SELECT INTO title SUBSTR(title, 0, 1024);

    IF title_media_id = 0 THEN
        RETURN title;
    END IF;

    SELECT INTO title_part part
    FROM (SELECT REGEXP_SPLIT_TO_TABLE(title, ' *SEPSEP *') AS part) AS parts
    ORDER BY LENGTH(part) DESC
    LIMIT 1;

    IF title_part = title THEN
        RETURN title;
    END IF;

    IF length(title_part) < 32 THEN
        RETURN title;
    END IF;

    SELECT INTO media_title get_normalized_title(name, 0)
    FROM media
    WHERE media_id = title_media_id;

    IF media_title = title_part THEN
        RETURN title;
    END IF;

    RETURN title_part;

END
$$ LANGUAGE plpgsql;

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('get_normalized_title(TEXT, BIGINT)');


CREATE OR REPLACE FUNCTION add_normalized_title_hash() RETURNS TRIGGER AS
$$
BEGIN

    IF (TG_OP = 'update') THEN
        IF (OLD.title = NEW.title) THEN
            RETURN NEW;
        END IF;
    END IF;

    SELECT INTO NEW.normalized_title_hash MD5(get_normalized_title(NEW.title, NEW.media_id))::uuid;

    RETURN NEW;

END

$$ LANGUAGE plpgsql;

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('add_normalized_title_hash()');


SELECT run_on_shards_or_raise('stories', $cmd$

    CREATE TRIGGER stories_add_normalized_title
        BEFORE INSERT OR UPDATE
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE add_normalized_title_hash();

    $cmd$);


CREATE OR REPLACE FUNCTION insert_solr_import_story() RETURNS TRIGGER AS
$$

DECLARE

    queue_stories_id BIGINT;
    return_value     RECORD;

BEGIN

    IF (TG_OP = 'UPDATE') OR (TG_OP = 'INSERT') THEN
        SELECT NEW.stories_id INTO queue_stories_id;
    ELSE
        SELECT OLD.stories_id INTO queue_stories_id;
    END IF;

    IF (TG_OP = 'UPDATE') OR (TG_OP = 'INSERT') THEN
        return_value := NEW;
    ELSE
        return_value := OLD;
    END IF;

    IF NOT EXISTS(
            SELECT 1
            FROM processed_stories
            WHERE stories_id = queue_stories_id
        ) THEN
        RETURN return_value;
    END IF;

    INSERT INTO solr_import_stories (stories_id)
    VALUES (queue_stories_id);

    RETURN return_value;

END;

$$ LANGUAGE plpgsql;

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('insert_solr_import_story()');


SELECT run_on_shards_or_raise('stories', $cmd$

    CREATE TRIGGER stories_insert_solr_import_story
        AFTER INSERT OR UPDATE OR DELETE
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE insert_solr_import_story();

    $cmd$);


CREATE TABLE stories_ap_syndicated
(
    stories_ap_syndicated_id BIGSERIAL NOT NULL,
    stories_id               BIGINT    NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    ap_syndicated            BOOLEAN   NOT NULL,

    PRIMARY KEY (stories_ap_syndicated_id, stories_id)
);

SELECT create_distributed_table('stories_ap_syndicated', 'stories_id');

CREATE UNIQUE INDEX stories_ap_syndicated_story ON stories_ap_syndicated (stories_id);


-- List of all URL or GUID identifiers for each story
CREATE TABLE story_urls
(
    story_urls_id BIGSERIAL NOT NULL,
    stories_id    BIGINT    NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    url           TEXT      NOT NULL,

    PRIMARY KEY (story_urls_id, stories_id)
);

SELECT create_distributed_table('story_urls', 'stories_id');

CREATE INDEX story_urls_stories_id ON story_urls (stories_id);
CREATE UNIQUE INDEX story_urls_stories_id_url ON story_urls (stories_id, url);


--
-- Downloads
--

CREATE TYPE download_state AS ENUM (

    -- Download fetch was attempted but led to an error
    'error',

    -- Download is currently being fetched by one of the crawler forks
    'fetching',

    -- Download is waiting for its turn to get fetched
    'pending',

    -- Download was successfully fetched
    'success',

    -- Download was a feed download, and an attempt at parsing it led to an
    -- error (e.g. bad XML syntax)
    'feed_error'

    );

CREATE TYPE download_type AS ENUM (

    -- Download is a content download, e.g. a news story
    'content',

    -- Download is a periodic feed download, e.g. RSS / Atom feed
    'feed'

    );


CREATE TABLE downloads
(
    downloads_id  BIGSERIAL      NOT NULL,
    feeds_id      BIGINT         NOT NULL,
    stories_id    BIGINT         NULL,
    parent        BIGINT         NULL,
    url           TEXT           NOT NULL,
    host          TEXT           NOT NULL,
    download_time TIMESTAMP      NOT NULL DEFAULT NOW(),
    type          download_type  NOT NULL,
    state         download_state NOT NULL,
    path          TEXT           NULL,
    error_message TEXT           NULL,
    priority      SMALLINT       NOT NULL,
    sequence      SMALLINT       NOT NULL,
    extracted     BOOLEAN        NOT NULL DEFAULT 'f',

    -- Partitions require a composite primary key
    PRIMARY KEY (downloads_id, state)

) PARTITION BY LIST (state);

SELECT create_distributed_table('downloads', 'downloads_id');

ALTER TABLE downloads
    ADD CONSTRAINT downloads_feeds_id_fkey
        FOREIGN KEY (feeds_id) REFERENCES feeds (feeds_id);

CREATE INDEX downloads_parent
    ON downloads (parent);

CREATE INDEX downloads_download_time
    ON downloads (download_time);

CREATE INDEX downloads_feeds_id_download_time
    ON downloads (feeds_id, download_time);

CREATE INDEX downloads_stories_id
    ON downloads (stories_id);


CREATE TABLE downloads_error
    PARTITION OF downloads
        FOR VALUES IN ('error');

CREATE UNIQUE INDEX downloads_error_downloads_id
    ON downloads_error (downloads_id);


CREATE TABLE downloads_feed_error
    PARTITION OF downloads
        FOR VALUES IN ('feed_error');

CREATE UNIQUE INDEX downloads_feed_error_downloads_id
    ON downloads_feed_error (downloads_id);


CREATE TABLE downloads_fetching
    PARTITION OF downloads
        FOR VALUES IN ('fetching');

CREATE UNIQUE INDEX downloads_fetching_downloads_id
    ON downloads_fetching (downloads_id);

CREATE TABLE downloads_pending
    PARTITION OF downloads
        FOR VALUES IN ('pending');

CREATE UNIQUE INDEX downloads_pending_downloads_id
    ON downloads_pending (downloads_id);


CREATE TABLE downloads_success
    PARTITION OF downloads (
        CONSTRAINT downloads_success_path_not_null
            CHECK (path IS NOT NULL),
        CONSTRAINT downloads_success_stories_id
            CHECK (
                    (type = 'feed' AND stories_id IS NULL) OR
                    (type = 'content' AND stories_id IS NOT NULL)
                )
        ) FOR VALUES IN ('success');

-- We need a separate unique index for the "download_texts" foreign key to be
-- able to point to "downloads_success"
CREATE UNIQUE INDEX downloads_success_downloads_id
    ON downloads_success (downloads_id);

CREATE INDEX downloads_success_extracted
    ON downloads_success (extracted);


CREATE VIEW downloads_to_be_extracted AS
SELECT *
FROM downloads
WHERE extracted = 'f'
  AND state = 'success'
  AND type = 'content';

CREATE VIEW downloads_in_past_day AS
SELECT *
FROM downloads
WHERE download_time > NOW() - interval '1 day';

CREATE VIEW downloads_with_error_in_past_day AS
SELECT *
FROM downloads_in_past_day
WHERE state = 'error';


-- table for object types used for mediawords.util.public_store
CREATE SCHEMA public_store;


CREATE TABLE public_store.timespan_files
(
    timespan_files_id BIGSERIAL NOT NULL,
    object_id         BIGINT    NOT NULL,
    raw_data          BYTEA     NOT NULL,

    PRIMARY KEY (timespan_files_id, object_id)
);

SELECT create_distributed_table('public_store.timespan_files', 'object_id');

CREATE UNIQUE INDEX timespan_files_object_id ON public_store.timespan_files (object_id);


CREATE TABLE public_store.snapshot_files
(
    snapshot_files_id BIGSERIAL NOT NULL,
    object_id         BIGINT    NOT NULL,
    raw_data          BYTEA     NOT NULL,

    PRIMARY KEY (snapshot_files_id, object_id)
);

SELECT create_distributed_table('public_store.snapshot_files', 'object_id');

CREATE UNIQUE INDEX snapshot_files_object_id ON public_store.snapshot_files (object_id);


CREATE TABLE public_store.timespan_maps
(
    timespan_maps_id BIGSERIAL NOT NULL,
    object_id        BIGINT    NOT NULL,
    raw_data         BYTEA     NOT NULL,

    PRIMARY KEY (timespan_maps_id, object_id)
);

SELECT create_distributed_table('public_store.timespan_maps', 'object_id');

CREATE UNIQUE INDEX timespan_maps_object_id ON public_store.timespan_maps (object_id);


--
-- Raw downloads stored in the database
-- (if the "postgresql" download storage method is enabled)
--
CREATE TABLE raw_downloads
(
    raw_downloads_id BIGSERIAL NOT NULL,

    -- FIXME reference to "downloads_error", "downloads_feed_error" or "downloads_success"
    object_id        BIGINT    NOT NULL,

    raw_data         BYTEA     NOT NULL,

    PRIMARY KEY (raw_downloads_id, object_id)
);

SELECT create_distributed_table('raw_downloads', 'object_id');

CREATE UNIQUE INDEX raw_downloads_object_id ON raw_downloads (object_id);


--
-- Feed -> story map
--

CREATE TABLE feeds_stories_map
(
    feeds_stories_map_id BIGSERIAL NOT NULL,

    feeds_id             BIGINT    NOT NULL,
    stories_id           BIGINT    NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,

    PRIMARY KEY (feeds_stories_map_id, stories_id)
);

SELECT create_distributed_table('feeds_stories_map', 'stories_id');

ALTER TABLE feeds_stories_map
    ADD CONSTRAINT feeds_stories_map_feeds_id_fkey
        FOREIGN KEY (feeds_id) REFERENCES feeds (feeds_id) MATCH FULL ON DELETE CASCADE;

CREATE UNIQUE INDEX feeds_stories_map_feeds_id_stories_id
    ON feeds_stories_map (feeds_id, stories_id);
CREATE INDEX feeds_stories_map_stories_id
    ON feeds_stories_map (stories_id);


--
-- Story -> tag map
--

CREATE TABLE stories_tags_map
(
    stories_tags_map_id BIGSERIAL NOT NULL,

    stories_id          BIGINT    NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    tags_id             BIGINT    NOT NULL,

    PRIMARY KEY (stories_tags_map_id, stories_id)
);

SELECT create_distributed_table('stories_tags_map', 'stories_id');

ALTER TABLE stories_tags_map
    ADD CONSTRAINT stories_tags_map_tags_id_fkey
        FOREIGN KEY (tags_id) REFERENCES tags (tags_id);

CREATE INDEX stories_tags_map_stories_id
    ON stories_tags_map (stories_id);
CREATE UNIQUE INDEX stories_tags_map_stories_id_tags_id
    ON stories_tags_map (stories_id, tags_id);

SELECT run_on_shards_or_raise('stories_tags_map', $cmd$

    CREATE TRIGGER stories_tags_map_insert_solr_import_story
        AFTER INSERT OR UPDATE OR DELETE
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE insert_solr_import_story();

    $cmd$);


CREATE TABLE queued_downloads
(
    queued_downloads_id BIGSERIAL PRIMARY KEY,
    downloads_id        BIGINT NOT NULL
);

-- Not distributed, not reference (used to copy to from "downloads" and generally small)

CREATE UNIQUE INDEX queued_downloads_downloads_id ON queued_downloads (downloads_id);


-- do this as a plpgsql function because it wraps it in the necessary transaction without
-- having to know whether the calling context is in a transaction
CREATE FUNCTION pop_queued_download() RETURNS BIGINT AS
$$

DECLARE

    pop_downloads_id BIGINT;

BEGIN

    SELECT INTO pop_downloads_id downloads_id
    FROM queued_downloads
    ORDER BY downloads_id DESC
    LIMIT 1 FOR UPDATE SKIP LOCKED;

    DELETE
    FROM queued_downloads
    WHERE downloads_id = pop_downloads_id;

    RETURN pop_downloads_id;

END;

$$ LANGUAGE plpgsql;


--
-- Extracted plain text from every download
--
CREATE TABLE download_texts
(
    download_texts_id    BIGSERIAL NOT NULL,
    downloads_id         BIGINT    NOT NULL REFERENCES downloads_success (downloads_id) ON DELETE CASCADE,
    download_text        TEXT      NOT NULL,
    download_text_length INT       NOT NULL,

    PRIMARY KEY (download_texts_id, downloads_id)
);

SELECT create_distributed_table('download_texts', 'downloads_id');

CREATE UNIQUE INDEX download_texts_downloads_id
    ON download_texts (downloads_id);

ALTER TABLE download_texts
    ADD CONSTRAINT download_texts_length_is_correct
        CHECK (length(download_text) = download_text_length);


--
-- Individual sentences of every story
--

CREATE TABLE story_sentences
(
    story_sentences_id BIGSERIAL  NOT NULL,
    stories_id         BIGINT     NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    sentence_number    INT        NOT NULL,
    sentence           TEXT       NOT NULL,
    media_id           BIGINT     NOT NULL,
    publish_date       TIMESTAMP  NULL,

    -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
    language           VARCHAR(3) NULL,

    -- Set to 'true' for every sentence for which a duplicate sentence was
    -- found in a future story (even though that duplicate sentence wasn't
    -- added to the table)
    --
    -- "We only use is_dup in the topic spidering, but I think it is critical
    -- there. It is there because the first time I tried to run a spider on a
    -- broadly popular topic, it was unusable because of the amount of
    -- irrelevant content. When I dug in, I found that stories were getting
    -- included because of matches on boilerplate content that was getting
    -- duped out of most stories but not the first time it appeared. So I added
    -- the check to remove stories that match on a dup sentence, even if it is
    -- the dup sentence, and things cleaned up."
    is_dup             BOOLEAN    NULL,

    PRIMARY KEY (story_sentences_id, stories_id)
);

SELECT create_distributed_table('story_sentences', 'stories_id');

ALTER TABLE story_sentences
    ADD CONSTRAINT story_sentences_media_id_fkey
        FOREIGN KEY (media_id) REFERENCES media (media_id) MATCH FULL ON DELETE CASCADE;

CREATE INDEX story_sentences_media_id
    ON story_sentences (media_id);

CREATE UNIQUE INDEX story_sentences_stories_id_sentence_number
    ON story_sentences (stories_id, sentence_number);

CREATE INDEX story_sentences_media_id_publish_week_sentence
    ON story_sentences (media_id, week_start_date(publish_date::DATE), half_md5(sentence));


CREATE TABLE solr_imports
(
    solr_imports_id BIGSERIAL PRIMARY KEY,
    import_date     TIMESTAMP NOT NULL,
    full_import     BOOLEAN   NOT NULL DEFAULT FALSE,
    num_stories     BIGINT    NULL
);

-- Not distributed, not reference (small and used locally)

CREATE INDEX solr_imports_date ON solr_imports (import_date);


-- Stories to import into Solr
CREATE TABLE solr_import_stories
(
    solr_import_stories_id BIGSERIAL NOT NULL,
    stories_id             BIGINT    NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    PRIMARY KEY (solr_import_stories_id, stories_id)
);

SELECT create_distributed_table('solr_import_stories', 'stories_id');

CREATE INDEX solr_import_stories_stories_id ON solr_import_stories (stories_id);


-- log of all stories import into solr, with the import date
CREATE TABLE solr_imported_stories
(
    solr_imported_stories_id BIGSERIAL NOT NULL,
    stories_id               BIGINT    NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    import_date              TIMESTAMP NOT NULL,
    PRIMARY KEY (solr_imported_stories_id, stories_id)
);

SELECT create_distributed_table('solr_imported_stories', 'stories_id');

CREATE INDEX solr_imported_stories_story
    ON solr_imported_stories (stories_id);
CREATE INDEX solr_imported_stories_day
    ON solr_imported_stories (date_trunc('day', import_date));


CREATE TYPE topics_job_queue_type AS ENUM (
    'mc',
    'public'
    );

-- the mode is how we analyze the data from the platform (as web pages, social
-- media posts, url sharing posts, etc)
CREATE TABLE topic_modes
(
    topic_modes_id BIGSERIAL PRIMARY KEY,
    name           TEXT NOT NULL,
    description    TEXT NOT NULL
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('topic_modes');

CREATE UNIQUE INDEX topic_modes_name ON topic_modes (name);

INSERT INTO topic_modes (name, description)
VALUES ('web', 'analyze urls using hyperlinks as network edges'),
       ('url_sharing', 'analyze urls shared on social media using co-sharing as network edges');


-- the platform is where the analyzed data lives (web, twitter, reddit, etc)
CREATE TABLE topic_platforms
(
    topic_platforms_id BIGSERIAL PRIMARY KEY,
    name               TEXT NOT NULL,
    description        TEXT NOT NULL
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('topic_platforms');

CREATE UNIQUE INDEX topic_platforms_name ON topic_platforms (name);

INSERT INTO topic_platforms (name, description)
VALUES ('web', 'pages on the open web'),
       ('twitter', 'tweets from twitter.com'),
       ('generic_post', 'generic social media posts'),
       ('reddit', 'submissions and comments from reddit.com');


-- the source is where we get the platform data from (a particular database, api, csv, etc)
CREATE TABLE topic_sources
(
    topic_sources_id BIGSERIAL PRIMARY KEY,
    name             TEXT NOT NULL,
    description      TEXT NOT NULL
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('topic_sources');

CREATE UNIQUE INDEX topic_sources_name ON topic_sources (name);

INSERT INTO topic_sources (name, description)
VALUES ('mediacloud', 'import from the mediacloud.org archive'),
       ('crimson_hexagon',
        'import from the crimsonhexagon.com forsight api, only accessible to internal media cloud team'),
       ('brandwatch', 'import from the brandwatch api, only accessible to internal media cloud team'),
       ('csv', 'import generic posts directly from csv'),
       ('postgres', 'import generic posts from a postgres table'),
       ('pushshift', 'import from the pushshift.io api'),
       ('google', 'import from search results on google');


-- the pairs of platforms / sources for which the platform can fetch data
CREATE TABLE topic_platforms_sources_map
(
    topic_platforms_sources_map_id BIGSERIAL PRIMARY KEY,
    topic_platforms_id             BIGINT NOT NULL
        REFERENCES topic_platforms (topic_platforms_id) ON DELETE CASCADE,
    topic_sources_id               BIGINT NOT NULL
        REFERENCES topic_sources (topic_sources_id) ON DELETE CASCADE
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('topic_platforms_sources_map');

CREATE UNIQUE INDEX topic_platforms_sources_map_topic_platforms_id_topic_sources_id
    ON topic_platforms_sources_map (topic_platforms_id, topic_sources_id);

-- easily create platform source pairs
CREATE OR REPLACE FUNCTION insert_platform_source_pair(platform_name TEXT, source_name TEXT)
    RETURNS VOID AS
$$

BEGIN

    INSERT INTO topic_platforms_sources_map (topic_platforms_id, topic_sources_id)
    SELECT tp.topic_platforms_id,
           ts.topic_sources_id
    FROM topic_platforms AS tp
             CROSS JOIN topic_sources AS ts
    WHERE tp.name = platform_name
      AND ts.name = source_name;

END
$$ LANGUAGE plpgsql;

SELECT insert_platform_source_pair('web', 'mediacloud');
SELECT insert_platform_source_pair('twitter', 'crimson_hexagon');
SELECT insert_platform_source_pair('generic_post', 'csv');
SELECT insert_platform_source_pair('generic_post', 'postgres');
SELECT insert_platform_source_pair('reddit', 'pushshift');
SELECT insert_platform_source_pair('web', 'google');


CREATE TABLE topics
(
    topics_id                     BIGSERIAL PRIMARY KEY,
    name                          TEXT                  NOT NULL,
    pattern                       TEXT                  NULL,
    solr_seed_query               TEXT                  NULL,
    solr_seed_query_run           BOOLEAN               NOT NULL DEFAULT 'f',
    description                   TEXT                  NOT NULL,
    media_type_tag_sets_id        BIGINT                NULL REFERENCES tag_sets (tag_sets_id),
    max_iterations                BIGINT                NOT NULL DEFAULT 15,
    state                         TEXT                  NOT NULL DEFAULT 'created but not queued',
    message                       TEXT                  NULL,
    is_public                     BOOLEAN               NOT NULL DEFAULT 'f',
    is_logogram                   BOOLEAN               NOT NULL DEFAULT 'f',
    start_date                    DATE                  NOT NULL,
    end_date                      DATE                  NOT NULL,

    -- if true, the topic_stories associated with this topic will be set to link_mined = 'f' on the next mining job
    respider_stories              BOOLEAN               NOT NULL DEFAULT 'f',
    respider_start_date           DATE                  NULL,
    respider_end_date             DATE                  NULL,

    -- space separate list of periods to snapshot
    snapshot_periods              TEXT                  NULL,

    -- platform that topic is analyzing
    platform                      TEXT                  NOT NULL REFERENCES topic_platforms (name),

    -- mode of analysis
    mode                          TEXT                  NOT NULL DEFAULT 'web' REFERENCES topic_modes (name),

    -- job queue to use for spider and snapshot jobs for this topic
    job_queue                     topics_job_queue_type NOT NULL,

    -- max stories allowed in the topic
    max_stories                   BIGINT                NOT NULL,

    -- if false, we should refuse to spider this topic because the use has not
    -- confirmed the new story query syntax
    is_story_index_ready          BOOLEAN               NOT NULL DEFAULT 't',

    -- if true, snapshots are pruned to only stories with a minimum level of
    -- engagements (links, shares, etc)
    only_snapshot_engaged_stories BOOLEAN               NOT NULL DEFAULT 'f'
);

-- "topics" itself is tiny but we want it to be distributed so that all the
-- stuff that belongs to a single topic is colocated together
SELECT create_distributed_table('topics', 'topics_id');

CREATE INDEX topics_name ON topics (name);
CREATE INDEX topics_media_type_tag_set ON topics (media_type_tag_sets_id);


-- Given that the unique index on (guid, media_id) is going to be valid only
-- per shard, add a trigger that will check for uniqueness after each INSERT.
-- We add the trigger after migrating a chunk of stories first to increase
-- performance of the copy.
CREATE OR REPLACE FUNCTION topics_ensure_unique_name() RETURNS trigger AS
$$

DECLARE
    name_row_count INT;

BEGIN

    SELECT COUNT(*)
    INTO name_row_count
    FROM topics
    WHERE name = NEW.name;

    IF name_row_count > 1 THEN
        RAISE EXCEPTION 'Duplicate topic name';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('topics_ensure_unique_name()');


SELECT run_on_shards_or_raise('topics', $cmd$

    CREATE TRIGGER topics_ensure_unique_name
        AFTER INSERT
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE topics_ensure_unique_name();

    $cmd$);


-- Given that the unique index on (guid, media_id) is going to be valid only
-- per shard, add a trigger that will check for uniqueness after each INSERT.
-- We add the trigger after migrating a chunk of stories first to increase
-- performance of the copy.
CREATE OR REPLACE FUNCTION topics_ensure_unique_media_type_tag_sets_id() RETURNS trigger AS
$$

DECLARE
    media_type_tag_sets_id_row_count INT;

BEGIN

    SELECT COUNT(*)
    INTO media_type_tag_sets_id_row_count
    FROM topics
    WHERE media_type_tag_sets_id = NEW.media_type_tag_sets_id;

    IF media_type_tag_sets_id_row_count > 1 THEN
        RAISE EXCEPTION 'Duplicate topic media_type_tag_sets_id';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('topics_ensure_unique_media_type_tag_sets_id()');


SELECT run_on_shards_or_raise('topics', $cmd$

    CREATE TRIGGER topics_ensure_unique_media_type_tag_sets_id
        AFTER INSERT
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE topics_ensure_unique_media_type_tag_sets_id();

    $cmd$);


CREATE TABLE topic_seed_queries
(
    topic_seed_queries_id BIGSERIAL NOT NULL,
    topics_id             BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    source                TEXT      NOT NULL,
    platform              TEXT      NOT NULL,
    query                 TEXT      NULL,
    imported_date         TIMESTAMP NULL,
    ignore_pattern        TEXT      NULL,

    PRIMARY KEY (topic_seed_queries_id, topics_id)
);

SELECT create_distributed_table('topic_seed_queries', 'topics_id');

CREATE INDEX topic_seed_queries_topic ON topic_seed_queries (topics_id);

ALTER TABLE topic_seed_queries
    ADD CONSTRAINT topic_seed_queries_source_fkey
        FOREIGN KEY (source) REFERENCES topic_sources (name);

ALTER TABLE topic_seed_queries
    ADD CONSTRAINT topic_seed_queries_platform_fkey
        FOREIGN KEY (platform) REFERENCES topic_platforms (name);


CREATE TABLE topic_dates
(
    topic_dates_id BIGSERIAL NOT NULL,
    topics_id      BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    start_date     DATE      NOT NULL,
    end_date       DATE      NOT NULL,
    boundary       BOOLEAN   NOT NULL DEFAULT 'f',

    PRIMARY KEY (topic_dates_id, topics_id)
);

SELECT create_distributed_table('topic_dates', 'topics_id');


CREATE TABLE topics_media_map
(
    topics_media_map_id BIGSERIAL NOT NULL,
    topics_id           BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    media_id            BIGINT    NOT NULL,

    PRIMARY KEY (topics_media_map_id, topics_id)
);

SELECT create_distributed_table('topics_media_map', 'topics_id');

ALTER TABLE topics_media_map
    ADD CONSTRAINT topics_media_map_media_id_fkey
        FOREIGN KEY (media_id) REFERENCES media (media_id) ON DELETE CASCADE;

CREATE INDEX topics_media_map_topics_id ON topics_media_map (topics_id);

CREATE INDEX topics_media_map_media_id ON topics_media_map (media_id);


CREATE TABLE topics_media_tags_map
(
    topics_media_tags_map_id BIGSERIAL NOT NULL,
    topics_id                BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    tags_id                  BIGINT    NOT NULL,

    PRIMARY KEY (topics_media_tags_map_id, topics_id)
);

SELECT create_distributed_table('topics_media_tags_map', 'topics_id');

ALTER TABLE topics_media_tags_map
    ADD CONSTRAINT topics_media_tags_map_tags_id_fkey
        FOREIGN KEY (tags_id) REFERENCES tags (tags_id) ON DELETE CASCADE;

CREATE INDEX topics_media_tags_map_topic ON topics_media_tags_map (topics_id);


CREATE TABLE topic_media_codes
(
    topic_media_codes_id BIGSERIAL NOT NULL,
    topics_id            BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    media_id             BIGINT    NOT NULL,
    code_type            TEXT      NULL,
    code                 TEXT      NULL,

    PRIMARY KEY (topic_media_codes_id, topics_id)
);

SELECT create_distributed_table('topic_media_codes', 'topics_id');

ALTER TABLE topic_media_codes
    ADD CONSTRAINT topic_media_codes_media_id_fkey
        FOREIGN KEY (media_id) REFERENCES media (media_id) ON DELETE CASCADE;

CREATE INDEX topic_media_codes_media_id ON topic_media_codes (media_id);


CREATE TABLE topic_merged_stories_map
(
    topic_merged_stories_map_id BIGSERIAL NOT NULL,
    source_stories_id           BIGINT    NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    target_stories_id           BIGINT    NOT NULL,

    PRIMARY KEY (topic_merged_stories_map_id, source_stories_id)
);

SELECT create_distributed_table('topic_merged_stories_map', 'source_stories_id');

CREATE INDEX topic_merged_stories_map_source_stories_id
    ON topic_merged_stories_map (source_stories_id);

CREATE INDEX topic_merged_stories_map_target_stories_id
    ON topic_merged_stories_map (target_stories_id);


-- track self links and all links for a given domain within a given topic
CREATE TABLE topic_domains
(
    topic_domains_id BIGSERIAL NOT NULL,
    topics_id        BIGINT    NOT NULL,
    domain           TEXT      NOT NULL,
    self_links       BIGINT    NOT NULL DEFAULT 0,

    PRIMARY KEY (topic_domains_id, topics_id)
);

SELECT create_distributed_table('topic_domains', 'topics_id');

CREATE UNIQUE INDEX topic_domains_domain ON topic_domains (topics_id, md5(domain));


CREATE TABLE topic_stories
(
    topic_stories_id        BIGSERIAL NOT NULL,
    topics_id               BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    stories_id              BIGINT    NOT NULL,
    link_mined              BOOLEAN   NULL DEFAULT 'f',
    iteration               BIGINT    NULL DEFAULT 0,
    link_weight             REAL      NULL,
    redirect_url            TEXT      NULL,
    valid_foreign_rss_story BOOLEAN   NULL DEFAULT false,
    link_mine_error         TEXT      NULL,

    PRIMARY KEY (topic_stories_id, topics_id)
);

SELECT create_distributed_table('topic_stories', 'topics_id');

CREATE UNIQUE INDEX topic_stories_topics_id_stories_id
    ON topic_stories (topics_id, stories_id);

CREATE INDEX topic_stories_topics_id
    ON topic_stories (topics_id);


-- topic links for which the http request failed
CREATE TABLE topic_dead_links
(
    topic_dead_links_id BIGSERIAL NOT NULL,
    topics_id           BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    stories_id          BIGINT    NULL,
    url                 TEXT      NOT NULL,

    PRIMARY KEY (topic_dead_links_id, topics_id)
);

SELECT create_distributed_table('topic_dead_links', 'topics_id');


CREATE TABLE topic_links
(
    topic_links_id BIGSERIAL NOT NULL,
    topics_id      BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    stories_id     BIGINT    NOT NULL,
    url            TEXT      NOT NULL,
    redirect_url   TEXT      NULL,
    ref_stories_id BIGINT    NULL,
    link_spidered  BOOLEAN   NULL DEFAULT 'f',

    PRIMARY KEY (topic_links_id, topics_id),

    FOREIGN KEY (stories_id, topics_id)
        REFERENCES topic_stories (stories_id, topics_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('topic_links', 'topics_id');

CREATE UNIQUE INDEX topic_links_topics_id_stories_id_ref_stories_id
    ON topic_links (topics_id, stories_id, ref_stories_id);

CREATE INDEX topic_links_topics_id ON topic_links (topics_id);

CREATE INDEX topic_links_ref_stories_id ON topic_links (ref_stories_id);


CREATE OR REPLACE VIEW topic_links_cross_media AS
WITH stories_from_topic AS NOT MATERIALIZED (
    SELECT topic_links.topic_links_id,
           topic_links.topics_id,
           topic_links.url,
           topic_links.stories_id,
           topic_links.ref_stories_id
    FROM topic_stories
             INNER JOIN topic_links ON
            topic_stories.topics_id = topic_links.topics_id AND
            topic_stories.stories_id = topic_links.ref_stories_id AND
            topic_links.ref_stories_id != topic_links.stories_id
),

     stories_non_ref AS NOT MATERIALIZED (
         SELECT stories_id,
                stories.media_id,
                media.name AS media_name
         FROM stories
                  INNER JOIN media ON
             stories.media_id = media.media_id
         WHERE stories_id IN (
             SELECT stories_id
             FROM stories_from_topic
         )
     ),

     stories_ref AS NOT MATERIALIZED (
         SELECT stories_id,
                stories.media_id,
                media.name AS media_name
         FROM stories
                  INNER JOIN media ON
             stories.media_id = media.media_id
         WHERE stories_id IN (
             SELECT ref_stories_id
             FROM stories_from_topic
         )
     )

SELECT stories_from_topic.*,
       stories_non_ref.media_name AS media_name,
       stories_ref.media_name     AS ref_media_name
FROM stories_from_topic
         INNER JOIN stories_non_ref ON
    stories_from_topic.stories_id = stories_non_ref.stories_id
         INNER JOIN stories_ref ON
    stories_from_topic.ref_stories_id = stories_ref.stories_id
WHERE stories_non_ref.media_id != stories_ref.media_id
;


CREATE TABLE topic_fetch_urls
(
    topic_fetch_urls_id BIGSERIAL NOT NULL,
    topics_id           BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    url                 TEXT      NOT NULL,
    code                INT       NULL,
    fetch_date          TIMESTAMP NULL,
    state               TEXT      NOT NULL,
    message             TEXT      NULL,
    stories_id          BIGINT    NULL,
    assume_match        BOOLEAN   NOT NULL DEFAULT 'f',
    topic_links_id      BIGINT    NULL,

    PRIMARY KEY (topic_fetch_urls_id, topics_id),

    FOREIGN KEY (topics_id, topic_links_id)
        REFERENCES topic_links (topics_id, topic_links_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('topic_fetch_urls', 'topics_id');

CREATE INDEX topic_fetch_urls_topics_id_pending
    ON topic_fetch_urls (topics_id)
    WHERE state = 'pending';

CREATE INDEX topic_fetch_urls_url on topic_fetch_urls USING HASH (url);

-- FIXME Remove backwards compatible index after sharding
CREATE INDEX topic_fetch_urls_url_md5 on topic_fetch_urls USING HASH (md5(url));

CREATE INDEX topic_fetch_urls_topic_links_id ON topic_fetch_urls (topic_links_id);


CREATE TABLE topic_ignore_redirects
(
    topic_ignore_redirects_id BIGSERIAL PRIMARY KEY,
    url                       TEXT NULL
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('topic_ignore_redirects');

CREATE INDEX topic_ignore_redirects_url on topic_ignore_redirects USING HASH (url);


CREATE TYPE bot_policy_type AS ENUM (
    'all',
    'no bots',
    'only bots'
    );


CREATE TABLE snapshots
(
    snapshots_id  BIGSERIAL       NOT NULL,
    topics_id     BIGINT          NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    snapshot_date TIMESTAMP       NOT NULL,
    start_date    TIMESTAMP       NOT NULL,
    end_date      TIMESTAMP       NOT NULL,
    note          TEXT            NULL,
    state         TEXT            NOT NULL DEFAULT 'queued',
    message       TEXT            NULL,
    searchable    BOOLEAN         NOT NULL DEFAULT 'f',
    bot_policy    bot_policy_type NULL,
    seed_queries  JSONB           NULL,

    PRIMARY KEY (snapshots_id, topics_id)
);

SELECT create_distributed_table('snapshots', 'topics_id');

CREATE INDEX snapshots_topic ON snapshots (topics_id);


CREATE TYPE snap_period_type AS ENUM (
    'overall',
    'weekly',
    'monthly',
    'custom'
    );

CREATE TYPE focal_technique_type AS ENUM (
    'Boolean Query',
    'URL Sharing'
    );


CREATE TABLE focal_set_definitions
(
    focal_set_definitions_id BIGSERIAL            NOT NULL,
    topics_id                BIGINT               NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    name                     TEXT                 NOT NULL,
    description              TEXT                 NULL,
    focal_technique          focal_technique_type NOT NULL,

    PRIMARY KEY (focal_set_definitions_id, topics_id)
);

SELECT create_distributed_table('focal_set_definitions', 'topics_id');

CREATE UNIQUE INDEX focal_set_definitions_topics_id_name
    ON focal_set_definitions (topics_id, name);


CREATE TABLE focus_definitions
(
    focus_definitions_id     BIGSERIAL NOT NULL,
    topics_id                BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    focal_set_definitions_id BIGINT    NOT NULL,
    name                     TEXT      NOT NULL,
    description              TEXT      NULL,
    arguments                JSONB     NOT NULL,

    PRIMARY KEY (focus_definitions_id, topics_id),

    FOREIGN KEY (topics_id, focal_set_definitions_id)
        REFERENCES focal_set_definitions (topics_id, focal_set_definitions_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('focus_definitions', 'topics_id');

CREATE UNIQUE INDEX focus_definition_topics_id_focal_set_definitions_id_name
    ON focus_definitions (topics_id, focal_set_definitions_id, name);


CREATE TABLE focal_sets
(
    focal_sets_id   BIGSERIAL            NOT NULL,
    topics_id       BIGINT               NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    snapshots_id    BIGINT               NOT NULL,
    name            TEXT                 NOT NULL,
    description     TEXT                 NULL,
    focal_technique focal_technique_type NOT NULL,

    PRIMARY KEY (focal_sets_id, topics_id),

    FOREIGN KEY (topics_id, snapshots_id) REFERENCES snapshots (topics_id, snapshots_id)
);

SELECT create_distributed_table('focal_sets', 'topics_id');

CREATE UNIQUE INDEX focal_set_topics_id_snapshots_id_name
    ON focal_sets (topics_id, snapshots_id, name);


CREATE TABLE foci
(
    foci_id       BIGSERIAL NOT NULL,
    topics_id     BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    focal_sets_id BIGINT    NOT NULL,
    name          TEXT      NOT NULL,
    description   TEXT      NULL,
    arguments     JSONB     NOT NULL,

    PRIMARY KEY (foci_id, topics_id),

    FOREIGN KEY (topics_id, focal_sets_id)
        REFERENCES focal_sets (topics_id, focal_sets_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('foci', 'topics_id');

CREATE UNIQUE INDEX foci_topics_id_focal_sets_id_name
    ON foci (topics_id, focal_sets_id, name);


-- individual timespans within a snapshot
CREATE TABLE timespans
(
    timespans_id         BIGSERIAL        NOT NULL,

    topics_id            BIGINT           NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,

    -- timespan is an active part of this snapshot
    snapshots_id         BIGINT           NULL,

    -- timespan is an archived part of this snapshot (and thus mostly not visible)
    archive_snapshots_id BIGINT           NULL,

    foci_id              BIGINT           NULL,
    start_date           TIMESTAMP        NOT NULL,
    end_date             TIMESTAMP        NOT NULL,
    period               snap_period_type NOT NULL,
    model_r2_mean        FLOAT            NULL,
    model_r2_stddev      FLOAT            NULL,
    model_num_media      BIGINT           NULL,
    story_count          BIGINT           NOT NULL,
    story_link_count     BIGINT           NOT NULL,
    medium_count         BIGINT           NOT NULL,
    medium_link_count    BIGINT           NOT NULL,
    post_count           BIGINT           NOT NULL,
    tags_id              BIGINT           NULL,

    PRIMARY KEY (timespans_id, topics_id),

    FOREIGN KEY (topics_id, snapshots_id)
        REFERENCES snapshots (topics_id, snapshots_id)
        ON DELETE CASCADE,

    FOREIGN KEY (topics_id, archive_snapshots_id)
        REFERENCES snapshots (topics_id, snapshots_id)
        ON DELETE CASCADE,

    FOREIGN KEY (topics_id, foci_id) REFERENCES foci (topics_id, foci_id),

    CHECK (
            (snapshots_id IS NULL AND archive_snapshots_id IS NOT NULL)
            OR
            (snapshots_id IS NOT NULL AND archive_snapshots_id IS NULL)
        )
);

SELECT create_distributed_table('timespans', 'topics_id');

-- Skip (?) ON CASCADE to avoid accidental deletion
ALTER TABLE timespans
    ADD CONSTRAINT timespans_tags_id_fkey
        FOREIGN KEY (tags_id) REFERENCES tags (tags_id);

CREATE INDEX timespans_snapshots_id ON timespans (snapshots_id);

CREATE UNIQUE INDEX timespans_unique
    ON timespans (topics_id, snapshots_id, foci_id, start_date, end_date, period);


CREATE TABLE timespan_maps
(
    timespan_maps_id BIGSERIAL NOT NULL,
    topics_id        BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    timespans_id     BIGINT    NOT NULL,
    options          JSONB     NOT NULL,
    content          BYTEA     NULL,
    url              TEXT      NULL,
    format           TEXT      NOT NULL,

    PRIMARY KEY (timespan_maps_id, topics_id),

    FOREIGN KEY (topics_id, timespans_id)
        REFERENCES timespans (topics_id, timespans_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('timespan_maps', 'topics_id');

CREATE INDEX timespan_maps_topics_id_timespans_id ON timespan_maps (topics_id, timespans_id);


CREATE TABLE timespan_files
(
    timespan_files_id BIGSERIAL NOT NULL,
    topics_id         BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    timespans_id      BIGINT    NOT NULL,
    name              TEXT      NULL,
    url               TEXT      NULL,

    PRIMARY KEY (timespan_files_id, topics_id),

    FOREIGN KEY (topics_id, timespans_id)
        REFERENCES timespans (topics_id, timespans_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('timespan_files', 'topics_id');

CREATE UNIQUE INDEX timespan_files_topics_id_timespans_id_name
    ON timespan_files (topics_id, timespans_id, name);


CREATE TABLE snapshot_files
(
    snapshot_files_id BIGSERIAL NOT NULL,
    topics_id         BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    snapshots_id      BIGINT    NOT NULL,
    name              TEXT      NULL,
    url               TEXT      NULL,

    PRIMARY KEY (snapshot_files_id, topics_id),

    FOREIGN KEY (topics_id, snapshots_id)
        REFERENCES snapshots (topics_id, snapshots_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snapshot_files', 'topics_id');

CREATE UNIQUE INDEX snapshot_files_topics_id_snapshots_id_name
    ON snapshot_files (topics_id, snapshots_id, name);


-- schema to hold the various snapshot snapshot tables
CREATE SCHEMA snap;


-- create a table for each of these tables to hold a snapshot of stories relevant
-- to a topic for each snapshot for that topic
CREATE TABLE snap.stories
(
    snap_stories_id BIGSERIAL  NOT NULL,
    topics_id       BIGINT     NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    snapshots_id    BIGINT     NOT NULL,
    stories_id      BIGINT     NULL,
    media_id        BIGINT     NOT NULL,
    url             TEXT       NOT NULL,
    guid            TEXT       NOT NULL,
    title           TEXT       NOT NULL,
    publish_date    TIMESTAMP  NULL,
    collect_date    TIMESTAMP  NOT NULL,
    full_text_rss   BOOLEAN    NOT NULL DEFAULT 'f',

    -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
    language        VARCHAR(3) NULL,

    PRIMARY KEY (snap_stories_id, topics_id),

    FOREIGN KEY (topics_id, snapshots_id)
        REFERENCES snapshots (topics_id, snapshots_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snap.stories', 'topics_id');

CREATE INDEX snap_stories_snapshots_id_stories_id ON snap.stories (snapshots_id, stories_id);


-- stats for various externally derived statistics about a story.
CREATE TABLE story_statistics
(
    story_statistics_id       BIGSERIAL NOT NULL,
    stories_id                BIGINT    NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,

    facebook_share_count      BIGINT    NULL,
    facebook_comment_count    BIGINT    NULL,
    facebook_reaction_count   BIGINT    NULL,
    facebook_api_collect_date TIMESTAMP NULL,
    facebook_api_error        TEXT      NULL,

    PRIMARY KEY (story_statistics_id, stories_id)
);

SELECT create_distributed_table('story_statistics', 'stories_id');

CREATE UNIQUE INDEX story_statistics_story ON story_statistics (stories_id);


-- stats for deprecated Twitter share counts
CREATE TABLE story_statistics_twitter
(
    story_statistics_twitter_id BIGSERIAL NOT NULL,
    stories_id                  BIGINT    NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,

    twitter_url_tweet_count     BIGINT    NULL,
    twitter_api_collect_date    TIMESTAMP NULL,
    twitter_api_error           TEXT      NULL,

    PRIMARY KEY (story_statistics_twitter_id, stories_id)
);

SELECT create_distributed_table('story_statistics_twitter', 'stories_id');

CREATE UNIQUE INDEX story_statistics_twitter_story on story_statistics_twitter (stories_id);


CREATE TABLE snap.topic_stories
(
    snap_topic_stories_id   BIGSERIAL NOT NULL,
    topics_id               BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    snapshots_id            BIGINT    NOT NULL,
    topic_stories_id        BIGINT    NULL,
    stories_id              BIGINT    NOT NULL,
    link_mined              BOOLEAN   NULL,
    iteration               BIGINT    NULL,
    link_weight             REAL      NULL,
    redirect_url            TEXT      NULL,
    valid_foreign_rss_story BOOLEAN   NULL,

    PRIMARY KEY (snap_topic_stories_id, topics_id),

    FOREIGN KEY (topics_id, snapshots_id)
        REFERENCES snapshots (topics_id, snapshots_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snap.topic_stories', 'topics_id');

CREATE INDEX snap_topic_stories_snapshots_id_stories_id
    ON snap.topic_stories (snapshots_id, stories_id);


CREATE TABLE snap.topic_links_cross_media
(
    snap_topic_links_cross_media_id BIGSERIAL NOT NULL,
    topics_id                       BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    snapshots_id                    BIGINT    NOT NULL,
    topic_links_id                  BIGINT    NULL,
    stories_id                      BIGINT    NOT NULL,
    url                             TEXT      NOT NULL,
    ref_stories_id                  BIGINT    NULL,

    PRIMARY KEY (snap_topic_links_cross_media_id, topics_id),

    FOREIGN KEY (topics_id, snapshots_id)
        REFERENCES snapshots (topics_id, snapshots_id)
        ON DELETE CASCADE,

    FOREIGN KEY (topics_id, topic_links_id)
        REFERENCES topic_links (topics_id, topic_links_id)
);

SELECT create_distributed_table('snap.topic_links_cross_media', 'topics_id');

CREATE INDEX snap_topic_links_cross_media_snapshots_id_stories_id
    ON snap.topic_links_cross_media (snapshots_id, stories_id);

CREATE INDEX snap_topic_links_cross_media_snapshots_id_ref_stories_id
    ON snap.topic_links_cross_media (snapshots_id, ref_stories_id);


CREATE TABLE snap.topic_media_codes
(
    snap_topic_media_codes_id BIGSERIAL NOT NULL,
    topics_id                 BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    snapshots_id              BIGINT    NOT NULL,
    media_id                  BIGINT    NOT NULL,
    code_type                 TEXT      NULL,
    code                      TEXT      NULL,

    PRIMARY KEY (snap_topic_media_codes_id, topics_id),

    FOREIGN KEY (topics_id, snapshots_id)
        REFERENCES snapshots (topics_id, snapshots_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snap.topic_media_codes', 'topics_id');

CREATE INDEX snap_topic_media_codes_snapshots_id_media_id
    ON snap.topic_media_codes (snapshots_id, media_id);


CREATE TABLE snap.media
(
    snap_media_id     BIGSERIAL NOT NULL,
    topics_id         BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    snapshots_id      BIGINT    NOT NULL,
    media_id          BIGINT    NULL,
    url               TEXT      NOT NULL,
    name              TEXT      NOT NULL,
    full_text_rss     BOOLEAN   NULL,
    foreign_rss_links BOOLEAN   NOT NULL DEFAULT 'f',
    dup_media_id      BIGINT    NULL,
    is_not_dup        BOOLEAN   NULL,

    PRIMARY KEY (snap_media_id, topics_id),

    FOREIGN KEY (topics_id, snapshots_id)
        REFERENCES snapshots (topics_id, snapshots_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snap.media', 'topics_id');

CREATE INDEX snap_media_snapshots_id_media_id
    ON snap.media (snapshots_id, media_id);


CREATE TABLE snap.media_tags_map
(
    snap_media_tags_map_id BIGSERIAL NOT NULL,
    topics_id              BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    snapshots_id           BIGINT    NOT NULL,
    media_tags_map_id      BIGINT    NULL,
    media_id               BIGINT    NOT NULL,
    tags_id                BIGINT    NOT NULL,

    PRIMARY KEY (snap_media_tags_map_id, topics_id),

    FOREIGN KEY (topics_id, snapshots_id)
        REFERENCES snapshots (topics_id, snapshots_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snap.media_tags_map', 'topics_id');

CREATE INDEX snap_media_tags_map_snapshots_id_media_id
    ON snap.media_tags_map (snapshots_id, media_id);

CREATE INDEX snap_media_tags_map_snapshots_id_tags_id
    ON snap.media_tags_map (snapshots_id, tags_id);


CREATE TABLE snap.stories_tags_map
(
    snap_stories_tags_map_id BIGSERIAL NOT NULL,
    topics_id                BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    snapshots_id             BIGINT    NOT NULL,
    stories_tags_map_id      BIGINT    NULL,
    stories_id               BIGINT    NULL,
    tags_id                  BIGINT    NULL,

    PRIMARY KEY (snap_stories_tags_map_id, topics_id),

    FOREIGN KEY (topics_id, snapshots_id)
        REFERENCES snapshots (topics_id, snapshots_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snap.stories_tags_map', 'topics_id');

CREATE INDEX snap_stories_tags_map_snapshots_id_stories_id
    ON snap.stories_tags_map (snapshots_id, stories_id);

CREATE INDEX snap_stories_tags_map_snapshots_id_tags_id
    ON snap.stories_tags_map (snapshots_id, tags_id);


-- story -> story links within a timespan
CREATE TABLE snap.story_links
(
    snap_story_links_id BIGSERIAL NOT NULL,
    topics_id           BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    timespans_id        BIGINT    NOT NULL,
    source_stories_id   BIGINT    NOT NULL,
    ref_stories_id      BIGINT    NOT NULL,

    PRIMARY KEY (snap_story_links_id, topics_id),

    FOREIGN KEY (topics_id, timespans_id)
        REFERENCES timespans (topics_id, timespans_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snap.story_links', 'topics_id');

-- TODO: add complex foreign key to check that *_stories_id exist for the snapshot stories snapshot
CREATE INDEX snap_story_links_timespans_id_source_stories_id
    ON snap.story_links (timespans_id, source_stories_id);

CREATE INDEX snap_story_links_timespans_id_ref_stories_id
    ON snap.story_links (timespans_id, ref_stories_id);


-- link counts for stories within a timespan
CREATE TABLE snap.story_link_counts
(
    snap_story_link_counts_id BIGSERIAL NOT NULL,
    topics_id                 BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    timespans_id              BIGINT    NOT NULL,
    stories_id                BIGINT    NOT NULL,

    media_inlink_count        BIGINT    NOT NULL,
    inlink_count              BIGINT    NOT NULL,
    outlink_count             BIGINT    NOT NULL,

    facebook_share_count      BIGINT    NULL,

    post_count                BIGINT    NULL,
    author_count              BIGINT    NULL,
    channel_count             BIGINT    NULL,

    PRIMARY KEY (snap_story_link_counts_id, topics_id),

    FOREIGN KEY (topics_id, timespans_id)
        REFERENCES timespans (topics_id, timespans_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snap.story_link_counts', 'topics_id');

-- TODO: add complex foreign key to check that stories_id exists for the snapshot stories snapshot
CREATE INDEX snap_story_link_counts_timespans_id_stories_id
    ON snap.story_link_counts (timespans_id, stories_id);

CREATE INDEX snap_story_link_counts_stories_id
    ON snap.story_link_counts (stories_id);

CREATE INDEX snap_story_link_counts_timespans_id_facebook_share_count
    ON snap.story_link_counts (timespans_id, facebook_share_count DESC NULLS LAST);

CREATE INDEX snap_story_link_counts_timespans_id_post_count
    ON snap.story_link_counts (timespans_id, post_count DESC NULLS LAST);

CREATE INDEX snap_story_link_counts_timespans_id_author_count
    ON snap.story_link_counts (timespans_id, author_count DESC NULLS LAST);

CREATE INDEX snap_story_link_counts_timespans_id_channel_count
    ON snap.story_link_counts (timespans_id, channel_count DESC NULLS LAST);


-- links counts for media within a timespan
CREATE TABLE snap.medium_link_counts
(
    snap_medium_link_counts_id BIGSERIAL NOT NULL,
    topics_id                  BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    timespans_id               BIGINT    NOT NULL,
    media_id                   BIGINT    NOT NULL,

    sum_media_inlink_count     BIGINT    NOT NULL,
    media_inlink_count         BIGINT    NOT NULL,
    inlink_count               BIGINT    NOT NULL,
    outlink_count              BIGINT    NOT NULL,
    story_count                BIGINT    NOT NULL,

    facebook_share_count       BIGINT    NULL,

    sum_post_count             BIGINT    NULL,
    sum_author_count           BIGINT    NULL,
    sum_channel_count          BIGINT    NULL,

    PRIMARY KEY (snap_medium_link_counts_id, topics_id),

    FOREIGN KEY (topics_id, timespans_id)
        REFERENCES timespans (topics_id, timespans_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snap.medium_link_counts', 'topics_id');

-- TODO: add complex foreign key to check that media_id exists for the snapshot media snapshot
CREATE INDEX snap_medium_link_counts_timespans_id_media_id
    ON snap.medium_link_counts (timespans_id, media_id);

CREATE INDEX snap_medium_link_counts_timespans_id_facebook_share_count
    ON snap.medium_link_counts (timespans_id, facebook_share_count DESC NULLS LAST);

CREATE INDEX snap_medium_link_counts_timespans_id_sum_post_count
    ON snap.medium_link_counts (timespans_id, sum_post_count DESC NULLS LAST);

CREATE INDEX snap_medium_link_counts_timespans_id_sum_author_count
    ON snap.medium_link_counts (timespans_id, sum_author_count DESC NULLS LAST);

CREATE INDEX snap_medium_link_counts_timespans_id_sum_channel_count
    ON snap.medium_link_counts (timespans_id, sum_channel_count DESC NULLS LAST);


CREATE TABLE snap.medium_links
(
    snap_medium_links_id BIGSERIAL NOT NULL,
    topics_id            BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    timespans_id         BIGINT    NOT NULL,
    source_media_id      BIGINT    NOT NULL,
    ref_media_id         BIGINT    NOT NULL,
    link_count           BIGINT    NOT NULL,

    PRIMARY KEY (snap_medium_links_id, topics_id),

    FOREIGN KEY (topics_id, timespans_id)
        REFERENCES timespans (topics_id, timespans_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snap.medium_links', 'topics_id');

-- TODO: add complex foreign key to check that *_media_id exist for the snapshot media snapshot
CREATE INDEX snap_medium_links_timespans_id_source_media_id
    ON snap.medium_links (timespans_id, source_media_id);

CREATE INDEX snap_medium_links_timespans_id_ref_media_id
    ON snap.medium_links (timespans_id, ref_media_id);


-- create a mirror of the stories table with the stories for each topic.  this is to make
-- it much faster to query the stories associated with a given topic, rather than querying the
-- congested and bloated stories table.  only inserts and updates on stories are triggered, because
-- deleted cascading stories_id and topics_id fields take care of deletes.
-- TODO: probably get rid of it at some point as it's no longer so congested
CREATE TABLE snap.live_stories
(
    snap_live_stories_id  BIGSERIAL  NOT NULL,
    topics_id             BIGINT     NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    topic_stories_id      BIGINT     NOT NULL,
    stories_id            BIGINT     NOT NULL,
    media_id              BIGINT     NOT NULL,
    url                   TEXT       NOT NULL,
    guid                  TEXT       NOT NULL,
    title                 TEXT       NOT NULL,
    normalized_title_hash UUID       NULL,
    description           TEXT       NULL,
    publish_date          TIMESTAMP  NULL,
    collect_date          TIMESTAMP  NOT NULL,
    full_text_rss         BOOLEAN    NOT NULL DEFAULT 'f',

    -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
    language              VARCHAR(3) null,

    PRIMARY KEY (snap_live_stories_id, topics_id),

    FOREIGN KEY (topics_id, topic_stories_id)
        REFERENCES topic_stories (topics_id, topic_stories_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snap.live_stories', 'topics_id');

CREATE INDEX snap_live_stories_topics_id
    ON snap.live_stories (topics_id);

CREATE UNIQUE INDEX snap_live_stories_topics_id_stories_id
    on snap.live_stories (topics_id, stories_id);

CREATE INDEX snap_live_stories_stories_id
    ON snap.live_stories (stories_id);

CREATE INDEX snap_live_stories_topic_stories_id
    ON snap.live_stories (topic_stories_id);

CREATE INDEX snap_live_stories_topics_id_media_id_publish_day_ntitle_hash
    ON snap.live_stories (
                          topics_id,
                          media_id,
                          date_trunc('day', publish_date),
                          normalized_title_hash
        );


CREATE OR REPLACE FUNCTION insert_live_story() RETURNS TRIGGER AS
$$

DECLARE
    story RECORD;

BEGIN

    SELECT *
    INTO story
    FROM stories
    WHERE stories_id = NEW.stories_id;

    INSERT INTO snap.live_stories (topics_id,
                                   topic_stories_id,
                                   stories_id,
                                   media_id,
                                   url,
                                   guid,
                                   title,
                                   normalized_title_hash,
                                   description,
                                   publish_date,
                                   collect_date,
                                   full_text_rss,
                                   language)
    SELECT NEW.topics_id,
           NEW.topic_stories_id,
           NEW.stories_id,
           story.media_id,
           story.url,
           story.guid,
           story.title,
           story.normalized_title_hash,
           story.description,
           story.publish_date,
           story.collect_date,
           story.full_text_rss,
           story.language
    FROM topic_stories
    WHERE topic_stories.stories_id = NEW.stories_id
      AND topic_stories.topics_id = NEW.topics_id;

    RETURN NEW;

END;

$$ LANGUAGE plpgsql;

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('insert_live_story()');


SELECT run_on_shards_or_raise('topic_stories', $cmd$

    CREATE TRIGGER topic_stories_insert_live_story
        AFTER INSERT
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE insert_live_story();

    $cmd$);


CREATE OR REPLACE FUNCTION update_live_story() RETURNS TRIGGER AS
$$

BEGIN

    UPDATE snap.live_stories
    SET media_id              = NEW.media_id,
        url                   = NEW.url,
        guid                  = NEW.guid,
        title                 = NEW.title,
        normalized_title_hash = NEW.normalized_title_hash,
        description           = NEW.description,
        publish_date          = NEW.publish_date,
        collect_date          = NEW.collect_date,
        full_text_rss         = NEW.full_text_rss,
        language              = NEW.language
    WHERE stories_id = NEW.stories_id;

    RETURN NEW;

END;

$$ LANGUAGE plpgsql;

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('update_live_story()');


SELECT run_on_shards_or_raise('stories', $cmd$

    CREATE TRIGGER stories_update_live_story
        AFTER UPDATE
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE update_live_story();

    $cmd$);


--
-- Snapshot word2vec models
--
CREATE TABLE snap.word2vec_models
(
    snap_word2vec_models_id BIGSERIAL NOT NULL,
    topics_id               BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    snapshots_id            BIGINT    NOT NULL,
    creation_date           TIMESTAMP NOT NULL DEFAULT NOW(),
    raw_data                BYTEA     NOT NULL,

    PRIMARY KEY (snap_word2vec_models_id, topics_id),

    FOREIGN KEY (topics_id, snapshots_id)
        REFERENCES snapshots (topics_id, snapshots_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snap.word2vec_models', 'topics_id');

-- We'll need to find the latest word2vec model
CREATE INDEX snap_word2vec_models_topics_id_snapshots_id_creation_date
    ON snap.word2vec_models (topics_id, snapshots_id, creation_date);



CREATE TABLE processed_stories
(
    processed_stories_id BIGSERIAL NOT NULL,
    stories_id           BIGINT    NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,

    PRIMARY KEY (processed_stories_id, stories_id)
);

SELECT create_distributed_table('processed_stories', 'stories_id');

CREATE INDEX processed_stories_stories_id
    ON processed_stories (stories_id);


SELECT run_on_shards_or_raise('processed_stories', $cmd$

    CREATE TRIGGER processed_stories_insert_solr_import_story
        AFTER INSERT OR UPDATE OR DELETE
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE insert_solr_import_story();

    $cmd$);


-- list of stories that have been scraped and the source
CREATE TABLE scraped_stories
(
    scraped_stories_id BIGSERIAL NOT NULL,
    stories_id         BIGINT    NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    import_module      TEXT      NOT NULL,

    PRIMARY KEY (scraped_stories_id, stories_id)
);

SELECT create_distributed_table('scraped_stories', 'stories_id');

CREATE INDEX scraped_stories_stories_id ON scraped_stories (stories_id);


-- dates on which feeds have been scraped with MediaWords::ImportStories and
-- the module used for scraping
CREATE TABLE scraped_feeds
(
    scraped_feeds_id BIGSERIAL PRIMARY KEY,
    feeds_id         BIGINT    NOT NULL REFERENCES feeds (feeds_id) ON DELETE CASCADE,
    scrape_date      TIMESTAMP NOT NULL DEFAULT NOW(),
    import_module    TEXT      NOT NULL
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('scraped_feeds');

CREATE INDEX scraped_feeds_feeds_id ON scraped_feeds (feeds_id);


CREATE VIEW feedly_unscraped_feeds AS
SELECT f.*
FROM feeds AS f
         LEFT JOIN scraped_feeds AS sf
                   ON f.feeds_id = sf.feeds_id
                       AND sf.import_module = 'MediaWords::ImportStories::Feedly'
WHERE f.type = 'syndicated'
  AND f.active = 't'
  AND sf.feeds_id IS NULL
;


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
         SELECT COALESCE(SUM(num_stories), 0) AS solr_stories
         FROM solr_imports
         WHERE import_date > now() - interval '1 day'
     ) AS si;


--
-- Authentication
--

-- List of users
-- noinspection SqlResolve @ object-type/"CITEXT"
CREATE TABLE auth_users
(
    auth_users_id                   BIGSERIAL PRIMARY KEY,

    -- Emails are case-insensitive
    email                           CITEXT    NOT NULL,

    -- Salted hash of a password
    password_hash                   TEXT      NOT NULL
        CONSTRAINT password_hash_sha256 CHECK (LENGTH(password_hash) = 137),

    full_name                       TEXT      NOT NULL,
    notes                           TEXT      NULL,

    active                          BOOLEAN   NOT NULL DEFAULT true,

    -- Salted hash of a password reset token (with Crypt::SaltedHash, algorithm => 'SHA-256',
    -- salt_len=>64) or NULL
    password_reset_token_hash       TEXT      NULL
        CONSTRAINT password_reset_token_hash_sha256
            CHECK (LENGTH(password_reset_token_hash) = 137 OR password_reset_token_hash IS NULL),

    -- Timestamp of the last unsuccessful attempt to log in; used for delaying successive
    -- attempts in order to prevent brute-force attacks
    last_unsuccessful_login_attempt TIMESTAMP NOT NULL DEFAULT TIMESTAMP 'epoch',

    created_date                    TIMESTAMP NOT NULL DEFAULT NOW(),

    -- Whether or not the user has consented to the privacy policy
    has_consented                   BOOLEAN   NOT NULL DEFAULT false
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('auth_users');

CREATE UNIQUE INDEX auth_users_email ON auth_users (email);

CREATE UNIQUE INDEX auth_users_password_reset_token_hash ON auth_users (password_reset_token_hash);

-- Used by daily stats script
CREATE INDEX auth_users_created_day ON auth_users (date_trunc('day', created_date));


-- Generate random API key
CREATE OR REPLACE FUNCTION generate_api_key() RETURNS VARCHAR(64)
    LANGUAGE plpgsql AS
$$
DECLARE
    api_key VARCHAR(64);
BEGIN
    -- pgcrypto's functions are being referred with public schema prefix to make pg_upgrade work
    -- noinspection SqlResolve
    SELECT encode(public.digest(public.gen_random_bytes(256), 'sha256'), 'hex') INTO api_key;
    RETURN api_key;
END;
$$;

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('generate_api_key()');


CREATE TABLE auth_user_api_keys
(
    auth_user_api_keys_id BIGSERIAL PRIMARY KEY,
    auth_users_id         BIGINT      NOT NULL REFERENCES auth_users (auth_users_id) ON DELETE CASCADE,

    -- API key
    -- (must be 64 bytes in order to prevent someone from resetting it to empty string somehow)
    api_key               VARCHAR(64) NOT NULL
        DEFAULT generate_api_key()
        CONSTRAINT api_key_64_characters
            CHECK ( length(api_key) = 64 ),

    -- If set, API key is limited to only this IP address
    ip_address            INET        NULL
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('auth_user_api_keys');

CREATE UNIQUE INDEX auth_user_api_keys_api_key
    ON auth_user_api_keys (api_key);

CREATE UNIQUE INDEX auth_user_api_keys_api_key_ip_address
    ON auth_user_api_keys (api_key, ip_address);


-- Autogenerate non-IP limited API key
CREATE OR REPLACE FUNCTION auth_user_api_keys_add_non_ip_limited_api_key() RETURNS trigger AS
$$
BEGIN

    INSERT INTO auth_user_api_keys (auth_users_id, api_key, ip_address)
    VALUES (NEW.auth_users_id,
            DEFAULT, -- Autogenerated API key
            NULL -- Not limited by IP address
           );
    RETURN NULL;

END;
$$ LANGUAGE 'plpgsql';

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('auth_user_api_keys_add_non_ip_limited_api_key()');


SELECT run_on_shards_or_raise('auth_users', $cmd$

    CREATE TRIGGER auth_user_api_keys_add_non_ip_limited_api_key
        AFTER INSERT
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE auth_user_api_keys_add_non_ip_limited_api_key();

    $cmd$);


-- List of roles the users can perform
CREATE TABLE auth_roles
(
    auth_roles_id BIGSERIAL PRIMARY KEY,
    role          TEXT NOT NULL,
    description   TEXT NOT NULL,

    CHECK (role NOT LIKE '% %')
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('auth_roles');

CREATE UNIQUE INDEX auth_roles_role ON auth_roles (role);


-- Map of user IDs and roles that are allowed to each of the user
CREATE TABLE auth_users_roles_map
(
    auth_users_roles_map_id BIGSERIAL PRIMARY KEY,
    auth_users_id           BIGINT NOT NULL
        REFERENCES auth_users (auth_users_id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE,
    auth_roles_id           BIGINT NOT NULL
        REFERENCES auth_roles (auth_roles_id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('auth_users_roles_map');

CREATE UNIQUE INDEX auth_users_roles_map_auth_users_id_auth_roles_id
    ON auth_users_roles_map (auth_users_id, auth_roles_id);


-- Authentication roles (keep in sync with MediaWords::DBI::Auth::Roles)
INSERT INTO auth_roles (role, description)
VALUES ('admin', 'Do everything, including editing users.'),
       ('admin-readonly', 'Read access to admin interface.'),
       ('media-edit', 'Add / edit media; includes feeds.'),
       ('stories-edit', 'Add / edit stories.'),
       ('tm', 'Topic mapper; includes media and story editing'),
       ('tm-readonly', 'Topic mapper; excludes media and story editing');


--
-- User request daily counts
--
-- noinspection SqlResolve @ object-type/"CITEXT"
CREATE TABLE auth_user_request_daily_counts
(

    auth_user_request_daily_counts_id BIGSERIAL NOT NULL,

    -- User's email (does *not* reference auth_users.email because the user
    -- might be deleted)
    email                             CITEXT    NOT NULL,

    -- Day (request timestamp, date_truncated to a day)
    day                               DATE      NOT NULL,

    -- Number of requests
    requests_count                    BIGINT    NOT NULL,

    -- Number of requested items
    requested_items_count             BIGINT    NOT NULL,

    PRIMARY KEY (auth_user_request_daily_counts_id, email)

);

-- Kinda grows big so distributed
SELECT create_distributed_table('auth_user_request_daily_counts', 'email');

-- Single index to enforce upsert uniqueness
CREATE UNIQUE INDEX auth_user_request_daily_counts_email_day
    ON auth_user_request_daily_counts (email, day);


-- User limits for logged + throttled controller actions
CREATE TABLE auth_user_limits
(
    auth_user_limits_id          BIGSERIAL PRIMARY KEY,

    auth_users_id                BIGINT NOT NULL REFERENCES auth_users (auth_users_id)
        ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE,

    -- Request limit (0 or belonging to 'admin' / 'admin-readonly' group = no
    -- limit)
    weekly_requests_limit        BIGINT NOT NULL DEFAULT 10000,

    -- Requested items (stories) limit (0 or belonging to 'admin' /
    -- 'admin-readonly' group = no limit)
    weekly_requested_items_limit BIGINT NOT NULL DEFAULT 100000,

    max_topic_stories            BIGINT NOT NULL DEFAULT 100000
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('auth_user_limits');

CREATE UNIQUE INDEX auth_user_limits_auth_users_id ON auth_user_limits (auth_users_id);


-- Set the default limits for newly created users
CREATE OR REPLACE FUNCTION auth_users_set_default_limits() RETURNS trigger AS
$$
BEGIN

    INSERT INTO auth_user_limits (auth_users_id) VALUES (NEW.auth_users_id);
    RETURN NULL;

END;
$$ LANGUAGE 'plpgsql';

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('auth_users_set_default_limits()');


SELECT run_on_shards_or_raise('auth_users', $cmd$

    CREATE TRIGGER auth_users_set_default_limits
        AFTER INSERT
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE auth_users_set_default_limits();

    $cmd$);


CREATE TABLE auth_users_tag_sets_permissions
(
    auth_users_tag_sets_permissions_id BIGSERIAL PRIMARY KEY,
    auth_users_id                      BIGINT  NOT NULL REFERENCES auth_users (auth_users_id) ON DELETE CASCADE,
    tag_sets_id                        BIGINT  NOT NULL REFERENCES tag_sets (tag_sets_id),
    apply_tags                         BOOLEAN NOT NULL,
    create_tags                        BOOLEAN NOT NULL,
    edit_tag_set_descriptors           BOOLEAN NOT NULL,
    edit_tag_descriptors               BOOLEAN NOT NULL
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('auth_users_tag_sets_permissions');

CREATE UNIQUE INDEX auth_users_tag_sets_permissions_auth_user_tag_set
    ON auth_users_tag_sets_permissions (auth_users_id, tag_sets_id);

CREATE INDEX auth_users_tag_sets_permissions_auth_user
    ON auth_users_tag_sets_permissions (auth_users_id);

CREATE INDEX auth_users_tag_sets_permissions_tag_sets
    ON auth_users_tag_sets_permissions (tag_sets_id);


--
-- Activity log
--

-- noinspection SqlResolve @ object-type/"CITEXT"
CREATE TABLE activities
(
    activities_id   BIGSERIAL PRIMARY KEY,

    -- Activity's name (e.g. "tm_snapshot_topic")
    name            TEXT      NOT NULL
        CONSTRAINT activities_name_can_not_contain_spaces CHECK (name NOT LIKE '% %'),

    -- When did the activity happen
    creation_date   TIMESTAMP NOT NULL DEFAULT LOCALTIMESTAMP,

    -- User that executed the activity, either:
    --     * user's email from "auth_users.email" (e.g. "foo@bar.baz.com", or
    --     * username that initiated the action (e.g. "system:foo")
    -- (store user's email instead of ID in case the user gets deleted)
    user_identifier CITEXT    NOT NULL,

    -- Indexed ID of the object that was modified in some way by the activity
    object_id       BIGINT    NULL,

    -- User-provided reason explaining why the activity was made
    reason          TEXT      NULL,

    -- Other free-form data describing the action in the JSON format
    -- (e.g.: '{ "field": "name", "old_value": "Foo.", "new_value": "Bar." }')
    description     JSONB     NOT NULL DEFAULT '{}'
);

-- Not a reference table (because not referenced), not a distributed table (because too small)

CREATE INDEX activities_name ON activities (name);

CREATE INDEX activities_creation_date ON activities (creation_date);

CREATE INDEX activities_user_identifier ON activities (user_identifier);

CREATE INDEX activities_object_id ON activities (object_id);


CREATE OR REPLACE FUNCTION story_is_english_and_has_sentences(param_stories_id BIGINT)
    RETURNS BOOLEAN AS
$$

DECLARE
    story RECORD;

BEGIN

    SELECT stories_id, media_id, language INTO story from stories where stories_id = param_stories_id;

    IF NOT (story.language = 'en' OR story.language IS NULL) THEN
        RETURN FALSE;

    ELSEIF NOT EXISTS(SELECT 1 FROM story_sentences WHERE stories_id = param_stories_id) THEN
        RETURN FALSE;

    END IF;

    RETURN TRUE;

END;

$$ LANGUAGE 'plpgsql';


-- Copy of "feeds" table from yesterday; used for generating reports for rescraping efforts
CREATE TABLE feeds_from_yesterday
(
    feeds_from_yesterday_id BIGSERIAL PRIMARY KEY,
    feeds_id                BIGINT    NOT NULL,
    media_id                BIGINT    NOT NULL,
    name                    TEXT      NOT NULL,
    url                     TEXT      NOT NULL,
    type                    feed_type NOT NULL,
    active                  BOOLEAN   NOT NULL
);

-- Not a reference table (because not referenced), not a distributed table (because too small)

CREATE INDEX feeds_from_yesterday_feeds_id ON feeds_from_yesterday (feeds_id);
CREATE INDEX feeds_from_yesterday_media_id ON feeds_from_yesterday (media_id);
CREATE INDEX feeds_from_yesterday_name ON feeds_from_yesterday (name);
CREATE UNIQUE INDEX feeds_from_yesterday_url ON feeds_from_yesterday (url, media_id);


--
-- Update "feeds_from_yesterday" with a new set of feeds
--
CREATE OR REPLACE FUNCTION update_feeds_from_yesterday() RETURNS VOID AS
$$

BEGIN

    -- noinspection SqlWithoutWhere
    DELETE FROM feeds_from_yesterday;
    INSERT INTO feeds_from_yesterday (feeds_id, media_id, name, url, type, active)
    SELECT feeds_id, media_id, name, url, type, active
    FROM feeds;

END;

$$ LANGUAGE 'plpgsql';


--
-- Print out a diff between "feeds" and "feeds_from_yesterday"
--
CREATE OR REPLACE FUNCTION rescraping_changes() RETURNS VOID AS
$$

DECLARE
    r_count RECORD;
    r_media RECORD;
    r_feed  RECORD;

BEGIN

    -- Check if media exists
    IF NOT EXISTS(
            SELECT 1
            FROM feeds_from_yesterday
        ) THEN
        RAISE EXCEPTION '"feeds_from_yesterday" table is empty.';
    END IF;

    -- Fill temp. tables with changes to print out later
    CREATE TEMPORARY TABLE rescraping_changes_media ON COMMIT DROP AS
    SELECT *
    FROM media
    WHERE media_id IN (
        SELECT DISTINCT media_id
        FROM (
                 -- Don't compare "name" because it's insignificant
                 (
                     SELECT feeds_id, media_id, type, active, url
                     FROM feeds_from_yesterday
                         EXCEPT
                     SELECT feeds_id, media_id, type, active, url
                     FROM feeds
                 )
                 UNION ALL
                 (
                     SELECT feeds_id, media_id, type, active, url
                     FROM feeds
                         EXCEPT
                     SELECT feeds_id, media_id, type, active, url
                     FROM feeds_from_yesterday
                 )
             ) AS modified_feeds
    );

    CREATE TEMPORARY TABLE rescraping_changes_feeds_added ON COMMIT DROP AS
    SELECT *
    FROM feeds
    WHERE media_id IN (
        SELECT media_id
        FROM rescraping_changes_media
    )
      AND feeds_id NOT IN (
        SELECT feeds_id
        FROM feeds_from_yesterday
    );

    CREATE TEMPORARY TABLE rescraping_changes_feeds_deleted ON COMMIT DROP AS
    SELECT *
    FROM feeds_from_yesterday
    WHERE media_id IN (
        SELECT media_id
        FROM rescraping_changes_media
    )
      AND feeds_id NOT IN (
        SELECT feeds_id
        FROM feeds
    );

    CREATE TEMPORARY TABLE rescraping_changes_feeds_modified ON COMMIT DROP AS
    SELECT feeds_before.media_id,
           feeds_before.feeds_id,

           feeds_before.name   AS before_name,
           feeds_before.url    AS before_url,
           feeds_before.type   AS before_type,
           feeds_before.active AS before_active,

           feeds_after.name    AS after_name,
           feeds_after.url     AS after_url,
           feeds_after.type    AS after_type,
           feeds_after.active  AS after_active

    FROM feeds_from_yesterday AS feeds_before
             INNER JOIN feeds AS feeds_after ON (
            feeds_before.feeds_id = feeds_after.feeds_id
            AND (
                -- Don't compare "name" because it's insignificant
                    feeds_before.url != feeds_after.url
                    OR feeds_before.type != feeds_after.type
                    OR feeds_before.active != feeds_after.active
                )
        )

    WHERE feeds_before.media_id IN (
        SELECT media_id
        FROM rescraping_changes_media
    );

    -- Print out changes
    RAISE NOTICE 'Changes between "feeds" and "feeds_from_yesterday":';
    RAISE NOTICE '';

    SELECT COUNT(1) AS media_count INTO r_count FROM rescraping_changes_media;
    RAISE NOTICE '* Modified media: %', r_count.media_count;
    SELECT COUNT(1) AS feeds_added_count INTO r_count FROM rescraping_changes_feeds_added;
    RAISE NOTICE '* Added feeds: %', r_count.feeds_added_count;
    SELECT COUNT(1) AS feeds_deleted_count INTO r_count FROM rescraping_changes_feeds_deleted;
    RAISE NOTICE '* Deleted feeds: %', r_count.feeds_deleted_count;
    SELECT COUNT(1) AS feeds_modified_count INTO r_count FROM rescraping_changes_feeds_modified;
    RAISE NOTICE '* Modified feeds: %', r_count.feeds_modified_count;
    RAISE NOTICE '';

    FOR r_media IN
        SELECT *,

               -- Prioritize US MSM media
               EXISTS(
                       SELECT 1
                       FROM tags AS tags
                                INNER JOIN media_tags_map
                                           ON tags.tags_id = media_tags_map.tags_id
                                INNER JOIN tag_sets
                                           ON tags.tag_sets_id = tag_sets.tag_sets_id
                       WHERE media_tags_map.media_id = rescraping_changes_media.media_id
                         AND tag_sets.name = 'collection'
                         AND tags.tag = 'ap_english_us_top25_20100110'
                   ) AS belongs_to_us_msm,

               -- Prioritize media with "show_on_media"
               EXISTS(
                       SELECT 1
                       FROM tags AS tags
                                INNER JOIN media_tags_map
                                           ON tags.tags_id = media_tags_map.tags_id
                                INNER JOIN tag_sets
                                           ON tags.tag_sets_id = tag_sets.tag_sets_id
                       WHERE media_tags_map.media_id = rescraping_changes_media.media_id
                         AND (
                               tag_sets.show_on_media
                               OR tags.show_on_media
                           )
                   ) AS show_on_media

        FROM rescraping_changes_media

        ORDER BY belongs_to_us_msm DESC,
                 show_on_media DESC,
                 media_id
        LOOP
            RAISE NOTICE 'MODIFIED media: media_id=%, name="%", url="%"',
                r_media.media_id,
                r_media.name,
                r_media.url;

            FOR r_feed IN
                SELECT *
                FROM rescraping_changes_feeds_added
                WHERE media_id = r_media.media_id
                ORDER BY feeds_id
                LOOP
                    RAISE NOTICE '    ADDED feed: feeds_id=%, type=%, active=%, name="%", url="%"',
                        r_feed.feeds_id,
                        r_feed.type,
                        r_feed.active,
                        r_feed.name,
                        r_feed.url;
                END LOOP;

            -- Feeds shouldn't get deleted but we're checking anyways
            FOR r_feed IN
                SELECT *
                FROM rescraping_changes_feeds_deleted
                WHERE media_id = r_media.media_id
                ORDER BY feeds_id
                LOOP
                    RAISE NOTICE '    DELETED feed: feeds_id=%, type=%, active=%, name="%", url="%"',
                        r_feed.feeds_id,
                        r_feed.type,
                        r_feed.active,
                        r_feed.name,
                        r_feed.url;
                END LOOP;

            FOR r_feed IN
                SELECT *
                FROM rescraping_changes_feeds_modified
                WHERE media_id = r_media.media_id
                ORDER BY feeds_id
                LOOP
                    RAISE NOTICE '    MODIFIED feed: feeds_id=%', r_feed.feeds_id;
                    RAISE NOTICE '        BEFORE: type=%, active=%, name="%", url="%"',
                        r_feed.before_type,
                        r_feed.before_active,
                        r_feed.before_name,
                        r_feed.before_url;
                    RAISE NOTICE '        AFTER:  type=%, active=%, name="%", url="%"',
                        r_feed.after_type,
                        r_feed.after_active,
                        r_feed.after_name,
                        r_feed.after_url;
                END LOOP;

            RAISE NOTICE '';

        END LOOP;

END;

$$ LANGUAGE 'plpgsql';


-- implements link_id as documented in the topics api spec
CREATE TABLE api_links
(
    api_links_id     BIGSERIAL PRIMARY KEY,
    path             TEXT   NOT NULL,
    params           JSONB  NOT NULL,
    next_link_id     BIGINT NULL
        REFERENCES api_links (api_links_id) ON DELETE SET NULL DEFERRABLE,
    previous_link_id BIGINT NULL
        REFERENCES api_links (api_links_id) ON DELETE SET NULL DEFERRABLE
);

-- Not a reference table (because not referenced), not a distributed table (because too small)

CREATE UNIQUE INDEX api_links_path_params ON api_links (path, params);


-- keep track of performance of the topic spider
CREATE TABLE topic_spider_metrics
(
    topic_spider_metrics_id BIGSERIAL NOT NULL,
    topics_id               BIGINT REFERENCES topics (topics_id) ON DELETE CASCADE,
    iteration               BIGINT    NOT NULL,
    links_processed         BIGINT    NOT NULL,
    elapsed_time            BIGINT    NOT NULL,
    processed_date          TIMESTAMP NOT NULL DEFAULT NOW(),

    PRIMARY KEY (topic_spider_metrics_id, topics_id)
);

SELECT create_distributed_table('topic_spider_metrics', 'topics_id');

CREATE INDEX topic_spider_metrics_topics_id ON topic_spider_metrics (topics_id);

CREATE INDEX topic_spider_metrics_processed_date ON topic_spider_metrics (processed_date);


CREATE TYPE topic_permission AS ENUM (
    'read', 'write', 'admin'
    );

-- per user permissions for topics
CREATE TABLE topic_permissions
(
    topic_permissions_id BIGSERIAL        NOT NULL,
    topics_id            BIGINT           NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    auth_users_id        BIGINT           NOT NULL,
    permission           topic_permission NOT NULL,

    PRIMARY KEY (topic_permissions_id, topics_id)
);

SELECT create_distributed_table('topic_permissions', 'topics_id');

ALTER TABLE topic_permissions
    ADD CONSTRAINT topic_permissions_auth_users_id_fkey
        FOREIGN KEY (auth_users_id) REFERENCES auth_users (auth_users_id) ON DELETE CASCADE;

CREATE INDEX topic_permissions_topics_id
    ON topic_permissions (topics_id);

CREATE UNIQUE INDEX topic_permissions_topics_id_auth_users_id
    ON topic_permissions (topics_id, auth_users_id);


-- topics table with auth_users_id and user_permission fields that indicate the permission level for
-- the user for the topic.  permissions in decreasing order are admin, write, read, none.  users with
-- the admin role have admin permission for every topic. users with admin-readonly role have at least
-- read access to every topic.  all users have read access to every is_public topic.  otherwise, the
-- topic_permissions table is used, with 'none' for no topic_permission.
CREATE OR REPLACE VIEW topics_with_user_permission AS
WITH admin_users AS (
    SELECT m.auth_users_id
    FROM auth_roles r
             JOIN auth_users_roles_map AS m USING (auth_roles_id)
    WHERE r.role = 'admin'
),

     read_admin_users AS (
         SELECT m.auth_users_id
         FROM auth_roles AS r
                  JOIN auth_users_roles_map AS m USING (auth_roles_id)
         WHERE r.role = 'admin-readonly'
     )
SELECT t.*,
       u.auth_users_id,
       CASE
           WHEN (EXISTS(
                   SELECT 1
                   FROM admin_users AS a
                   WHERE a.auth_users_id = u.auth_users_id
               )) THEN 'admin'
           WHEN (tp.permission IS NOT NULL) THEN tp.permission::text
           WHEN (t.is_public) THEN 'read'
           WHEN (EXISTS(
                   SELECT 1
                   FROM read_admin_users AS a
                   WHERE a.auth_users_id = u.auth_users_id
               )) THEN 'read'
           ELSE 'none'
           END AS user_permission
FROM topics AS t
         JOIN auth_users AS u ON (true)
         LEFT JOIN topic_permissions AS tp USING (topics_id, auth_users_id)
;


-- list of tweet counts and fetching statuses for each day of each topic
CREATE TABLE topic_post_days
(
    topic_post_days_id    BIGSERIAL NOT NULL,
    topics_id             BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    topic_seed_queries_id BIGINT    NOT NULL,
    day                   DATE      NOT NULL,
    num_posts_stored      BIGINT    NOT NULL,
    num_posts_fetched     BIGINT    NOT NULL,
    posts_fetched         BOOLEAN   NOT NULL DEFAULT 'f',

    PRIMARY KEY (topic_post_days_id, topics_id),

    FOREIGN KEY (topics_id, topic_seed_queries_id)
        REFERENCES topic_seed_queries (topics_id, topic_seed_queries_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('topic_post_days', 'topics_id');

CREATE INDEX topic_post_days_topic_seed_queries_id_day
    ON topic_post_days (topic_seed_queries_id, day);


-- list of posts associated with a given topic
CREATE TABLE topic_posts
(
    topic_posts_id     BIGSERIAL NOT NULL,
    topics_id          BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    topic_post_days_id BIGINT    NOT NULL,
    data               JSONB     NOT NULL,
    post_id            TEXT      NOT NULL,
    content            TEXT      NOT NULL,
    publish_date       TIMESTAMP NOT NULL,
    author             TEXT      NOT NULL,
    channel            TEXT      NOT NULL,
    url                TEXT      NULL,

    PRIMARY KEY (topic_posts_id, topics_id),

    FOREIGN KEY (topics_id, topic_post_days_id)
        REFERENCES topic_post_days (topics_id, topic_post_days_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('topic_posts', 'topics_id');

CREATE UNIQUE INDEX topic_posts_topics_id_topic_post_days_id_post_id
    ON topic_posts (topics_id, topic_post_days_id, post_id);

CREATE INDEX topic_posts_topic_post_days_id_author
    ON topic_posts (topic_post_days_id, author);

CREATE INDEX topic_posts_topic_post_days_id_channel
    ON topic_posts (topic_post_days_id, channel);


-- urls parsed from topic tweets and imported into topic_seed_urls
CREATE TABLE topic_post_urls
(
    topic_post_urls_id BIGSERIAL NOT NULL,
    topics_id          BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    topic_posts_id     BIGINT    NOT NULL,
    url                TEXT      NOT NULL,

    PRIMARY KEY (topic_post_urls_id, topics_id),

    FOREIGN KEY (topics_id, topic_posts_id)
        REFERENCES topic_posts (topics_id, topic_posts_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('topic_post_urls', 'topics_id');

CREATE INDEX topic_post_urls_url
    ON topic_post_urls (url);

CREATE UNIQUE INDEX topic_post_urls_topics_id_topic_posts_id_url
    ON topic_post_urls (topics_id, topic_posts_id, url);


CREATE TABLE topic_seed_urls
(
    topic_seed_urls_id    BIGSERIAL NOT NULL,
    topics_id             BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    url                   TEXT      NULL,
    source                TEXT      NULL,
    stories_id            BIGINT    NULL,
    processed             BOOLEAN   NOT NULL DEFAULT 'f',
    assume_match          BOOLEAN   NOT NULL DEFAULT 'f',
    content               TEXT      NULL,
    guid                  TEXT      NULL,
    title                 TEXT      NULL,
    publish_date          TEXT      NULL,
    topic_seed_queries_id BIGINT    NULL,
    topic_post_urls_id    BIGINT    NULL,

    PRIMARY KEY (topic_seed_urls_id, topics_id),

    FOREIGN KEY (topics_id, topic_seed_queries_id)
        REFERENCES topic_seed_queries (topics_id, topic_seed_queries_id)
        ON DELETE CASCADE,

    FOREIGN KEY (topics_id, topic_post_urls_id)
        REFERENCES topic_post_urls (topics_id, topic_post_urls_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('topic_seed_urls', 'topics_id');

CREATE INDEX topic_seed_urls_topics_id
    ON topic_seed_urls (topics_id);

CREATE INDEX topic_seed_urls_url
    ON topic_seed_urls (url);

CREATE INDEX topic_seed_urls_stories_id
    ON topic_seed_urls (stories_id);

CREATE UNIQUE INDEX topic_seed_urls_topics_id_topic_post_urls_id
    ON topic_seed_urls (topics_id, topic_post_urls_id);


-- view that joins together the chain of tables from topic_seed_queries all the way through to
-- topic_stories, so that you get back a topics_id, topic_posts_id stories_id, and topic_seed_queries_id in each
-- row to track which stories came from which posts in which seed queries
CREATE OR REPLACE VIEW topic_post_stories AS
SELECT tsq.topics_id,
       tp.topic_posts_id,
       tp.content,
       tp.publish_date,
       tp.author,
       tp.channel,
       tp.data,
       tpd.topic_seed_queries_id,
       ts.stories_id,
       tpu.url,
       tpu.topic_post_urls_id
FROM topic_seed_queries AS tsq
         INNER JOIN topic_post_days AS tpd ON
        tsq.topics_id = tpd.topics_id AND
        tsq.topic_seed_queries_id = tpd.topic_seed_queries_id
         INNER JOIN topic_posts AS tp ON
        tsq.topics_id = tp.topics_id AND
        tpd.topic_post_days_id = tp.topic_post_days_id
         INNER JOIN topic_post_urls AS tpu ON
        tsq.topics_id = tpu.topics_id AND
        tp.topic_posts_id = tpu.topic_posts_id
         INNER JOIN topic_seed_urls AS tsu ON
        tsq.topics_id = tsu.topics_id AND
        tpu.topic_post_urls_id = tsu.topic_post_urls_id
         INNER JOIN topic_stories AS ts ON
        tsq.topics_id = ts.topics_id AND
        tsu.stories_id = ts.stories_id
;


CREATE TABLE snap.timespan_posts
(
    snap_timespan_posts_id BIGSERIAL NOT NULL,
    topics_id              BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    topic_posts_id         BIGINT    NOT NULL,
    timespans_id           BIGINT    NOT NULL,

    PRIMARY KEY (snap_timespan_posts_id, topics_id),

    FOREIGN KEY (topics_id, topic_posts_id)
        REFERENCES topic_posts (topics_id, topic_posts_id)
        ON DELETE CASCADE,

    FOREIGN KEY (topics_id, timespans_id)
        REFERENCES timespans (topics_id, timespans_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('snap.timespan_posts', 'topics_id');

CREATE UNIQUE INDEX snap_timespan_posts_topics_id_timespans_id_topic_posts_id
    ON snap.timespan_posts (topics_id, timespans_id, topic_posts_id);


CREATE TABLE media_stats_weekly
(
    media_stats_weekly_id BIGSERIAL PRIMARY KEY,
    media_id              BIGINT  NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,
    stories_rank          BIGINT  NOT NULL,
    num_stories           NUMERIC NOT NULL,
    sentences_rank        BIGINT  NOT NULL,
    num_sentences         NUMERIC NOT NULL,
    stat_week             DATE    NOT NULL
);

-- Not a reference table (because not referenced), not a distributed table (because too small)

CREATE INDEX media_stats_weekly_media_id ON media_stats_weekly (media_id);

CREATE INDEX media_stats_weekly_media_id_stat_week_num_stories_num_sentences
    ON media_stats_weekly (media_id, stat_week, num_stories, num_sentences);

CREATE INDEX media_stats_weekly_stories_rank
    ON media_stats_weekly (stories_rank);

CREATE INDEX media_stats_weekly_sentences_rank
    ON media_stats_weekly (sentences_rank);


CREATE TABLE media_expected_volume
(
    media_expected_volume_id BIGSERIAL PRIMARY KEY,
    media_id                 BIGINT  NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,
    start_date               DATE    NOT NULL,
    end_date                 DATE    NOT NULL,
    expected_stories         NUMERIC NOT NULL,
    expected_sentences       NUMERIC NOT NULL
);

-- Not a reference table (because not referenced), not a distributed table (because too small)

CREATE INDEX media_expected_volume_media_id ON media_expected_volume (media_id);


CREATE TABLE media_coverage_gaps
(
    media_coverage_gaps_id BIGSERIAL NOT NULL,
    media_id               BIGINT    NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,
    stat_week              DATE      NOT NULL,
    num_stories            NUMERIC   NOT NULL,
    expected_stories       NUMERIC   NOT NULL,
    num_sentences          NUMERIC   NOT NULL,
    expected_sentences     NUMERIC   NOT NULL,

    PRIMARY KEY (media_coverage_gaps_id, media_id)
);

SELECT create_distributed_table('media_coverage_gaps', 'media_id');

CREATE INDEX media_coverage_gaps_media_id ON media_coverage_gaps (media_id);


CREATE TABLE media_health
(
    media_health_id    BIGSERIAL PRIMARY KEY,
    media_id           BIGINT  NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,
    num_stories        NUMERIC NOT NULL,
    num_stories_y      NUMERIC NOT NULL,
    num_stories_w      NUMERIC NOT NULL,
    num_stories_90     NUMERIC NOT NULL,
    num_sentences      NUMERIC NOT NULL,
    num_sentences_y    NUMERIC NOT NULL,
    num_sentences_w    NUMERIC NOT NULL,
    num_sentences_90   NUMERIC NOT NULL,
    is_healthy         BOOLEAN NOT NULL DEFAULT 'f',
    has_active_feed    BOOLEAN NOT NULL DEFAULT 't',
    start_date         DATE    NOT NULL,
    end_date           DATE    NOT NULL,
    expected_sentences NUMERIC NOT NULL,
    expected_stories   NUMERIC NOT NULL,
    coverage_gaps      BIGINT  NOT NULL
);

-- Not a reference table (because not referenced), not a distributed table (because too small)

CREATE INDEX media_health_media_id ON media_health (media_id);

CREATE INDEX media_health_is_healthy ON media_health (is_healthy);


CREATE TYPE media_suggestions_status AS ENUM (
    'pending',
    'approved',
    'rejected'
    );

CREATE TABLE media_suggestions
(
    media_suggestions_id BIGSERIAL PRIMARY KEY,
    name                 TEXT                     NULL,
    url                  TEXT                     NOT NULL,
    feed_url             TEXT                     NULL,
    reason               TEXT                     NULL,
    auth_users_id        BIGINT                   REFERENCES auth_users (auth_users_id) ON DELETE SET NULL,
    mark_auth_users_id   BIGINT                   REFERENCES auth_users (auth_users_id) ON DELETE SET NULL,
    date_submitted       TIMESTAMP                NOT NULL DEFAULT NOW(),
    media_id             BIGINT                   REFERENCES media (media_id) ON DELETE SET NULL,
    date_marked          TIMESTAMP                NOT NULL DEFAULT NOW(),
    mark_reason          TEXT                     NULL,
    status               media_suggestions_status NOT NULL DEFAULT 'pending',

    CONSTRAINT media_suggestions_media_id CHECK (
        (status IN ('pending', 'rejected')) OR (media_id IS NOT NULL)
        )
);

-- Not a reference table (because not referenced), not a distributed table (because too small)

CREATE INDEX media_suggestions_date ON media_suggestions (date_submitted);


CREATE TABLE media_suggestions_tags_map
(
    media_suggestions_tags_map_id BIGSERIAL PRIMARY KEY,
    media_suggestions_id          BIGINT REFERENCES media_suggestions (media_suggestions_id) ON DELETE CASCADE,
    tags_id                       BIGINT REFERENCES tags (tags_id) ON DELETE CASCADE
);

-- Not a reference table (because not referenced), not a distributed table (because too small)

CREATE INDEX media_suggestions_tags_map_media_suggestions_id
    ON media_suggestions_tags_map (media_suggestions_id);

CREATE INDEX media_suggestions_tags_map_tags_id
    ON media_suggestions_tags_map (tags_id);


-- keep track of basic high level stats for mediacloud for access through api
CREATE TABLE mediacloud_stats
(
    mediacloud_stats_id  BIGSERIAL PRIMARY KEY,
    stats_date           DATE   NOT NULL DEFAULT NOW(),
    daily_downloads      BIGINT NOT NULL,
    daily_stories        BIGINT NOT NULL,
    active_crawled_media BIGINT NOT NULL,
    active_crawled_feeds BIGINT NOT NULL,
    total_stories        BIGINT NOT NULL,
    total_downloads      BIGINT NOT NULL,
    total_sentences      BIGINT NOT NULL
);

-- Not a reference table (because not referenced), not a distributed table (because too small)


-- job states as implemented in mediawords.job.StatefulJobBroker
CREATE TABLE job_states
(
    job_states_id BIGSERIAL NOT NULL,

    --MediaWords::Job::* class implementing the job
    class         TEXT      NOT NULL,

    -- short class specific state
    state         TEXT      NOT NULL,

    -- optional longer message describing the state, such as a stack trace for an error
    message       TEXT      NULL,

    -- last time this job state was updated
    last_updated  TIMESTAMP NOT NULL DEFAULT NOW(),

    -- details about the job
    args          JSONB     NOT NULL,
    priority      TEXT      NOT NULL,

    -- the hostname and process_id of the running process
    hostname      TEXT      NOT NULL,
    process_id    BIGINT    NOT NULL,

    PRIMARY KEY (job_states_id, class)
);

SELECT create_distributed_table('job_states', 'class');

CREATE INDEX job_states_class_last_updated ON job_states (class, last_updated);


CREATE VIEW pending_job_states AS
SELECT *
FROM job_states
WHERE state IN ('running', 'queued')
;


CREATE TYPE retweeter_scores_match_type AS ENUM (
    'retweet',
    'regex'
    );

-- definition of bipolar comparisons for retweeter polarization scores
CREATE TABLE retweeter_scores
(
    retweeter_scores_id BIGSERIAL                   NOT NULL,
    topics_id           BIGINT                      NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    group_a_id          BIGINT                      NULL,
    group_b_id          BIGINT                      NULL,
    name                TEXT                        NOT NULL,
    state               TEXT                        NOT NULL DEFAULT 'created but not queued',
    message             TEXT                        NULL,
    num_partitions      BIGINT                      NOT NULL,
    match_type          retweeter_scores_match_type NOT NULL DEFAULT 'retweet',

    PRIMARY KEY (retweeter_scores_id, topics_id)
);

SELECT create_distributed_table('retweeter_scores', 'topics_id');


-- group retweeters together so that we an compare, for example, sanders/warren retweeters to cruz/kasich retweeters
CREATE TABLE retweeter_groups
(
    retweeter_groups_id BIGSERIAL NOT NULL,
    topics_id           BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    retweeter_scores_id BIGINT    NOT NULL,
    name                TEXT      NOT NULL,

    PRIMARY KEY (retweeter_groups_id, topics_id),

    FOREIGN KEY (topics_id, retweeter_scores_id)
        REFERENCES retweeter_scores (topics_id, retweeter_scores_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('retweeter_groups', 'topics_id');

ALTER TABLE retweeter_scores
    ADD CONSTRAINT retweeter_scores_group_a
        FOREIGN KEY (topics_id, group_a_id)
            REFERENCES retweeter_groups (topics_id, retweeter_groups_id)
            ON DELETE CASCADE;

ALTER TABLE retweeter_scores
    ADD CONSTRAINT retweeter_scores_group_b
        FOREIGN KEY (topics_id, group_b_id)
            REFERENCES retweeter_groups (topics_id, retweeter_groups_id)
            ON DELETE CASCADE;


-- list of twitter users within a given topic that have retweeted the given user
CREATE TABLE retweeters
(
    retweeters_id       BIGSERIAL NOT NULL,
    topics_id           BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    retweeter_scores_id BIGINT    NOT NULL,
    twitter_user        TEXT      NOT NULL,
    retweeted_user      TEXT      NOT NULL,

    PRIMARY KEY (retweeters_id, topics_id),

    FOREIGN KEY (topics_id, retweeter_scores_id)
        REFERENCES retweeter_scores (topics_id, retweeter_scores_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('retweeters', 'topics_id');

CREATE UNIQUE INDEX retweeters_user
    ON retweeters (topics_id, retweeter_scores_id, twitter_user, retweeted_user);


CREATE TABLE retweeter_groups_users_map
(
    retweeter_groups_users_map_id BIGSERIAL NOT NULL,
    topics_id                     BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    retweeter_groups_id           BIGINT    NOT NULL,
    retweeter_scores_id           BIGINT    NOT NULL,
    retweeted_user                TEXT      NOT NULL,

    PRIMARY KEY (retweeter_groups_users_map_id, topics_id),

    FOREIGN KEY (topics_id, retweeter_groups_id)
        REFERENCES retweeter_groups (topics_id, retweeter_groups_id)
        ON DELETE CASCADE,

    FOREIGN KEY (topics_id, retweeter_scores_id)
        REFERENCES retweeter_scores (topics_id, retweeter_scores_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('retweeter_groups_users_map', 'topics_id');


-- count of shares by retweeters for each retweeted_user in retweeters
CREATE TABLE retweeter_stories
(
    retweeter_stories_id BIGSERIAL NOT NULL,
    topics_id            BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    retweeter_scores_id  BIGINT    NOT NULL,
    stories_id           BIGINT    NOT NULL,
    retweeted_user       TEXT      NOT NULL,
    share_count          BIGINT    NOT NULL,

    PRIMARY KEY (retweeter_stories_id, topics_id),

    FOREIGN KEY (topics_id, retweeter_stories_id)
        REFERENCES retweeter_stories (topics_id, retweeter_stories_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('retweeter_stories', 'topics_id');

CREATE UNIQUE INDEX retweeter_stories_psu
    ON retweeter_stories (topics_id, retweeter_scores_id, stories_id, retweeted_user);


-- polarization scores for media within a topic for the given retweeter_scores_definition
CREATE TABLE retweeter_media
(
    retweeter_media_id  BIGSERIAL NOT NULL,
    topics_id           BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    retweeter_scores_id BIGINT    NOT NULL,
    media_id            BIGINT    NOT NULL,
    group_a_count       BIGINT    NOT NULL,
    group_b_count       BIGINT    NOT NULL,
    group_a_count_n     FLOAT     NOT NULL,
    score               FLOAT     NOT NULL,
    partition           BIGint    not null,

    PRIMARY KEY (retweeter_media_id, topics_id),

    FOREIGN KEY (topics_id, retweeter_scores_id)
        REFERENCES retweeter_scores (topics_id, retweeter_scores_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('retweeter_media', 'topics_id');

ALTER TABLE retweeter_media
    ADD CONSTRAINT retweeter_media_media_id_fkey
        FOREIGN KEY (media_id) REFERENCES media (media_id) ON DELETE CASCADE;

CREATE INDEX retweeter_media_media_id ON retweeter_media (media_id);

CREATE UNIQUE INDEX retweeter_media_topics_id_retweeter_scores_id_media_id
    ON retweeter_media (topics_id, retweeter_scores_id, media_id);


CREATE TABLE retweeter_partition_matrix
(
    retweeter_partition_matrix_id BIGserial NOT NULL,
    topics_id                     BIGINT    NOT NULL REFERENCES topics (topics_id) ON DELETE CASCADE,
    retweeter_scores_id           BIGINT    NOT NULL,
    retweeter_groups_id           BIGINT    NOT NULL,
    group_name                    TEXT      NOT NULL,
    share_count                   BIGINT    NOT NULL,
    group_proportion              FLOAT     NOT NULL,
    partition                     BIGINT    NOT NULL,

    PRIMARY KEY (retweeter_partition_matrix_id, topics_id),

    FOREIGN KEY (topics_id, retweeter_scores_id)
        REFERENCES retweeter_scores (topics_id, retweeter_scores_id)
        ON DELETE CASCADE,

    FOREIGN KEY (topics_id, retweeter_groups_id)
        REFERENCES retweeter_groups (topics_id, retweeter_groups_id)
        ON DELETE CASCADE
);

SELECT create_distributed_table('retweeter_partition_matrix', 'topics_id');

CREATE INDEX retweeter_partition_matrix_topics_id_retweeter_scores_id
    ON retweeter_partition_matrix (topics_id, retweeter_scores_id);


--
-- Schema to hold object caches
--

CREATE SCHEMA cache;


-- Helper to purge object caches
CREATE OR REPLACE FUNCTION cache.purge_object_caches()
    RETURNS VOID AS
$$
BEGIN

    RAISE NOTICE 'Purging "s3_raw_downloads_cache" table...';
    EXECUTE '
        DELETE FROM cache.s3_raw_downloads_cache
        WHERE db_row_last_updated <= NOW() - INTERVAL ''3 days'';
    ';

    RAISE NOTICE 'Purging "extractor_results_cache" table...';
    EXECUTE '
        DELETE FROM cache.extractor_results_cache
        WHERE db_row_last_updated <= NOW() - INTERVAL ''3 days'';
    ';

END;
$$
    LANGUAGE plpgsql;


--
-- Raw downloads from S3 cache
--
CREATE UNLOGGED TABLE cache.s3_raw_downloads_cache
(
    cache_s3_raw_downloads_cache_id BIGSERIAL                NOT NULL,

    -- FIXME reference to "downloads_error", "downloads_feed_error" or "downloads_success"
    object_id                       BIGINT                   NOT NULL,

    -- Will be used to purge old cache objects;
    -- don't forget to update cache.purge_object_caches()
    db_row_last_updated             TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    raw_data                        BYTEA                    NOT NULL,

    PRIMARY KEY (cache_s3_raw_downloads_cache_id, object_id)
);

SELECT create_distributed_table('cache.s3_raw_downloads_cache', 'object_id');

CREATE UNIQUE INDEX cache_s3_raw_downloads_cache_object_id
    ON cache.s3_raw_downloads_cache (object_id);

CREATE INDEX cache_s3_raw_downloads_cache_db_row_last_updated
    ON cache.s3_raw_downloads_cache (db_row_last_updated);


-- Trigger to update "db_row_last_updated" for cache tables
CREATE OR REPLACE FUNCTION cache.update_cache_db_row_last_updated()
    RETURNS TRIGGER AS
$$
BEGIN
    NEW.db_row_last_updated = NOW();
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('cache.update_cache_db_row_last_updated()');


SELECT run_on_shards_or_raise('cache.s3_raw_downloads_cache', $cmd$

    CREATE TRIGGER cache_s3_raw_downloads_cache_db_row_last_updated_trigger
        BEFORE INSERT OR UPDATE
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE cache.update_cache_db_row_last_updated();

    $cmd$);


--
-- Cached extractor results for extraction jobs with use_cache set to true
--
CREATE UNLOGGED TABLE cache.extractor_results_cache
(
    cache_extractor_results_cache_id BIGSERIAL                NOT NULL,
    downloads_id                     BIGINT                   NOT NULL
        REFERENCES downloads_success (downloads_id) ON DELETE CASCADE,
    extracted_html                   TEXT                     NULL,
    extracted_text                   TEXT                     NULL,

    -- Will be used to purge old cache objects;
    -- don't forget to update cache.purge_object_caches()
    db_row_last_updated              TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    PRIMARY KEY (cache_extractor_results_cache_id, downloads_id)
);

SELECT create_distributed_table('cache.extractor_results_cache', 'downloads_id');

CREATE UNIQUE INDEX cache_extractor_results_cache_downloads_id
    ON cache.extractor_results_cache (downloads_id);

CREATE INDEX extractor_results_cache_db_row_last_updated
    ON cache.extractor_results_cache (db_row_last_updated);


SELECT run_on_shards_or_raise('cache.extractor_results_cache', $cmd$

    CREATE TRIGGER cache_extractor_results_cache_db_row_last_updated_trigger
        BEFORE INSERT OR UPDATE
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE cache.update_cache_db_row_last_updated();

    $cmd$);


-- keep track of per domain web requests so that we can throttle them using mediawords.util.web.user_agent.throttled.
-- this is unlogged because we don't care about anything more than about 10 seconds old.  we don't have a primary
-- key because we want it just to be a fast table for temporary storage.
CREATE UNLOGGED TABLE domain_web_requests
(
    domain_web_requests_id BIGSERIAL NOT NULL,
    domain                 TEXT      NOT NULL,
    request_time           TIMESTAMP NOT NULL DEFAULT NOW(),

    PRIMARY KEY (domain_web_requests_id, domain)
);

SELECT create_distributed_table('domain_web_requests', 'domain');

CREATE INDEX domain_web_requests_domain ON domain_web_requests (domain);


-- return false if there is a request for the given domain within the last domain_timeout_arg milliseconds.  otherwise
-- return true and insert a row into domain_web_request for the domain.  this function does not lock the table and
-- so may allow some parallel requests through.
CREATE OR REPLACE FUNCTION get_domain_web_requests_lock(
    domain_arg TEXT,
    domain_timeout_arg FLOAT
) RETURNS BOOLEAN AS
$$

BEGIN

    -- we don't want this table to grow forever or to have to manage it externally, so just truncate about every
    -- 1 million requests.  only do this if there are more than 1000 rows in the table so that unit tests will not
    -- randomly fail.
    IF (SELECT RANDOM() * 1000000) < 1 THEN
        IF EXISTS(SELECT 1 FROM domain_web_requests OFFSET 1000) THEN
            TRUNCATE TABLE domain_web_requests;
        END IF;
    END IF;

    IF EXISTS(
            SELECT *
            FROM domain_web_requests
            WHERE domain = domain_arg
              AND extract(epoch FROM NOW() - request_time) < domain_timeout_arg
        ) THEN
        RETURN FALSE;
    END IF;

    DELETE FROM domain_web_requests WHERE domain = domain_arg;
    INSERT INTO domain_web_requests (domain) SELECT domain_arg;

    RETURN TRUE;

END

$$ LANGUAGE plpgsql;


CREATE TYPE media_sitemap_pages_change_frequency AS ENUM (
    'always',
    'hourly',
    'daily',
    'weekly',
    'monthly',
    'yearly',
    'never'
    );


-- Pages derived from XML sitemaps (stories or not)
CREATE TABLE media_sitemap_pages
(
    media_sitemap_pages_id BIGSERIAL                            NOT NULL,
    media_id               BIGINT                               NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,

    -- <loc> -- URL of the page
    url                    TEXT                                 NOT NULL,

    -- <lastmod> -- date of last modification of the URL
    last_modified          TIMESTAMP WITH TIME ZONE             NULL,

    -- <changefreq> -- how frequently the page is likely to change
    change_frequency       media_sitemap_pages_change_frequency NULL,

    -- <priority> -- priority of this URL relative to other URLs on your site
    priority               DECIMAL(2, 1)                        NOT NULL DEFAULT 0.5,

    -- <news:title> -- title of the news article
    news_title             TEXT                                 NULL,

    -- <news:publication_date> -- article publication date
    news_publish_date      TIMESTAMP WITH TIME ZONE             NULL,

    CONSTRAINT media_sitemap_pages_priority_within_bounds
        CHECK (priority IS NULL OR (priority >= 0.0 AND priority <= 1.0)),

    PRIMARY KEY (media_sitemap_pages_id, media_id)
);

SELECT create_distributed_table('media_sitemap_pages', 'media_id');

CREATE INDEX media_sitemap_pages_media_id
    ON media_sitemap_pages (media_id);

CREATE UNIQUE INDEX media_sitemap_pages_media_id_url
    ON media_sitemap_pages (media_id, url);


--
-- Domains for which we have tried to fetch SimilarWeb stats
--
-- Every media source domain for which we have tried to fetch estimated visits
-- from SimilarWeb gets stored here.
--
-- The domain might have been invalid or unpopular enough so
-- "similarweb_estimated_visits" might not necessarily store stats for every
-- domain in this table.
--
CREATE TABLE similarweb_domains
(
    similarweb_domains_id BIGSERIAL PRIMARY KEY,

    -- Top-level (e.g. cnn.com) or second-level (e.g. edition.cnn.com) domain
    domain                TEXT NOT NULL

);

-- Not a reference table (because not referenced), not a distributed table (because too small)

CREATE UNIQUE INDEX similarweb_domains_domain
    ON similarweb_domains (domain);


--
-- Media - SimilarWeb domain map
--
-- A few media sources might be pointing to one or more domains due to code
-- differences in how domain was extracted from media source's URL between
-- various implementations.
--
CREATE TABLE media_similarweb_domains_map
(
    media_similarweb_domains_map_id BIGSERIAL PRIMARY KEY,

    media_id                        BIGINT NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,
    similarweb_domains_id           BIGINT NOT NULL
        REFERENCES similarweb_domains (similarweb_domains_id) ON DELETE CASCADE
);

-- Not a reference table (because not referenced), not a distributed table (because too small)

CREATE INDEX media_similarweb_domains_map_media_id
    ON media_similarweb_domains_map (media_id);

-- Different media sources can point to the same domain
CREATE UNIQUE INDEX media_similarweb_domains_map_media_id_sdi
    ON media_similarweb_domains_map (media_id, similarweb_domains_id);


--
-- SimilarWeb estimated visits for domain
-- (https://www.similarweb.com/corp/developer/estimated_visits_api)
--
CREATE TABLE similarweb_estimated_visits
(
    similarweb_estimated_visits_id BIGSERIAL PRIMARY KEY,

    -- Domain for which the stats were fetched
    similarweb_domains_id          BIGINT  NOT NULL
        REFERENCES similarweb_domains (similarweb_domains_id) ON DELETE CASCADE,

    -- Month, e.g. 2018-03-01 for March of 2018
    month                          DATE    NOT NULL,

    -- Visit count is for the main domain only (value of "main_domain_only" API call argument)
    main_domain_only               BOOLEAN NOT NULL,

    -- Visit count
    visits                         BIGINT  NOT NULL
);

-- Not a reference table (because not referenced), not a distributed table (because too small)

CREATE UNIQUE INDEX similarweb_estimated_visits_domain_month_mdo
    ON similarweb_estimated_visits (similarweb_domains_id, month, main_domain_only);


--
-- Enclosures added to the story's feed item
--
-- noinspection SqlResolve
CREATE TABLE story_enclosures
(
    story_enclosures_id BIGSERIAL NOT NULL,
    stories_id          BIGINT    NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,

    -- Podcast enclosure URL
    url                 TEXT      NOT NULL,

    -- RSS spec says that enclosure's "length" and "type" are required too but
    -- I guess some podcasts don't care that much about specs so both are
    -- allowed to be NULL:

    -- MIME type as reported by <enclosure />
    mime_type           CITEXT    NULL,

    -- Length in bytes as reported by <enclosure />
    length              BIGINT    NULL,

    PRIMARY KEY (story_enclosures_id, stories_id)
);

SELECT create_distributed_table('story_enclosures', 'stories_id');

CREATE UNIQUE INDEX story_enclosures_stories_id_url
    ON story_enclosures (stories_id, url);


--
-- Celery job results
-- (configured as self.__app.conf.database_table_names; schema is dictated by Celery + SQLAlchemy)
--

CREATE TABLE celery_groups
(
    id         BIGINT                      NOT NULL PRIMARY KEY,
    taskset_id CHARACTER VARYING(155)      NULL,
    result     BYTEA                       NULL,
    date_done  TIMESTAMP WITHOUT TIME ZONE NULL
);

-- noinspection SqlResolve @ routine/"create_reference_table"
SELECT create_reference_table('celery_groups');

CREATE UNIQUE INDEX celery_groups_taskset_id ON celery_groups (taskset_id);


CREATE TABLE celery_tasks
(
    id        BIGINT                      NOT NULL,
    task_id   CHARACTER VARYING(155)      NULL,
    status    CHARACTER VARYING(50)       NULL,
    result    BYTEA                       NULL,
    date_done TIMESTAMP WITHOUT TIME ZONE NULL,
    traceback TEXT                        NULL,

    PRIMARY KEY (id, task_id)
);

SELECT create_distributed_table('celery_tasks', 'task_id');

CREATE UNIQUE INDEX celery_tasks_task_id ON celery_tasks (task_id);

CREATE SEQUENCE task_id_sequence AS BIGINT;
