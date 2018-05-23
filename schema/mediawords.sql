--
-- Schema for MediaWords database
--

-- main schema
CREATE SCHEMA IF NOT EXISTS public;


CREATE OR REPLACE LANGUAGE plpgsql;

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;


-- Database properties (variables) table
create table database_variables (
    database_variables_id        serial          primary key,
    name                varchar(512)    not null unique,
    value               varchar(1024)   not null
);

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4672;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';


-- Set the version number right away
SELECT set_database_schema_version();

-- This function is needed because date_trunc('week', date) is not consider immutable
-- See http://www.mentby.com/Group/pgsql-general/datetrunc-on-date-is-immutable.html
--
CREATE OR REPLACE FUNCTION week_start_date(day date)
    RETURNS date AS
$$
DECLARE
    date_trunc_result date;
BEGIN
    date_trunc_result := date_trunc('week', day::timestamp);
    RETURN date_trunc_result;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE
  COST 10;


-- Returns first 64 bits (16 characters) of MD5 hash
--
-- Useful for reducing index sizes (e.g. in story_sentences.sentence) where
-- 64 bits of entropy is enough.
CREATE OR REPLACE FUNCTION half_md5(string TEXT) RETURNS bytea AS $$
    -- pgcrypto's functions are being referred with public schema prefix to make pg_upgrade work
    SELECT SUBSTRING(public.digest(string, 'md5'::text), 0, 9);
$$ LANGUAGE SQL;


-- Returns true if table exists (and user has access to it)
-- Table name might be with ("public.stories") or without ("stories") schema.
CREATE OR REPLACE FUNCTION table_exists(target_table_name VARCHAR)
RETURNS BOOLEAN AS $$
DECLARE
    schema_position INT;
    schema VARCHAR;
BEGIN

    SELECT POSITION('.' IN target_table_name) INTO schema_position;

    -- "." at string index 0 would return position 1
    IF schema_position = 0 THEN
        schema := CURRENT_SCHEMA();
    ELSE
        schema := SUBSTRING(target_table_name FROM 1 FOR schema_position - 1);
        target_table_name := SUBSTRING(target_table_name FROM schema_position + 1);
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = schema
          AND table_name = target_table_name
    );

END;
$$
LANGUAGE plpgsql;


 -- Returns true if the date is greater than the latest import date in solr_imports
 CREATE OR REPLACE FUNCTION before_last_solr_import(db_row_last_updated timestamp with time zone) RETURNS boolean AS $$
 BEGIN
    RETURN ( ( db_row_last_updated is null ) OR
             ( db_row_last_updated < ( select max( import_date ) from solr_imports ) ) );
END;
$$
LANGUAGE 'plpgsql'
 ;

CREATE OR REPLACE FUNCTION update_media_last_updated () RETURNS trigger AS
$$
   DECLARE
   BEGIN

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
      	 update media set db_row_last_updated = now()
             where media_id = NEW.media_id;
      END IF;

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
      	 update media set db_row_last_updated = now()
              where media_id = OLD.media_id;
      END IF;

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
        RETURN NEW;
      ELSE
        RETURN OLD;
      END IF;
   END;
$$
LANGUAGE 'plpgsql';


-- Update "db_row_last_updated" column to trigger Solr (re)imports for given
-- row; no update gets done if "db_row_last_updated" is set explicitly in
-- INSERT / UPDATE (e.g. when copying between tables)
CREATE OR REPLACE FUNCTION last_updated_trigger() RETURNS trigger AS $$

BEGIN

    IF TG_OP = 'INSERT' THEN
        IF NEW.db_row_last_updated IS NULL THEN
            NEW.db_row_last_updated = NOW();
        END IF;

    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.db_row_last_updated = OLD.db_row_last_updated THEN
            NEW.db_row_last_updated = NOW();
        END IF;
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


create table media (
    media_id            serial          primary key,
    url                 varchar(1024)   not null,
    name                varchar(128)    not null,
    moderated           boolean         not null,
    moderation_notes    text            null,
    full_text_rss       boolean         null,

    -- It indicates that the media source includes a substantial number of
    -- links in its feeds that are not its own. These media sources cause
    -- problems for the topic mapper's spider, which finds those foreign rss links and
    -- thinks that the urls belong to the parent media source.
    foreign_rss_links   boolean         not null default( false ),
    dup_media_id        int             null references media on delete set null deferrable,
    is_not_dup          boolean         null,

    -- Delay content downloads for this media source this many hours
    content_delay       int             null,

    db_row_last_updated         timestamp with time zone,

    last_solr_import_date       timestamp with time zone not null default now(),

    -- notes for internal media cloud consumption (eg. 'added this for yochai')
    editor_notes                text null,
    -- notes for public consumption (eg. 'leading dissident paper in anatarctica')
    public_notes                text null,

    -- if true, indicates that media cloud closely monitors the health of this source
    is_monitored                boolean not null default false,

    CONSTRAINT media_name_not_empty CHECK ( ( (name)::text <> ''::text ) ),
    CONSTRAINT media_self_dup CHECK ( dup_media_id IS NULL OR dup_media_id <> media_id )
);

create unique index media_name on media(name);
create unique index media_url on media(url);
create index media_moderated on media(moderated);
create index media_db_row_last_updated on media( db_row_last_updated );

CREATE INDEX media_name_trgm on media USING gin (name gin_trgm_ops);
CREATE INDEX media_url_trgm on media USING gin (url gin_trgm_ops);


-- update media stats table for deleted story sentence
CREATE FUNCTION update_media_db_row_last_updated() RETURNS trigger AS $$
BEGIN
    NEW.db_row_last_updated = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

create trigger update_media_db_row_last_updated before update or insert
    on media for each row execute procedure update_media_db_row_last_updated();

--- allow lookup of media by mediawords.util.url.normalized_url_lossy.
-- the data in this table is accessed and kept up to date by mediawords.tm.media.lookup_medium_by_url
create table media_normalized_urls (
    media_normalized_urls_id        serial primary key,
    media_id                        int not null references media,
    normalized_url                  varchar(1024) not null,
    db_row_last_updated             timestamp not null default now(),

    -- assigned the value of mediawords.util.url.normalized_url_lossy_version()
    normalize_url_lossy_version    int not null
);

create unique index media_normalized_urls_medium on media_normalized_urls(normalize_url_lossy_version, media_id);
create index media_normalized_urls_url on media_normalized_urls(normalized_url);
create index media_normalized_urls_db_row_last_updated on media_normalized_urls(db_row_last_updated);


-- list of media sources for which the stories should be updated to be at
-- at least db_row_last_updated
create table media_update_time_queue (
    media_id                    int         not null references media on delete cascade,
    db_row_last_updated         timestamp with time zone not null
);


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


create index media_update_time_queue_updated on media_update_time_queue ( db_row_last_updated );

create table media_stats (
    media_stats_id              serial      primary key,
    media_id                    int         not null references media on delete cascade,
    num_stories                 int         not null,
    num_sentences               int         not null,
    stat_date                   date        not null
);

--
-- Returns true if media has active RSS feeds
--
CREATE OR REPLACE FUNCTION media_has_active_syndicated_feeds(param_media_id INT)
RETURNS boolean AS $$
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


create index media_stats_medium on media_stats( media_id );

create type feed_feed_type AS ENUM (

    -- Syndicated feed, e.g. RSS or Atom
    'syndicated',

    -- Web page feed, used when no syndicated feed was found
    'web_page',

    -- Univision.com XML feed
    'univision',

    -- Superglue (TV) feed
    'superglue'

);

-- Feed statuses that determine whether the feed will be fetched
-- or skipped
CREATE TYPE feed_feed_status AS ENUM (
    -- Feed is active, being fetched
    'active',
    -- Feed is (temporary) disabled (usually by hand), not being fetched
    'inactive',
    -- Feed was moderated as the one that shouldn't be fetched, but is still kept around
    -- to reduce the moderation queue next time the page is being scraped for feeds to find
    -- new ones
    'skipped'
);

create table feeds (
    feeds_id            serial              primary key,
    media_id            int                 not null references media on delete cascade,
    name                varchar(512)        not null,
    url                 varchar(1024)       not null,
    reparse             boolean             null,
    feed_type           feed_feed_type      not null default 'syndicated',
    feed_status         feed_feed_status    not null default 'active',
    last_checksum       text                null,

    -- Last time the feed was *attempted* to be downloaded and parsed
    -- (null -- feed was never attempted to be downloaded and parsed)
    -- (used to allow more active feeds to be downloaded more frequently)
    last_attempted_download_time    timestamp with time zone,

    -- Last time the feed was *successfully* downloaded and parsed
    -- (null -- feed was either never attempted to be downloaded or parsed,
    -- or feed was never successfully downloaded and parsed)
    -- (used to find feeds that are broken)
    last_successful_download_time   timestamp with time zone,

    -- Last time the feed provided a new story
    -- (null -- feed has never provided any stories)
    last_new_story_time             timestamp with time zone

);

UPDATE feeds SET last_new_story_time = greatest( last_attempted_download_time, last_new_story_time );

create index feeds_media on feeds(media_id);
create index feeds_name on feeds(name);
create unique index feeds_url on feeds (url, media_id);
create index feeds_reparse on feeds(reparse);
create index feeds_last_attempted_download_time on feeds(last_attempted_download_time);
create index feeds_last_successful_download_time on feeds(last_successful_download_time);

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


create table tag_sets (
    tag_sets_id            serial            primary key,

    --unique identifier
    name                varchar(512)    not null,

    -- short human readable label
    label               varchar(512),

    -- longer human readable description
    description         text,

    -- should public interfaces show this as an option for searching media sources
    show_on_media       boolean,

    -- should public interfaces show this as an option for search stories
    show_on_stories     boolean,

    CONSTRAINT tag_sets_name_not_empty CHECK (((name)::text <> ''::text))
);

create unique index tag_sets_name on tag_sets (name);

create table tags (
    tags_id                serial            primary key,
    tag_sets_id            int                not null references tag_sets,

    -- unique identifier
    tag                    varchar(512)    not null,

    -- short human readable label
    label               varchar(512),

    -- longer human readable description
    description         text,

    -- should public interfaces show this as an option for searching media sources
    show_on_media       boolean,

    -- should public interfaces show this as an option for search stories
    show_on_stories     boolean,

    -- if true, users can expect this tag ans its associations not to change in major ways
    is_static              boolean not null default false,

        CONSTRAINT no_line_feed CHECK (((NOT ((tag)::text ~~ '%
%'::text)) AND (NOT ((tag)::text ~~ '%
%'::text)))),
        CONSTRAINT tag_not_empty CHECK (((tag)::text <> ''::text))
);

create index tags_tag_sets_id ON tags (tag_sets_id);
create unique index tags_tag on tags (tag, tag_sets_id);
create index tags_label on tags (label);
create index tags_fts on tags using gin(to_tsvector('english'::regconfig, (tag::text || ' '::text) || label::text));

create index tags_show_on_media on tags ( show_on_media );
create index tags_show_on_stories on tags ( show_on_stories );

create view tags_with_sets as select t.*, ts.name as tag_set_name from tags t, tag_sets ts where t.tag_sets_id = ts.tag_sets_id;

insert into tag_sets ( name, label, description ) values (
    'media_type',
    'Media Type',
    'High level topology for media sources for use across a variety of different topics'
);

create temporary table media_type_tags ( name text, label text, description text );
insert into media_type_tags values
    (
        'Not Typed',
        'Not Typed',
        'The medium has not yet been typed.'
    ),
    (
        'Other',
        'Other',
        'The medium does not fit in any listed type.'
    ),
    (
        'Independent Group',
        'Ind. Group',

        -- Single multiline string
        'An academic or nonprofit group that is not affiliated with the private sector or government, '
        'such as the Electronic Frontier Foundation or the Center for Democracy and Technology)'
    ),
    (
        'Social Linking Site',
        'Social Linking',

        -- Single multiline string
        'A site that aggregates links based at least partially on user submissions and/or ranking, '
        'such as Reddit, Digg, Slashdot, MetaFilter, StumbleUpon, and other social news sites'
    ),
    (
        'Blog',
        'Blog',

        -- Single multiline string
        'A web log, written by one or more individuals, that is not associated with a professional '
        'or advocacy organization or institution'
    ),
    (
        'General Online News Media',
        'General News',

        -- Single multiline string
        'A site that is a mainstream media outlet, such as The New York Times and The Washington Post; '
        'an online-only news outlet, such as Slate, Salon, or the Huffington Post; '
        'or a citizen journalism or non-profit news outlet, such as Global Voices or ProPublica'
    ),
    (
        'Issue Specific Campaign',
        'Issue',
        'A site specifically dedicated to campaigning for or against a single issue.'
    ),
    (
        'News Aggregator',
        'News Agg.',

        -- Single multiline string
        'A site that contains little to no original content and compiles news from other sites, '
        'such as Yahoo News or Google News'
    ),
    (
        'Tech Media',
        'Tech Media',

        -- Single multiline string
        'A site that focuses on technological news and information produced by a news organization, '
        'such as Arstechnica, Techdirt, or Wired.com'
    ),
    (
        'Private Sector',
        'Private Sec.',

        -- Single multiline string
        'A non-news media for-profit actor, including, for instance, trade organizations, industry '
        'sites, and domain registrars'
    ),
    (
        'Government',
        'Government',

        -- Single multiline string
        'A site associated with and run by a government-affiliated entity, such as the DOJ website, '
        'White House blog, or a U.S. Senator official website'
    ),
    (
        'User-Generated Content Platform',
        'User Gen.',

        -- Single multiline string
        'A general communication and networking platform or tool, like Wikipedia, YouTube, Twitter, '
        'and Scribd, or a search engine like Google or speech platform like the Daily Kos'
    );

insert into tags ( tag_sets_id, tag, label, description )
    select ts.tag_sets_id, mtt.name, mtt.name, mtt.description
        from tag_sets ts cross join media_type_tags mtt
        where ts.name = 'media_type';

create table feeds_tags_map (
    feeds_tags_map_id    serial            primary key,
    feeds_id            int                not null references feeds on delete cascade,
    tags_id                int                not null references tags on delete cascade
);

create unique index feeds_tags_map_feed on feeds_tags_map (feeds_id, tags_id);
create index feeds_tags_map_tag on feeds_tags_map (tags_id);

create table media_tags_map (
    media_tags_map_id    serial            primary key,
    media_id            int                not null references media on delete cascade,
    tags_id                int                not null references tags on delete cascade,
    tagged_date         date null default now()
);

create unique index media_tags_map_media on media_tags_map (media_id, tags_id);
create index media_tags_map_tag on media_tags_map (tags_id);

DROP TRIGGER IF EXISTS mtm_last_updated on media_tags_map CASCADE;
CREATE TRIGGER mtm_last_updated BEFORE INSERT OR UPDATE OR DELETE
    ON media_tags_map FOR EACH ROW EXECUTE PROCEDURE update_media_last_updated() ;

create view media_with_media_types as
    select m.*, mtm.tags_id media_type_tags_id, t.label media_type
    from
        media m
        left join (
            tags t
            join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id and ts.name = 'media_type' )
            join media_tags_map mtm on ( mtm.tags_id = t.tags_id )
        ) on ( m.media_id = mtm.media_id );


create table media_rss_full_text_detection_data (
    media_id            int references media on delete cascade,
    max_similarity      real,
    avg_similarity      double precision,
    min_similarity      real,
    avg_expected_length numeric,
    avg_rss_length      numeric,
    avg_rss_discription numeric,
    count               bigint
);

create index media_rss_full_text_detection_data_media on media_rss_full_text_detection_data (media_id);


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


create table color_sets (
    color_sets_id               serial          primary key,
    color                       varchar( 256 )  not null,
    color_set                   varchar( 256 )  not null,
    id                          varchar( 256 )  not null
);

create unique index color_sets_set_id on color_sets ( color_set, id );

-- prefill colors for partisan_code set so that liberal is blue and conservative is red
insert into color_sets ( color, color_set, id ) values ( 'c10032', 'partisan_code', 'partisan_2012_conservative' );
insert into color_sets ( color, color_set, id ) values ( '00519b', 'partisan_code', 'partisan_2012_liberal' );
insert into color_sets ( color, color_set, id ) values ( '009543', 'partisan_code', 'partisan_2012_libertarian' );

create table stories (
    stories_id                  serial          primary key,
    media_id                    int             not null references media on delete cascade,
    url                         varchar(1024)   not null,
    guid                        varchar(1024)   not null,
    title                       text            not null,
    description                 text            null,
    publish_date                timestamp       not null,
    collect_date                timestamp       not null default now(),
    full_text_rss               boolean         not null default 'f',
    db_row_last_updated                timestamp with time zone,
    language                    varchar(3)      null   -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
);

create index stories_media_id on stories (media_id);
create unique index stories_guid on stories(guid, media_id);
create index stories_url on stories (url);
create index stories_publish_date on stories (publish_date);
create index stories_collect_date on stories (collect_date);
create index stories_md on stories(media_id, date_trunc('day'::text, publish_date));
create index stories_language on stories(language);
create index stories_title_hash on stories( md5( title ) );
create index stories_publish_day on stories( date_trunc( 'day', publish_date ) );

DROP TRIGGER IF EXISTS stories_last_updated_trigger on stories CASCADE;
CREATE TRIGGER stories_last_updated_trigger
    BEFORE INSERT OR UPDATE ON stories
    FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger();

DROP TRIGGER IF EXISTS stories_update_story_sentences_last_updated_trigger on stories CASCADE;
CREATE TRIGGER stories_update_story_sentences_last_updated_trigger
    AFTER INSERT OR UPDATE ON stories
    FOR EACH ROW EXECUTE PROCEDURE update_story_sentences_updated_time_trigger();

create table stories_ap_syndicated (
    stories_ap_syndicated_id    serial primary key,
    stories_id                  int not null references stories on delete cascade,
    ap_syndicated               boolean not null
);

create unique index stories_ap_syndicated_story on stories_ap_syndicated ( stories_id );


--- Superglue (TV) stories metadata -->
CREATE TABLE stories_superglue_metadata (
    stories_superglue_metadata_id   SERIAL    PRIMARY KEY,
    stories_id                      INT       NOT NULL REFERENCES stories ON DELETE CASCADE,
    video_url                       VARCHAR   NOT NULL,
    thumbnail_url                   VARCHAR   NOT NULL,   -- might be an empty string but not NULL
    segment_duration                NUMERIC   NOT NULL
);

CREATE UNIQUE INDEX stories_superglue_metadata_stories_id
    ON stories_superglue_metadata (stories_id);


CREATE TYPE download_state AS ENUM (
    'error',
    'fetching',
    'pending',
    'queued',
    'success',
    'feed_error',
    'extractor_error'
);

CREATE TYPE download_type AS ENUM (
    'Calais',
    'calais',
    'content',
    'feed',
    'spider_blog_home',
    'spider_posting',
    'spider_rss',
    'spider_blog_friends_list',
    'spider_validation_blog_home',
    'spider_validation_rss',
    'archival_only'
);

create table downloads (
    downloads_id        serial          primary key,
    feeds_id            int             null references feeds,
    stories_id          int             null references stories on delete cascade,
    parent              int             null,
    url                 varchar(1024)   not null,
    host                varchar(1024)   not null,
    download_time       timestamp       not null default now(),
    type                download_type   not null,
    state               download_state  not null,
    path                text            null,
    error_message       text            null,
    priority            int             not null,
    sequence            int             not null,
    extracted           boolean         not null default 'f'
);


alter table downloads add constraint downloads_parent_fkey
    foreign key (parent) references downloads on delete set null;
alter table downloads add constraint downloads_path
    check ((state = 'success' and path is not null) or
           (state != 'success'));
alter table downloads add constraint downloads_feed_id_valid
      check (feeds_id is not null);
alter table downloads add constraint downloads_story
    check (((type = 'feed') and stories_id is null) or (stories_id is not null));

-- make the query optimizer get enough stats to use the feeds_id index
alter table downloads alter feeds_id set statistics 1000;

-- Temporary hack so that we don't have to rewrite the entire download to alter the type column

ALTER TABLE downloads
    ADD CONSTRAINT valid_download_type
    CHECK( type NOT IN
      (
      'spider_blog_home',
      'spider_posting',
      'spider_rss',
      'spider_blog_friends_list',
      'spider_validation_blog_home',
      'spider_validation_rss',
      'archival_only'
      )
    );

create index downloads_parent on downloads (parent);
-- create unique index downloads_host_fetching
--     on downloads(host, (case when state='fetching' then 1 else null end));
create index downloads_time on downloads (download_time);

create index downloads_feed_download_time on downloads ( feeds_id, download_time );

-- create index downloads_sequence on downloads (sequence);
create index downloads_story on downloads(stories_id);
CREATE INDEX downloads_state_downloads_id_pending on downloads(state,downloads_id) where state='pending';
create index downloads_extracted on downloads(extracted, state, type)
    where extracted = 'f' and state = 'success' and type = 'content';

CREATE INDEX downloads_stories_to_be_extracted
    ON downloads (stories_id)
    WHERE extracted = false AND state = 'success' AND type = 'content';

CREATE INDEX downloads_extracted_stories on downloads (stories_id) where type='content' and state='success';
CREATE INDEX downloads_state_queued_or_fetching on downloads(state) where state='queued' or state='fetching';
CREATE INDEX downloads_state_fetching ON downloads(state, downloads_id) where state = 'fetching';

CREATE INDEX downloads_in_old_format
    ON downloads USING btree (downloads_id)
    WHERE state = 'success'::download_state
      AND path ~~ 'content/%'::text;

create view downloads_media as select d.*, f.media_id as _media_id from downloads d, feeds f where d.feeds_id = f.feeds_id;

create view downloads_non_media as select d.* from downloads d where d.feeds_id is null;

CREATE OR REPLACE FUNCTION site_from_host(host varchar)
    RETURNS varchar AS
$$
BEGIN
    RETURN regexp_replace(host, E'^(.)*?([^.]+)\\.([^.]+)$' ,E'\\2.\\3');
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE INDEX downloads_sites_pending on downloads ( site_from_host( host ) ) where state='pending';

CREATE UNIQUE INDEX downloads_sites_downloads_id_pending ON downloads ( site_from_host(host), downloads_id ) WHERE (state = 'pending');

-- CREATE INDEX downloads_sites_index_downloads_id on downloads (site_from_host( host ), downloads_id);

CREATE VIEW downloads_sites as select site_from_host( host ) as site, * from downloads_media;


--
-- Raw downloads stored in the database (if the "postgresql" download storage
-- method is enabled)
--
CREATE TABLE raw_downloads (
    raw_downloads_id    SERIAL      PRIMARY KEY,
    object_id           INTEGER     NOT NULL REFERENCES downloads (downloads_id) ON DELETE CASCADE,
    raw_data            BYTEA       NOT NULL
);
CREATE UNIQUE INDEX raw_downloads_object_id ON raw_downloads (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE raw_downloads
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;


create table feeds_stories_map
 (
    feeds_stories_map_id    serial  primary key,
    feeds_id                int        not null references feeds on delete cascade,
    stories_id                int        not null references stories on delete cascade
);

create unique index feeds_stories_map_feed on feeds_stories_map (feeds_id, stories_id);
create index feeds_stories_map_story on feeds_stories_map (stories_id);


--
-- Partitioning tools
--

-- Return partition size for every table that is partitioned by "stories_id"
CREATE OR REPLACE FUNCTION stories_partition_chunk_size()
RETURNS BIGINT AS $$
BEGIN
    RETURN 100 * 1000 * 1000;   -- 100m stories in each partition
END; $$
LANGUAGE plpgsql IMMUTABLE;


-- Return partition table name for a given base table name and "stories_id"
CREATE OR REPLACE FUNCTION stories_partition_name(base_table_name TEXT, stories_id INT)
RETURNS TEXT AS $$
DECLARE

    -- Up to 100 partitions, suffixed as "_00", "_01" ..., "_99"
    -- (having more of them is not feasible)
    to_char_format CONSTANT TEXT := '00';

    -- Partition table name (e.g. "stories_tags_map_01")
    table_name TEXT;

    stories_id_chunk_number INT;

BEGIN
    SELECT stories_id / stories_partition_chunk_size() INTO stories_id_chunk_number;

    SELECT base_table_name || '_' || TRIM(leading ' ' FROM TO_CHAR(stories_id_chunk_number, to_char_format))
        INTO table_name;

    RETURN table_name;
END;
$$
LANGUAGE plpgsql IMMUTABLE;


-- Create missing partitions for tables partitioned by "stories_id", returning
-- a list of created partition tables
CREATE OR REPLACE FUNCTION stories_create_partitions(base_table_name TEXT)
RETURNS SETOF TEXT AS
$$
DECLARE
    chunk_size INT;
    max_stories_id INT;
    partition_stories_id INT;

    -- Partition table name (e.g. "stories_tags_map_01")
    target_table_name TEXT;

    -- Partition table owner (e.g. "mediaclouduser")
    target_table_owner TEXT;

    -- "stories_id" chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_start BIGINT;

    -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
    stories_id_end BIGINT;
BEGIN

    SELECT stories_partition_chunk_size() INTO chunk_size;

    -- Create +1 partition for future insertions
    SELECT COALESCE(MAX(stories_id), 0) + chunk_size FROM stories INTO max_stories_id;

    FOR partition_stories_id IN 1..max_stories_id BY chunk_size LOOP
        SELECT stories_partition_name( base_table_name, partition_stories_id ) INTO target_table_name;
        IF table_exists(target_table_name) THEN
            RAISE NOTICE 'Partition "%" for story ID % already exists.', target_table_name, partition_stories_id;
        ELSE
            RAISE NOTICE 'Creating partition "%" for story ID %', target_table_name, partition_stories_id;

            SELECT (partition_stories_id / chunk_size) * chunk_size INTO stories_id_start;
            SELECT ((partition_stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

            EXECUTE '
                CREATE TABLE ' || target_table_name || ' (

                    PRIMARY KEY (' || base_table_name || '_id),

                    -- Partition by stories_id
                    CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id CHECK (
                        stories_id >= ''' || stories_id_start || '''
                    AND stories_id <  ''' || stories_id_end   || '''),

                    -- Foreign key to stories.stories_id
                    CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id_fkey
                        FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL ON DELETE CASCADE

                ) INHERITS (' || base_table_name || ');
            ';

            -- Update owner
            SELECT u.usename AS owner
            FROM information_schema.tables AS t
                JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
                JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
            WHERE t.table_name = base_table_name
              AND t.table_schema = 'public'
            INTO target_table_owner;

            EXECUTE 'ALTER TABLE ' || target_table_name || ' OWNER TO ' || target_table_owner || ';';

            -- Add created partition name to the list of returned partition names
            RETURN NEXT target_table_name;

        END IF;
    END LOOP;

    RETURN;

END;
$$
LANGUAGE plpgsql;


--
-- Story -> tag map
--

-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE stories_tags_map (

    -- PRIMARY KEY on master table needed for database handler's primary_key_column() method to work
    stories_tags_map_id     BIGSERIAL   PRIMARY KEY NOT NULL,

    stories_id              INT         NOT NULL,
    tags_id                 INT         NOT NULL,
    db_row_last_updated     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TRIGGER stories_tags_map_last_updated_trigger
    BEFORE INSERT OR UPDATE ON stories_tags_map
    FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger();

CREATE TRIGGER stories_tags_map_update_stories_last_updated_trigger
    AFTER INSERT OR UPDATE OR DELETE ON stories_tags_map
    FOR EACH ROW EXECUTE PROCEDURE update_stories_updated_time_by_stories_id_trigger();


-- Create missing "stories_tags_map" partitions
CREATE OR REPLACE FUNCTION stories_tags_map_create_partitions()
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT stories_create_partitions('stories_tags_map'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;
        
        -- Add extra foreign keys / constraints to the newly created partitions
        EXECUTE '
            ALTER TABLE ' || partition || '

                -- Foreign key to tags.tags_id
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_tags_id_fkey
                    FOREIGN KEY (tags_id) REFERENCES tags (tags_id) MATCH FULL ON DELETE CASCADE,

                -- Unique duplets
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_stories_id_tags_id_unique
                    UNIQUE (stories_id, tags_id);
        ';

    END LOOP;

END;
$$
LANGUAGE plpgsql;

-- Create initial "stories_tags_map" partitions for empty database
SELECT stories_tags_map_create_partitions();


-- Upsert row into correct partition
CREATE OR REPLACE FUNCTION stories_tags_map_partition_upsert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "stories_tags_map_01")
BEGIN
    SELECT stories_partition_name( 'stories_tags_map', NEW.stories_id ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ON CONFLICT (stories_id, tags_id) DO NOTHING
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER stories_tags_map_partition_upsert_trigger
    BEFORE INSERT ON stories_tags_map
    FOR EACH ROW EXECUTE PROCEDURE stories_tags_map_partition_upsert_trigger();



CREATE TABLE download_texts (
    download_texts_id integer NOT NULL,
    downloads_id integer NOT NULL,
    download_text text NOT NULL,
    download_text_length int NOT NULL
);

CREATE SEQUENCE download_texts_download_texts_id_seq
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1 OWNED BY download_texts.download_texts_id;

CREATE UNIQUE INDEX download_texts_downloads_id_index ON download_texts USING btree (downloads_id);

ALTER TABLE download_texts ALTER COLUMN download_texts_id SET DEFAULT nextval('download_texts_download_texts_id_seq'::regclass);

ALTER TABLE ONLY download_texts
    ADD CONSTRAINT download_texts_pkey PRIMARY KEY (download_texts_id);

ALTER TABLE ONLY download_texts
    ADD CONSTRAINT download_texts_downloads_id_fkey FOREIGN KEY (downloads_id) REFERENCES downloads(downloads_id) ON DELETE CASCADE;

ALTER TABLE download_texts add CONSTRAINT download_text_length_is_correct CHECK (length(download_text)=download_text_length);



--
-- Individual sentences of every story
--

-- Intermediate table for migrating sentences to the partitioned table
create table story_sentences_nonpartitioned (
    story_sentences_nonpartitioned_id   BIGSERIAL       PRIMARY KEY,
    stories_id                          INT             NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    sentence_number                     INT             NOT NULL,
    sentence                            TEXT            NOT NULL,
    media_id                            INT             NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,
    publish_date                        TIMESTAMP       NOT NULL,
    db_row_last_updated                 TIMESTAMP WITH TIME ZONE,
    language                            VARCHAR(3)      NULL,
    is_dup                              BOOLEAN         NULL
);

CREATE INDEX story_sentences_nonpartitioned_story
    ON story_sentences_nonpartitioned (stories_id, sentence_number);

CREATE INDEX story_sentences_nonpartitioned_db_row_last_updated
    ON story_sentences_nonpartitioned (db_row_last_updated);

CREATE INDEX story_sentences_nonpartitioned_sentence_half_md5
    ON story_sentences_nonpartitioned (half_md5(sentence));

CREATE TRIGGER story_sentences_nonpartitioned_last_updated_trigger
    BEFORE INSERT OR UPDATE ON story_sentences_nonpartitioned
    FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger();


-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE story_sentences_partitioned (
    story_sentences_partitioned_id      BIGSERIAL       PRIMARY KEY NOT NULL,
    stories_id                          INT             NOT NULL,
    sentence_number                     INT             NOT NULL,
    sentence                            TEXT            NOT NULL,
    media_id                            INT             NOT NULL,
    publish_date                        TIMESTAMP       NOT NULL,

    -- Time this row was last updated
    db_row_last_updated                 TIMESTAMP WITH TIME ZONE,

    -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
    language                            VARCHAR(3)      NULL,

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
    is_dup                              BOOLEAN         NULL
);

CREATE TRIGGER story_sentences_partitioned_last_updated_trigger
    BEFORE INSERT OR UPDATE ON story_sentences_partitioned
    FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger();


-- Create missing "story_sentences_partitioned" partitions
CREATE OR REPLACE FUNCTION story_sentences_create_partitions()
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT stories_create_partitions('story_sentences_partitioned'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;
        
        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_media_id_fkey
                FOREIGN KEY (media_id) REFERENCES media (media_id) MATCH FULL ON DELETE CASCADE;

            CREATE UNIQUE INDEX ' || partition || '_stories_id_sentence_number
                ON ' || partition || ' (stories_id, sentence_number);

            CREATE INDEX ' || partition || '_db_row_last_updated
                ON ' || partition || ' (db_row_last_updated);

            CREATE INDEX ' || partition || '_sentence_media_week
                ON ' || partition || ' (half_md5(sentence), media_id, week_start_date(publish_date::date));
        ';

    END LOOP;

END;
$$
LANGUAGE plpgsql;

-- Create initial "story_sentences_partitioned" partitions for empty database
SELECT story_sentences_create_partitions();


-- View that joins the non-partitioned and partitioned tables while the data is
-- being migrated
CREATE OR REPLACE VIEW story_sentences AS

    SELECT *
    FROM (
        SELECT
            story_sentences_partitioned_id AS story_sentences_id,
            stories_id,
            sentence_number,
            sentence,
            media_id,
            publish_date,
            db_row_last_updated,
            language,
            is_dup
        FROM story_sentences_partitioned

        UNION ALL

        SELECT
            story_sentences_nonpartitioned_id AS story_sentences_id,
            stories_id,
            sentence_number,
            sentence,
            media_id,
            publish_date,
            db_row_last_updated,
            language,
            is_dup
        FROM story_sentences_nonpartitioned

    ) AS ss;


-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW story_sentences
    ALTER COLUMN story_sentences_id
    SET DEFAULT nextval(pg_get_serial_sequence('story_sentences_partitioned', 'story_sentences_partitioned_id')) + 1;


-- Trigger that implements INSERT / UPDATE / DELETE behavior on "story_sentences" view
CREATE OR REPLACE FUNCTION story_sentences_view_insert_update_delete() RETURNS trigger AS $$

DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "story_sentences_01")

BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- All new INSERTs go to partitioned table only
        SELECT stories_partition_name( 'story_sentences_partitioned', NEW.stories_id ) INTO target_table_name;
        EXECUTE '
            INSERT INTO ' || target_table_name || '
                SELECT $1.*
            ' USING NEW;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        -- UPDATE on both tables

        UPDATE story_sentences_partitioned
            SET stories_id = NEW.stories_id,
                sentence_number = NEW.sentence_number,
                sentence = NEW.sentence,
                media_id = NEW.media_id,
                publish_date = NEW.publish_date,
                db_row_last_updated = NEW.db_row_last_updated,
                language = NEW.language,
                is_dup = NEW.is_dup
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        UPDATE story_sentences_nonpartitioned
            SET stories_id = NEW.stories_id,
                sentence_number = NEW.sentence_number,
                sentence = NEW.sentence,
                media_id = NEW.media_id,
                publish_date = NEW.publish_date,
                db_row_last_updated = NEW.db_row_last_updated,
                language = NEW.language,
                is_dup = NEW.is_dup
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        -- DELETE from both tables

        DELETE FROM story_sentences_partitioned
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        DELETE FROM story_sentences_nonpartitioned
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER story_sentences_view_insert_update_delete_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE ON story_sentences
    FOR EACH ROW EXECUTE PROCEDURE story_sentences_view_insert_update_delete();



-- Copy a chunk of story sentences from a non-partitioned "story_sentences" to a
-- partitioned one; call this repeatedly to migrate all the data to the partitioned table
CREATE OR REPLACE FUNCTION copy_chunk_of_nonpartitioned_sentences_to_partitions(story_chunk_size INT)
RETURNS VOID AS $$

DECLARE
    copied_sentence_count INT;

BEGIN

    RAISE NOTICE 'Copying sentences of up to % stories to the partitioned table...', story_chunk_size;

    -- Kill all autovacuums before proceeding with DDL changes
    PERFORM pid
    FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
    WHERE backend_type = 'autovacuum worker'
      AND query ~ 'story_sentences';

    WITH deleted_rows AS (

        -- Fetch and delete sentences of selected stories
        DELETE FROM story_sentences_nonpartitioned
        WHERE stories_id IN (

            -- Pick unique story IDs from the returned resultset
            SELECT DISTINCT stories_id
            FROM (

                -- "SELECT DISTINCT stories_ID ... ORDER BY stories_id" from
                -- the non-partitioned table to copy them to the partitioned
                -- one worked fine at first but then got superslow. My guess is
                -- that it's because of the index bloat: the oldest story IDs
                -- got removed from the table (their tuples were marked as
                -- "deleted"), so after a while the database was struggling to
                -- get through all the dead rows to get to the next chunk of
                -- the live ones.
                --
                -- "SELECT DISTINCT" without the "ORDER BY" has a similar
                -- effect, probably because it uses the very same index. At
                -- least for now, the most effective strategy seems to do a
                -- sequential scan with a LIMIT on the table, collect an
                -- approximate amount of sentences for the given story count to
                -- copy, and then DISTINCT them as a separate step.
                SELECT stories_id
                FROM story_sentences_nonpartitioned

                -- Assume that a single story has 10 sentences + add some leeway
                LIMIT story_chunk_size * 15
            ) AS stories_and_sentences

        )
        RETURNING story_sentences_nonpartitioned.*

    ),

    deduplicated_rows AS (

        -- Deduplicate sentences: nonpartitioned table has weird duplicates,
        -- and the new index insists on (stories_id, sentence_number)
        -- uniqueness (which is a logical assumption to make)
        SELECT DISTINCT ON (stories_id, sentence_number) *
        FROM deleted_rows

        -- Assume that the sentence with the biggest story_sentences_id is the
        -- newest one and so is the one that we want
        ORDER BY stories_id, sentence_number, story_sentences_nonpartitioned_id DESC

    )

    -- INSERT into view to hit the partitioning trigger
    INSERT INTO story_sentences (
        story_sentences_id,
        stories_id,
        sentence_number,
        sentence,
        media_id,
        publish_date,
        db_row_last_updated,
        language,
        is_dup
    )
    SELECT
        story_sentences_nonpartitioned_id,
        stories_id,
        sentence_number,
        sentence,
        media_id,
        publish_date,
        db_row_last_updated,
        language,
        is_dup
    FROM deduplicated_rows;

    GET DIAGNOSTICS copied_sentence_count = ROW_COUNT;

    RAISE NOTICE 'Copied % sentences to the partitioned table.', copied_sentence_count;

END;
$$
LANGUAGE plpgsql;


-- update media stats table for new story. create the media / day row if needed.
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


create trigger stories_insert_story_media_stats after insert
    on stories for each row execute procedure insert_story_media_stats();


-- update media stats and story_sentences tables for updated story date
CREATE FUNCTION update_story_media_stats() RETURNS trigger AS $$

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


create trigger stories_update_story_media_stats after update
    on stories for each row execute procedure update_story_media_stats();


-- update media stats table for deleted story
CREATE FUNCTION delete_story_media_stats() RETURNS trigger AS $$
BEGIN

    UPDATE media_stats
    SET num_stories = num_stories - 1
    WHERE media_id = OLD.media_id
      AND stat_date = date_trunc( 'day', OLD.publish_date );

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


create trigger story_delete_story_media_stats after delete
    on stories for each row execute procedure delete_story_media_stats();

create table solr_imports (
    solr_imports_id     serial primary key,
    import_date         timestamp not null,
    full_import         boolean not null default false,
    num_stories         bigint
);

create index solr_imports_date on solr_imports ( import_date );

-- Extra stories to import into Solr, e.g.: for media with updated media.m.db_row_last_updated
create table solr_import_extra_stories (
    stories_id          int not null references stories on delete cascade
);
create index solr_import_extra_stories_story on solr_import_extra_stories ( stories_id );

-- log of all stories import into solr, with the import date
create table solr_imported_stories (
    stories_id          int not null references stories on delete cascade,
    import_date         timestamp not null
);

create index solr_imported_stories_story on solr_imported_stories ( stories_id );
create index solr_imported_stories_day on solr_imported_stories ( date_trunc( 'day', import_date ) );

create type topics_job_queue_type AS ENUM ( 'mc', 'public' );

create table topics (
    topics_id        serial primary key,
    name                    varchar(1024) not null,
    pattern                 text not null,
    solr_seed_query         text not null,
    solr_seed_query_run     boolean not null default false,
    description             text not null,
    media_type_tag_sets_id  int references tag_sets,
    max_iterations          int not null default 15,
    state                   text not null default 'created but not queued',
    message                 text null,
    is_public               boolean not null default false,
    is_logogram             boolean not null default false,
    start_date              date not null,
    end_date                date not null,

    -- this is the id of a crimson hexagon monitor, not an internal database id
    ch_monitor_id           bigint null,

    -- job queue to use for spider and snapshot jobs for this topic
    job_queue               topics_job_queue_type not null,

    -- max stories allowed in the topic
    max_stories             int not null,

    -- id of a twitter topic to use to generate snapshot twitter counts
    twitter_topics_id int null references topics on delete set null,

    -- if false, we should refuse to spider this topic because the use has not confirmed the new story query syntax
    is_story_index_ready     boolean not null default true

);

create unique index topics_name on topics( name );
create unique index topics_media_type_tag_set on topics( media_type_tag_sets_id );

create table topic_dates (
    topic_dates_id    serial primary key,
    topics_id        int not null references topics on delete cascade,
    start_date              date not null,
    end_date                date not null,
    boundary                boolean not null default 'false'
);

create table topics_media_map (
    topics_id       int not null references topics on delete cascade,
    media_id        int not null references media on delete cascade
);

create index topics_media_map_topic on topics_media_map ( topics_id );

create table topics_media_tags_map (
    topics_id       int not null references topics on delete cascade,
    tags_id         int not null references tags on delete cascade
);

create index topics_media_tags_map_topic on topics_media_tags_map ( topics_id );

create table topic_media_codes (
    topics_id        int not null references topics on delete cascade,
    media_id                int not null references media on delete cascade,
    code_type               text,
    code                    text
);

create table topic_merged_stories_map (
    source_stories_id       int not null references stories on delete cascade,
    target_stories_id       int not null references stories on delete cascade
);

create index topic_merged_stories_map_source on topic_merged_stories_map ( source_stories_id );
create index topic_merged_stories_map_story on topic_merged_stories_map ( target_stories_id );

create table topic_stories (
    topic_stories_id          serial primary key,
    topics_id                int not null references topics on delete cascade,
    stories_id                      int not null references stories on delete cascade,
    link_mined                      boolean default 'f',
    iteration                       int default 0,
    link_weight                     real,
    redirect_url                    text,
    valid_foreign_rss_story         boolean default false,
    link_mine_error                 text
);

create unique index topic_stories_sc on topic_stories ( stories_id, topics_id );
create index topic_stories_topic on topic_stories( topics_id );

-- topic links for which the http request failed
create table topic_dead_links (
    topic_dead_links_id   serial primary key,
    topics_id            int not null,
    stories_id                  int,
    url                         text not null
);

-- no foreign key constraints on topics_id and stories_id because
--   we have the combined foreign key constraint pointing to topic_stories
--   below
create table topic_links (
    topic_links_id        serial primary key,
    topics_id            int not null,
    stories_id                  int not null,
    url                         text not null,
    redirect_url                text,
    ref_stories_id              int references stories on delete cascade,
    link_spidered               boolean default 'f'
);

alter table topic_links add constraint topic_links_topic_story_stories_id
    foreign key ( stories_id, topics_id ) references topic_stories ( stories_id, topics_id )
    on delete cascade;

create unique index topic_links_scr on topic_links ( stories_id, topics_id, ref_stories_id );
create index topic_links_topic on topic_links ( topics_id );
create index topic_links_ref_story on topic_links ( ref_stories_id );

CREATE VIEW topic_links_cross_media AS
    SELECT s.stories_id,
           sm.name AS media_name,
           r.stories_id AS ref_stories_id,
           rm.name AS ref_media_name,
           cl.url AS url,
           cs.topics_id,
           cl.topic_links_id
    FROM media sm,
         media rm,
         topic_links cl,
         stories s,
         stories r,
         topic_stories cs
    WHERE cl.ref_stories_id != cl.stories_id
      AND s.stories_id = cl.stories_id
      AND cl.ref_stories_id = r.stories_id
      AND s.media_id != r.media_id
      AND sm.media_id = s.media_id
      AND rm.media_id = r.media_id
      AND cs.stories_id = cl.ref_stories_id
      AND cs.topics_id = cl.topics_id;

create table topic_seed_urls (
    topic_seed_urls_id        serial primary key,
    topics_id                int not null references topics on delete cascade,
    url                             text,
    source                          text,
    stories_id                      int references stories on delete cascade,
    processed                       boolean not null default false,
    assume_match                    boolean not null default false,
    content                         text,
    guid                            text,
    title                           text,
    publish_date                    text
);

create index topic_seed_urls_topic on topic_seed_urls( topics_id );
create index topic_seed_urls_url on topic_seed_urls( url );
create index topic_seed_urls_story on topic_seed_urls ( stories_id );

create table topic_fetch_urls(
    topic_fetch_urls_id         bigserial primary key,
    topics_id                   int not null references topics on delete cascade,
    url                         text not null,
    code                        int,
    fetch_date                  timestamp,
    state                       text not null,
    message                     text,
    stories_id                  int references stories on delete cascade,
    assume_match                boolean not null default false,
    topic_links_id              int references topic_links on delete cascade
);

create index topic_fetch_urls_pending on topic_fetch_urls(topics_id) where state = 'pending';
create index topic_fetch_urls_url on topic_fetch_urls(md5(url));
create index topic_fetch_urls_link on topic_fetch_urls(topic_links_id);

create table topic_ignore_redirects (
    topic_ignore_redirects_id     serial primary key,
    url                                 varchar( 1024 )
);

create index topic_ignore_redirects_url on topic_ignore_redirects ( url );

create type bot_policy_type AS ENUM ( 'all', 'no bots', 'only bots');

create table snapshots (
    snapshots_id            serial primary key,
    topics_id               int not null references topics on delete cascade,
    snapshot_date           timestamp not null,
    start_date              timestamp not null,
    end_date                timestamp not null,
    note                    text,
    state                   text not null default 'queued',
    message                 text null,
    searchable              boolean not null default false,
    bot_policy              bot_policy_type null
);

create index snapshots_topic on snapshots ( topics_id );

create type snap_period_type AS ENUM ( 'overall', 'weekly', 'monthly', 'custom' );

create type focal_technique_type as enum ( 'Boolean Query' );

create table focal_set_definitions (
    focal_set_definitions_id    serial primary key,
    topics_id                   int not null references topics on delete cascade,
    name                        text not null,
    description                 text null,
    focal_technique             focal_technique_type not null
);

create unique index focal_set_definitions_topic_name on focal_set_definitions ( topics_id, name );

create table focus_definitions (
    focus_definitions_id        serial primary key,
    focal_set_definitions_id    int not null references focal_set_definitions on delete cascade,
    name                        text not null,
    description                 text null,
    arguments                   json not null
);

create unique index focus_definition_set_name on focus_definitions ( focal_set_definitions_id, name );

create table focal_sets (
    focal_sets_id               serial primary key,
    snapshots_id                int not null references snapshots,
    name                        text not null,
    description                 text null,
    focal_technique             focal_technique_type not null
);

create unique index focal_set_snapshot on focal_sets ( snapshots_id, name );

create table foci (
    foci_id                     serial primary key,
    focal_sets_id               int not null references focal_sets on delete cascade,
    name                        text not null,
    description                 text null,
    arguments                   json not null
);

create unique index foci_set_name on foci ( focal_sets_id, name );


-- individual timespans within a snapshot
create table timespans (
    timespans_id serial primary key,
    snapshots_id            int not null references snapshots on delete cascade,
    foci_id     int null references foci,
    start_date                      timestamp not null,
    end_date                        timestamp not null,
    period                          snap_period_type not null,
    model_r2_mean                   float,
    model_r2_stddev                 float,
    model_num_media                 int,
    story_count                     int not null,
    story_link_count                int not null,
    medium_count                    int not null,
    medium_link_count               int not null,
    tweet_count                     int not null,

    tags_id                         int references tags -- keep on cascade to avoid accidental deletion
);

create index timespans_snapshot on timespans ( snapshots_id );

create table timespan_files (
    timespan_files_id                   serial primary key,
    timespans_id int not null references timespans on delete cascade,
    file_name                       text,
    file_content                    text
);

create index timespan_files_timespan on timespan_files ( timespans_id );

create table snap_files (
    snap_files_id                     serial primary key,
    snapshots_id            int not null references snapshots on delete cascade,
    file_name                       text,
    file_content                    text
);

create index snap_files_cd on snap_files ( snapshots_id );


-- schema to hold the various snapshot snapshot tables
CREATE SCHEMA snap;


CREATE OR REPLACE LANGUAGE plpgsql;

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;


-- create a table for each of these tables to hold a snapshot of stories relevant
-- to a topic for each snapshot for that topic
create table snap.stories (
    snapshots_id        int             not null references snapshots on delete cascade,
    stories_id                  int,
    media_id                    int             not null,
    url                         varchar(1024)   not null,
    guid                        varchar(1024)   not null,
    title                       text            not null,
    publish_date                timestamp       not null,
    collect_date                timestamp       not null,
    full_text_rss               boolean         not null default 'f',
    language                    varchar(3)      null   -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
);
create index stories_id on snap.stories ( snapshots_id, stories_id );

-- stats for various externally dervied statistics about a story.
create table story_statistics (
    story_statistics_id         serial      primary key,
    stories_id                  int         not null references stories on delete cascade,

    facebook_share_count        int         null,
    facebook_comment_count      int         null,
    facebook_api_collect_date   timestamp   null,
    facebook_api_error          text        null
);

create unique index story_statistics_story on story_statistics ( stories_id );


-- stats for deprecated Twitter share counts
create table story_statistics_twitter (
    story_statistics_id         serial      primary key,
    stories_id                  int         not null references stories on delete cascade,

    twitter_url_tweet_count     int         null,
    twitter_api_collect_date    timestamp   null,
    twitter_api_error           text        null
);

create unique index story_statistics_twitter_story on story_statistics_twitter ( stories_id );


create table snap.topic_stories (
    snapshots_id            int not null references snapshots on delete cascade,
    topic_stories_id          int,
    topics_id                int not null,
    stories_id                      int not null,
    link_mined                      boolean,
    iteration                       int,
    link_weight                     real,
    redirect_url                    text,
    valid_foreign_rss_story         boolean
);
create index topic_stories_id on snap.topic_stories ( snapshots_id, stories_id );

create table snap.topic_links_cross_media (
    snapshots_id        int not null references snapshots on delete cascade,
    topic_links_id        int,
    topics_id            int not null,
    stories_id                  int not null,
    url                         text not null,
    ref_stories_id              int
);
create index topic_links_story on snap.topic_links_cross_media ( snapshots_id, stories_id );
create index topic_links_ref on snap.topic_links_cross_media ( snapshots_id, ref_stories_id );

create table snap.topic_media_codes (
    snapshots_id    int not null references snapshots on delete cascade,
    topics_id        int not null,
    media_id                int not null,
    code_type               text,
    code                    text
);
create index topic_media_codes_medium on snap.topic_media_codes ( snapshots_id, media_id );

create table snap.media (
    snapshots_id    int not null references snapshots on delete cascade,
    media_id                int,
    url                     varchar(1024)   not null,
    name                    varchar(128)    not null,
    moderated               boolean         not null,
    moderation_notes        text            null,
    full_text_rss           boolean,
    foreign_rss_links       boolean         not null default( false ),
    dup_media_id            int             null,
    is_not_dup              boolean         null
);
create index media_id on snap.media ( snapshots_id, media_id );

create table snap.media_tags_map (
    snapshots_id    int not null    references snapshots on delete cascade,
    media_tags_map_id       int,
    media_id                int             not null,
    tags_id                 int             not null
);
create index media_tags_map_medium on snap.media_tags_map ( snapshots_id, media_id );
create index media_tags_map_tag on snap.media_tags_map ( snapshots_id, tags_id );

create table snap.stories_tags_map
(
    snapshots_id    int not null    references snapshots on delete cascade,
    stories_tags_map_id     int,
    stories_id              int,
    tags_id                 int
);
create index stories_tags_map_story on snap.stories_tags_map ( snapshots_id, stories_id );
create index stories_tags_map_tag on snap.stories_tags_map ( snapshots_id, tags_id );

create table snap.tags (
    snapshots_id    int not null    references snapshots on delete cascade,
    tags_id                 int,
    tag_sets_id             int,
    tag                     varchar(512),
    label                   text,
    description             text
);
create index tags_id on snap.tags ( snapshots_id, tags_id );

create table snap.tag_sets (
    snapshots_id    int not null    references snapshots on delete cascade,
    tag_sets_id             int,
    name                    varchar(512),
    label                   text,
    description             text
);
create index tag_sets_id on snap.tag_sets ( snapshots_id, tag_sets_id );

-- story -> story links within a timespan
create table snap.story_links (
    timespans_id         int not null
                                            references timespans on delete cascade,
    source_stories_id                       int not null,
    ref_stories_id                          int not null
);

-- TODO: add complex foreign key to check that *_stories_id exist for the snapshot stories snapshot
create index story_links_source on snap.story_links( timespans_id, source_stories_id );
create index story_links_ref on snap.story_links( timespans_id, ref_stories_id );

-- link counts for stories within a timespan
create table snap.story_link_counts (
    timespans_id         int not null
                                            references timespans on delete cascade,
    stories_id                              int not null,
    media_inlink_count                      int not null,
    inlink_count                            int not null,
    outlink_count                           int not null,

    facebook_share_count                    int null,

    simple_tweet_count                      int null,
    normalized_tweet_count                  float null
);

-- TODO: add complex foreign key to check that stories_id exists for the snapshot stories snapshot
create index story_link_counts_ts on snap.story_link_counts ( timespans_id, stories_id );
create index story_link_counts_story on snap.story_link_counts ( stories_id );

-- links counts for media within a timespan
create table snap.medium_link_counts (
    timespans_id int not null
                                    references timespans on delete cascade,
    media_id                        int not null,
    sum_media_inlink_count          int not null,
    media_inlink_count              int not null,
    inlink_count                    int not null,
    outlink_count                   int not null,
    story_count                     int not null,

    facebook_share_count            int null,

    simple_tweet_count              int null,
    normalized_tweet_count          float null
);

-- TODO: add complex foreign key to check that media_id exists for the snapshot media snapshot
create index medium_link_counts_medium on snap.medium_link_counts ( timespans_id, media_id );

create table snap.medium_links (
    timespans_id int not null
                                    references timespans on delete cascade,
    source_media_id                 int not null,
    ref_media_id                    int not null,
    link_count                      int not null
);

-- TODO: add complex foreign key to check that *_media_id exist for the snapshot media snapshot
create index medium_links_source on snap.medium_links( timespans_id, source_media_id );
create index medium_links_ref on snap.medium_links( timespans_id, ref_media_id );

create table snap.daily_date_counts (
    snapshots_id            int not null references snapshots on delete cascade,
    publish_date                    date not null,
    story_count                     int not null,
    tags_id                         int
);

create index daily_date_counts_date on snap.daily_date_counts( snapshots_id, publish_date );
create index daily_date_counts_tag on snap.daily_date_counts( snapshots_id, tags_id );

create table snap.weekly_date_counts (
    snapshots_id            int not null references snapshots on delete cascade,
    publish_date                    date not null,
    story_count                     int not null,
    tags_id                         int
);

create index weekly_date_counts_date on snap.weekly_date_counts( snapshots_id, publish_date );
create index weekly_date_counts_tag on snap.weekly_date_counts( snapshots_id, tags_id );

-- create a mirror of the stories table with the stories for each topic.  this is to make
-- it much faster to query the stories associated with a given topic, rather than querying the
-- contested and bloated stories table.  only inserts and updates on stories are triggered, because
-- deleted cascading stories_id and topics_id fields take care of deletes.
create table snap.live_stories (
    topics_id            int             not null references topics on delete cascade,
    topic_stories_id      int             not null references topic_stories on delete cascade,
    stories_id                  int             not null references stories on delete cascade,
    media_id                    int             not null,
    url                         varchar(1024)   not null,
    guid                        varchar(1024)   not null,
    title                       text            not null,
    description                 text            null,
    publish_date                timestamp       not null,
    collect_date                timestamp       not null,
    full_text_rss               boolean         not null default 'f',
    language                    varchar(3)      null,   -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
    db_row_last_updated         timestamp with time zone null
);

create index live_story_topic on snap.live_stories ( topics_id );
create unique index live_stories_story on snap.live_stories ( topics_id, stories_id );
create index live_stories_story_solo on snap.live_stories ( stories_id );
create index live_stories_topic_story on snap.live_stories ( topic_stories_id );


create function insert_live_story() returns trigger as $insert_live_story$
    begin

        insert into snap.live_stories
            ( topics_id, topic_stories_id, stories_id, media_id, url, guid, title, description,
                publish_date, collect_date, full_text_rss, language,
                db_row_last_updated )
            select NEW.topics_id, NEW.topic_stories_id, NEW.stories_id, s.media_id, s.url, s.guid,
                    s.title, s.description, s.publish_date, s.collect_date, s.full_text_rss, s.language,
                    s.db_row_last_updated
                from topic_stories cs
                    join stories s on ( cs.stories_id = s.stories_id )
                where
                    cs.stories_id = NEW.stories_id and
                    cs.topics_id = NEW.topics_id;

        return NEW;
    END;
$insert_live_story$ LANGUAGE plpgsql;

create trigger topic_stories_insert_live_story after insert on topic_stories
    for each row execute procedure insert_live_story();

create or replace function update_live_story() returns trigger as $update_live_story$
    begin

        update snap.live_stories set
                media_id = NEW.media_id,
                url = NEW.url,
                guid = NEW.guid,
                title = NEW.title,
                description = NEW.description,
                publish_date = NEW.publish_date,
                collect_date = NEW.collect_date,
                full_text_rss = NEW.full_text_rss,
                language = NEW.language,
                db_row_last_updated = NEW.db_row_last_updated
            where
                stories_id = NEW.stories_id;

        return NEW;
    END;
$update_live_story$ LANGUAGE plpgsql;

create trigger stories_update_live_story after update on stories
    for each row execute procedure update_live_story();


--
-- Snapshot word2vec models
--
CREATE TABLE snap.word2vec_models (
    word2vec_models_id  SERIAL      PRIMARY KEY,
    object_id           INTEGER     NOT NULL REFERENCES snapshots (snapshots_id) ON DELETE CASCADE,
    creation_date       TIMESTAMP   NOT NULL DEFAULT NOW()
);

-- We'll need to find the latest word2vec model
CREATE INDEX snap_word2vec_models_object_id_creation_date ON snap.word2vec_models (object_id, creation_date);

CREATE TABLE snap.word2vec_models_data (
    word2vec_models_data_id SERIAL      PRIMARY KEY,
    object_id               INTEGER     NOT NULL
                                            REFERENCES snap.word2vec_models (word2vec_models_id)
                                            ON DELETE CASCADE,
    raw_data                BYTEA       NOT NULL
);
CREATE UNIQUE INDEX snap_word2vec_models_data_object_id ON snap.word2vec_models_data (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE snap.word2vec_models_data
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;


create table processed_stories (
    processed_stories_id        bigserial          primary key,
    stories_id                  int             not null references stories on delete cascade
);

create index processed_stories_story on processed_stories ( stories_id );

CREATE TRIGGER processed_stories_update_stories_last_updated_trigger
    AFTER INSERT OR UPDATE OR DELETE ON processed_stories
    FOR EACH ROW EXECUTE PROCEDURE update_stories_updated_time_by_stories_id_trigger();

-- list of stories that have been scraped and the source
create table scraped_stories (
    scraped_stories_id      serial primary key,
    stories_id              int not null references stories on delete cascade,
    import_module           text not null
);

create index scraped_stories_story on scraped_stories ( stories_id );

-- dates on which feeds have been scraped with MediaWords::ImportStories and the module used for scraping
create table scraped_feeds (
    feed_scrapes_id         serial primary key,
    feeds_id                int not null references feeds on delete cascade,
    scrape_date             timestamp not null default now(),
    import_module           text not null
);

create index scraped_feeds_feed on scraped_feeds ( feeds_id );

create view feedly_unscraped_feeds as
    select f.*
        from feeds f
            left join scraped_feeds sf on
                ( f.feeds_id = sf.feeds_id and sf.import_module = 'MediaWords::ImportStories::Feedly' )
        where
            f.feed_type = 'syndicated' and
            f.feed_status = 'active' and
            sf.feeds_id is null;


create table topic_query_story_searches_imported_stories_map (
    topics_id            int not null references topics on delete cascade,
    stories_id                  int not null references stories on delete cascade
);

create index cqssism_c on topic_query_story_searches_imported_stories_map ( topics_id );
create index cqssism_s on topic_query_story_searches_imported_stories_map ( stories_id );


CREATE VIEW stories_collected_in_past_day AS
    SELECT *
    FROM stories
    WHERE collect_date > now() - interval '1 day';


CREATE VIEW downloads_to_be_extracted as select * from downloads where extracted = 'f' and state = 'success' and type = 'content';

CREATE VIEW downloads_in_past_day as select * from downloads where download_time > now() - interval '1 day';
CREATE VIEW downloads_with_error_in_past_day as select * from downloads_in_past_day where state = 'error';

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


--
-- Authentication
--

-- List of users
CREATE TABLE auth_users (
    auth_users_id   SERIAL  PRIMARY KEY,

    -- Emails are case-insensitive
    email           CITEXT  UNIQUE NOT NULL,

    -- Salted hash of a password (with Crypt::SaltedHash, algorithm => 'SHA-256', salt_len=>64)
    password_hash   TEXT    NOT NULL CONSTRAINT password_hash_sha256 CHECK(LENGTH(password_hash) = 137),

    full_name       TEXT    NOT NULL,
    notes           TEXT    NULL,

    active          BOOLEAN NOT NULL DEFAULT true,

    -- Salted hash of a password reset token (with Crypt::SaltedHash, algorithm => 'SHA-256',
    -- salt_len=>64) or NULL
    password_reset_token_hash TEXT  UNIQUE NULL
        CONSTRAINT password_reset_token_hash_sha256
            CHECK(LENGTH(password_reset_token_hash) = 137 OR password_reset_token_hash IS NULL),

    -- Timestamp of the last unsuccessful attempt to log in; used for delaying successive
    -- attempts in order to prevent brute-force attacks
    last_unsuccessful_login_attempt     TIMESTAMP NOT NULL DEFAULT TIMESTAMP 'epoch',

    created_date                        timestamp not null default now(),

    max_topic_stories                   int not null default 100000
);


-- Generate random API key
CREATE FUNCTION generate_api_key() RETURNS VARCHAR(64) LANGUAGE plpgsql AS $$
DECLARE
    api_key VARCHAR(64);
BEGIN
    -- pgcrypto's functions are being referred with public schema prefix to make pg_upgrade work
    SELECT encode(public.digest(public.gen_random_bytes(256), 'sha256'), 'hex') INTO api_key;
    RETURN api_key;
END;
$$;


CREATE TABLE auth_user_api_keys (
    auth_user_api_keys_id SERIAL      PRIMARY KEY,
    auth_users_id         INT         NOT NULL REFERENCES auth_users ON DELETE CASCADE,

    -- API key
    -- (must be 64 bytes in order to prevent someone from resetting it to empty string somehow)
    api_key               VARCHAR(64) UNIQUE NOT NULL
                                          DEFAULT generate_api_key()
                                          CONSTRAINT api_key_64_characters
                                          CHECK( length( api_key ) = 64 ),

    -- If set, API key is limited to only this IP address
    ip_address            INET        NULL
);

CREATE UNIQUE INDEX auth_user_api_keys_api_key_ip_address
    ON auth_user_api_keys (api_key, ip_address);


-- Autogenerate non-IP limited API key
CREATE OR REPLACE FUNCTION auth_user_api_keys_add_non_ip_limited_api_key() RETURNS trigger AS
$$
BEGIN

    INSERT INTO auth_user_api_keys (auth_users_id, api_key, ip_address)
    VALUES (
        NEW.auth_users_id,
        DEFAULT,  -- Autogenerated API key
        NULL      -- Not limited by IP address
    );
    RETURN NULL;

END;
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER auth_user_api_keys_add_non_ip_limited_api_key
    AFTER INSERT ON auth_users
    FOR EACH ROW EXECUTE PROCEDURE auth_user_api_keys_add_non_ip_limited_api_key();


-- List of roles the users can perform
CREATE TABLE auth_roles (
    auth_roles_id   SERIAL  PRIMARY KEY,
    role            TEXT    UNIQUE NOT NULL CONSTRAINT role_name_can_not_contain_spaces CHECK(role NOT LIKE '% %'),
    description     TEXT    NOT NULL
);

-- Map of user IDs and roles that are allowed to each of the user
CREATE TABLE auth_users_roles_map (
    auth_users_roles_map_id SERIAL      PRIMARY KEY,
    auth_users_id           INTEGER     NOT NULL REFERENCES auth_users(auth_users_id)
                                        ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE,
    auth_roles_id           INTEGER     NOT NULL REFERENCES auth_roles(auth_roles_id)
                                        ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE,
    CONSTRAINT no_duplicate_entries UNIQUE (auth_users_id, auth_roles_id)
);
CREATE INDEX auth_users_roles_map_auth_users_id_auth_roles_id
    ON auth_users_roles_map (auth_users_id, auth_roles_id);

-- Authentication roles (keep in sync with MediaWords::DBI::Auth::Roles)
INSERT INTO auth_roles (role, description) VALUES
    ('admin', 'Do everything, including editing users.'),
    ('admin-readonly', 'Read access to admin interface.'),
    ('media-edit', 'Add / edit media; includes feeds.'),
    ('stories-edit', 'Add / edit stories.'),
    ('tm', 'Topic mapper; includes media and story editing'),
    ('tm-readonly', 'Topic mapper; excludes media and story editing'),
    ('stories-api', 'Access to the stories api'),
    ('search', 'Access to the /search pages');


--
-- User request daily counts
--
CREATE TABLE auth_user_request_daily_counts (

    auth_user_request_daily_counts_id  SERIAL  PRIMARY KEY,

    -- User's email (does *not* reference auth_users.email because the user
    -- might be deleted)
    email                   CITEXT  NOT NULL,

    -- Day (request timestamp, date_truncated to a day)
    day                     DATE    NOT NULL,

    -- Number of requests
    requests_count          INTEGER NOT NULL,

    -- Number of requested items
    requested_items_count   INTEGER NOT NULL

);

-- Single index to enforce upsert uniqueness
CREATE UNIQUE INDEX auth_user_request_daily_counts_email_day ON auth_user_request_daily_counts (email, day);


-- User limits for logged + throttled controller actions
CREATE TABLE auth_user_limits (

    auth_user_limits_id             SERIAL      NOT NULL,

    auth_users_id                   INTEGER     NOT NULL UNIQUE REFERENCES auth_users(auth_users_id)
                                                ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE,

    -- Request limit (0 or belonging to 'admin' / 'admin-readonly' group = no
    -- limit)
    weekly_requests_limit           INTEGER     NOT NULL DEFAULT 10000,

    -- Requested items (stories) limit (0 or belonging to 'admin' /
    -- 'admin-readonly' group = no limit)
    weekly_requested_items_limit    INTEGER     NOT NULL DEFAULT 100000

);

CREATE UNIQUE INDEX auth_user_limits_auth_users_id ON auth_user_limits (auth_users_id);

-- Set the default limits for newly created users
CREATE OR REPLACE FUNCTION auth_users_set_default_limits() RETURNS trigger AS
$$
BEGIN

    INSERT INTO auth_user_limits (auth_users_id) VALUES (NEW.auth_users_id);
    RETURN NULL;

END;
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER auth_users_set_default_limits
    AFTER INSERT ON auth_users
    FOR EACH ROW EXECUTE PROCEDURE auth_users_set_default_limits();


-- Add helper function to find out weekly request / request items usage for a user
CREATE OR REPLACE FUNCTION auth_user_limits_weekly_usage(user_email CITEXT)
RETURNS TABLE(email CITEXT, weekly_requests_sum BIGINT, weekly_requested_items_sum BIGINT) AS
$$

    SELECT auth_users.email,
           COALESCE(SUM(auth_user_request_daily_counts.requests_count), 0) AS weekly_requests_sum,
           COALESCE(SUM(auth_user_request_daily_counts.requested_items_count), 0) AS weekly_requested_items_sum
    FROM auth_users
        LEFT JOIN auth_user_request_daily_counts
            ON auth_users.email = auth_user_request_daily_counts.email
            AND auth_user_request_daily_counts.day > DATE_TRUNC('day', NOW())::date - INTERVAL '1 week'
    WHERE auth_users.email = $1
    GROUP BY auth_users.email;

$$
LANGUAGE SQL;

CREATE TABLE auth_users_tag_sets_permissions (
    auth_users_tag_sets_permissions_id SERIAL  PRIMARY KEY,
    auth_users_id                      integer references auth_users not null,
    tag_sets_id                        integer references tag_sets not null,
    apply_tags                         boolean NOT NULL,
    create_tags                        boolean NOT NULL,
    edit_tag_set_descriptors           boolean NOT NULL,
    edit_tag_descriptors               boolean NOT NULL
);

CREATE UNIQUE INDEX auth_users_tag_sets_permissions_auth_user_tag_set on  auth_users_tag_sets_permissions( auth_users_id , tag_sets_id );
CREATE INDEX auth_users_tag_sets_permissions_auth_user         on  auth_users_tag_sets_permissions( auth_users_id );
CREATE INDEX auth_users_tag_sets_permissions_tag_sets          on  auth_users_tag_sets_permissions( tag_sets_id );


-- Users to subscribe to groups.io mailing list
CREATE TABLE auth_users_subscribe_to_newsletter (
    auth_users_subscribe_to_newsletter_id SERIAL  PRIMARY KEY,
    auth_users_id                         INTEGER NOT NULL REFERENCES auth_users (auth_users_id) ON DELETE CASCADE
);


--
-- Activity log
--

CREATE TABLE activities (
    activities_id       SERIAL          PRIMARY KEY,

    -- Activity's name (e.g. "media_edit", "story_edit", etc.)
    name                VARCHAR(255)    NOT NULL
                                        CONSTRAINT activities_name_can_not_contain_spaces CHECK(name NOT LIKE '% %'),

    -- When did the activity happen
    creation_date       TIMESTAMP       NOT NULL DEFAULT LOCALTIMESTAMP,

    -- User that executed the activity, either:
    --     * user's email from "auth_users.email" (e.g. "lvaliukas@cyber.law.harvard.edu", or
    --     * username that initiated the action (e.g. "system:lvaliukas")
    -- (store user's email instead of ID in case the user gets deleted)
    user_identifier     CITEXT          NOT NULL,

    -- Indexed ID of the object that was modified in some way by the activity
    -- (e.g. media's ID "media_edit" or story's ID in "story_edit")
    object_id           BIGINT          NULL,

    -- User-provided reason explaining why the activity was made
    reason              TEXT            NULL,

    -- Other free-form data describing the action in the JSON format
    -- (e.g.: '{ "field": "name", "old_value": "Foo.", "new_value": "Bar." }')
    -- FIXME: has potential to use 'JSON' type instead of 'TEXT' in
    -- PostgreSQL 9.2+
    description_json    TEXT            NOT NULL DEFAULT '{ }'

);

CREATE INDEX activities_name ON activities (name);
CREATE INDEX activities_creation_date ON activities (creation_date);
CREATE INDEX activities_user_identifier ON activities (user_identifier);
CREATE INDEX activities_object_id ON activities (object_id);


CREATE OR REPLACE FUNCTION story_is_english_and_has_sentences(param_stories_id INT)
RETURNS boolean AS $$
DECLARE
    story record;
BEGIN

    SELECT stories_id, media_id, language INTO story from stories where stories_id = param_stories_id;

    IF NOT ( story.language = 'en' or story.language is null ) THEN
        RETURN FALSE;

    ELSEIF NOT EXISTS ( SELECT 1 FROM story_sentences WHERE stories_id = param_stories_id ) THEN
        RETURN FALSE;

    END IF;

    RETURN TRUE;

END;
$$
LANGUAGE 'plpgsql';


-- Helper to find corrupted sequences (the ones in which the primary key's sequence value > MAX(primary_key))
CREATE OR REPLACE FUNCTION find_corrupted_sequences()
RETURNS TABLE(tablename VARCHAR, maxid BIGINT, sequenceval BIGINT)
AS $BODY$
DECLARE
    r RECORD;
BEGIN

    SET client_min_messages TO WARNING;
    DROP TABLE IF EXISTS temp_corrupted_sequences;
    CREATE TEMPORARY TABLE temp_corrupted_sequences (
        tablename VARCHAR NOT NULL UNIQUE,
        maxid BIGINT,
        sequenceval BIGINT
    ) ON COMMIT DROP;
    SET client_min_messages TO NOTICE;

    FOR r IN (

        -- Get all tables, their primary keys and serial sequence names
        SELECT t.relname AS tablename,
               primarykey AS idcolumn,
               pg_get_serial_sequence(t.relname, primarykey) AS serialsequence
        FROM pg_constraint AS c
            JOIN pg_class AS t ON c.conrelid = t.oid
            JOIN pg_namespace nsp ON nsp.oid = t.relnamespace
            JOIN (
                SELECT a.attname AS primarykey,
                       i.indrelid
                FROM pg_index AS i
                    JOIN pg_attribute AS a
                        ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
                WHERE i.indisprimary
            ) AS pkey ON pkey.indrelid = t.relname::regclass
        WHERE conname LIKE '%_pkey'
          AND nsp.nspname = CURRENT_SCHEMA()
          AND t.relname NOT IN (
            'story_similarities_100_short',
            'url_discovery_counts'
          )
        ORDER BY t.relname

    )
    LOOP

        -- Filter out the tables that have their max ID bigger than the last
        -- sequence value
        EXECUTE '
            INSERT INTO temp_corrupted_sequences
                SELECT tablename,
                       maxid,
                       sequenceval
                FROM (
                    SELECT ''' || r.tablename || ''' AS tablename,
                           MAX(' || r.idcolumn || ') AS maxid,
                           ( SELECT last_value FROM ' || r.serialsequence || ') AS sequenceval
                    FROM ' || r.tablename || '
                ) AS id_and_sequence
                WHERE maxid > sequenceval
        ';

    END LOOP;

    RETURN QUERY SELECT * FROM temp_corrupted_sequences ORDER BY tablename;

END
$BODY$
LANGUAGE 'plpgsql';


-- Copy of "feeds" table from yesterday; used for generating reports for rescraping efforts
CREATE TABLE feeds_from_yesterday (
    feeds_id            INT                 NOT NULL,
    media_id            INT                 NOT NULL,
    name                VARCHAR(512)        NOT NULL,
    url                 VARCHAR(1024)       NOT NULL,
    feed_type           feed_feed_type      NOT NULL,
    feed_status         feed_feed_status    NOT NULL
);

CREATE INDEX feeds_from_yesterday_feeds_id ON feeds_from_yesterday(feeds_id);
CREATE INDEX feeds_from_yesterday_media_id ON feeds_from_yesterday(media_id);
CREATE INDEX feeds_from_yesterday_name ON feeds_from_yesterday(name);
CREATE UNIQUE INDEX feeds_from_yesterday_url ON feeds_from_yesterday(url, media_id);

--
-- Update "feeds_from_yesterday" with a new set of feeds
--
CREATE OR REPLACE FUNCTION update_feeds_from_yesterday() RETURNS VOID AS $$
BEGIN

    DELETE FROM feeds_from_yesterday;
    INSERT INTO feeds_from_yesterday (feeds_id, media_id, name, url, feed_type, feed_status)
        SELECT feeds_id, media_id, name, url, feed_type, feed_status
        FROM feeds;

END;
$$
LANGUAGE 'plpgsql';

--
-- Print out a diff between "feeds" and "feeds_from_yesterday"
--
CREATE OR REPLACE FUNCTION rescraping_changes() RETURNS VOID AS
$$
DECLARE
    r_count RECORD;
    r_media RECORD;
    r_feed RECORD;
BEGIN

    -- Check if media exists
    IF NOT EXISTS (
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
                    SELECT feeds_id, media_id, feed_type, feed_status, url FROM feeds_from_yesterday
                    EXCEPT
                    SELECT feeds_id, media_id, feed_type, feed_status, url FROM feeds
                ) UNION ALL (
                    SELECT feeds_id, media_id, feed_type, feed_status, url FROM feeds
                    EXCEPT
                    SELECT feeds_id, media_id, feed_type, feed_status, url FROM feeds_from_yesterday
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

               feeds_before.name AS before_name,
               feeds_before.url AS before_url,
               feeds_before.feed_type AS before_feed_type,
               feeds_before.feed_status AS before_feed_status,

               feeds_after.name AS after_name,
               feeds_after.url AS after_url,
               feeds_after.feed_type AS after_feed_type,
               feeds_after.feed_status AS after_feed_status

        FROM feeds_from_yesterday AS feeds_before
            INNER JOIN feeds AS feeds_after ON (
                feeds_before.feeds_id = feeds_after.feeds_id
                AND (
                    -- Don't compare "name" because it's insignificant
                    feeds_before.url != feeds_after.url
                 OR feeds_before.feed_type != feeds_after.feed_type
                 OR feeds_before.feed_status != feeds_after.feed_status
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
        EXISTS (
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
        EXISTS (
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
            RAISE NOTICE '    ADDED feed: feeds_id=%, feed_type=%, feed_status=%, name="%", url="%"',
                r_feed.feeds_id,
                r_feed.feed_type,
                r_feed.feed_status,
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
            RAISE NOTICE '    DELETED feed: feeds_id=%, feed_type=%, feed_status=%, name="%", url="%"',
                r_feed.feeds_id,
                r_feed.feed_type,
                r_feed.feed_status,
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
            RAISE NOTICE '        BEFORE: feed_type=%, feed_status=%, name="%", url="%"',
                r_feed.before_feed_type,
                r_feed.before_feed_status,
                r_feed.before_name,
                r_feed.before_url;
            RAISE NOTICE '        AFTER:  feed_type=%, feed_status=%, name="%", url="%"',
                r_feed.after_feed_type,
                r_feed.after_feed_status,
                r_feed.after_name,
                r_feed.after_url;
        END LOOP;

        RAISE NOTICE '';

    END LOOP;

END;
$$
LANGUAGE 'plpgsql';


--
-- Stories without Readability tag
--
CREATE TABLE IF NOT EXISTS stories_without_readability_tag (
    stories_id BIGINT NOT NULL REFERENCES stories (stories_id)
);
CREATE INDEX stories_without_readability_tag_stories_id
    ON stories_without_readability_tag (stories_id);

-- Fill in the table manually with:
--
-- INSERT INTO scratch.stories_without_readability_tag (stories_id)
--     SELECT stories.stories_id
--     FROM stories
--         LEFT JOIN stories_tags_map
--             ON stories.stories_id = stories_tags_map.stories_id

--             -- "extractor_version:readability-lxml-0.3.0.5"
--             AND stories_tags_map.tags_id = 8929188

--     -- No Readability tag
--     WHERE stories_tags_map.tags_id IS NULL
--     ;

-- implements link_id as documented in the topics api spec
create table api_links (
    api_links_id        bigserial primary key,
    path                text not null,
    params_json         text not null,
    next_link_id        bigint null references api_links on delete set null deferrable,
    previous_link_id    bigint null references api_links on delete set null deferrable
);

create unique index api_links_params on api_links ( path, md5( params_json ) );

-- Create missing partitions for partitioned tables
CREATE OR REPLACE FUNCTION create_missing_partitions()
RETURNS VOID AS
$$
BEGIN

    RAISE NOTICE 'Creating partitions in "stories_tags_map" table...';
    PERFORM stories_tags_map_create_partitions();

    RAISE NOTICE 'Creating partitions in "story_sentences_partitioned" table...';
    PERFORM story_sentences_create_partitions();


END;
$$
LANGUAGE plpgsql;

create view controversies as select topics_id controversies_id, * from topics;
create view controversy_dumps as
    select snapshots_id controversy_dumps_id, topics_id controversies_id, snapshot_date dump_date, * from snapshots;
create view controversy_dump_time_slices as
    select timespans_id controversy_dump_time_slices_id, snapshots_id controversy_dumps_id, foci_id controversy_query_slices_id, *
        from timespans;

-- cached extractor results for extraction jobs with use_cache set to true
create table cached_extractor_results(
    cached_extractor_results_id         bigserial primary key,
    extracted_html                      text,
    extracted_text                      text,
    downloads_id                        bigint not null
);

-- it's better to have a few duplicates than deal with locking issues, so we don't try to make this unique
create index cached_extractor_results_downloads_id on cached_extractor_results( downloads_id );

-- keep track of performance of the topic spider
create table topic_spider_metrics (
    topic_spider_metrics_id         serial primary key,
    topics_id                       int references topics on delete cascade,
    iteration                       int not null,
    links_processed                 int not null,
    elapsed_time                    int not null,
    processed_date                  timestamp not null default now()
);

create index topic_spider_metrics_topic on topic_spider_metrics( topics_id );
create index topic_spider_metrics_dat on topic_spider_metrics( processed_date );

create type topic_permission AS ENUM ( 'read', 'write', 'admin' );

-- per user permissions for topics
create table topic_permissions (
    topic_permissions_id    serial primary key,
    topics_id               int not null references topics on delete cascade,
    auth_users_id           int not null references auth_users on delete cascade,
    permission              topic_permission not null
);

create index topic_permissions_topic on topic_permissions( topics_id );
create unique index topic_permissions_user on topic_permissions( auth_users_id, topics_id );

-- topics table with auth_users_id and user_permission fields that indicate the permission level for
-- the user for the topic.  permissions in decreasing order are admin, write, read, none.  users with
-- the admin role have admin permission for every topic. users with admin-readonly role have at least
-- read access to every topic.  all users have read access to every is_public topic.  otherwise, the
-- topic_permissions tableis used, with 'none' for no topic_permission.
create or replace view topics_with_user_permission as
    with admin_users as (
        select m.auth_users_id
            from auth_roles r
                join auth_users_roles_map m using ( auth_roles_id )
            where
                r.role = 'admin'
    ),

    read_admin_users as (
        select m.auth_users_id
            from auth_roles r
                join auth_users_roles_map m using ( auth_roles_id )
            where
                r.role = 'admin-readonly'
    )

    select
            t.*,
            u.auth_users_id,
            case
                when ( exists ( select 1 from admin_users a where a.auth_users_id = u.auth_users_id ) ) then 'admin'
                when ( tp.permission is not null ) then tp.permission::text
                when ( t.is_public ) then 'read'
                when ( exists ( select 1 from read_admin_users a where a.auth_users_id = u.auth_users_id ) ) then 'read'
                else 'none' end
                as user_permission
        from topics t
            join auth_users u on ( true )
            left join topic_permissions tp using ( topics_id, auth_users_id );

-- list of tweet counts and fetching statuses for each day of each topic
create table topic_tweet_days (
    topic_tweet_days_id     serial primary key,
    topics_id               int not null references topics on delete cascade,
    day                     date not null,
    tweet_count             int not null,
    num_ch_tweets           int not null,
    tweets_fetched          boolean not null default false
);

create index topic_tweet_days_td on topic_tweet_days ( topics_id, day );

-- list of tweets associated with a given topic
create table topic_tweets (
    topic_tweets_id         serial primary key,
    topic_tweet_days_id     int not null references topic_tweet_days on delete cascade,
    data                    json not null,
    tweet_id                varchar(256) not null,
    content                 text not null,
    publish_date            timestamp not null,
    twitter_user            varchar( 1024 ) not null
);

create unique index topic_tweets_id on topic_tweets( topic_tweet_days_id, tweet_id );
create index topic_tweet_topic_user on topic_tweets( topic_tweet_days_id, twitter_user );

-- urls parsed from topic tweets and imported into topic_seed_urls
create table topic_tweet_urls (
    topic_tweet_urls_id     serial primary key,
    topic_tweets_id         int not null references topic_tweets on delete cascade,
    url                     varchar (1024) not null
);

create index topic_tweet_urls_url on topic_tweet_urls ( url );
create index topic_tweet_urls_tt on topic_tweet_urls ( topic_tweets_id, url );

-- view that joins together the related topic_tweets, topic_tweet_days, topic_tweet_urls, and topic_seed_urls tables
-- tables for convenient querying of topic twitter url data
create view topic_tweet_full_urls as
    select distinct
            t.topics_id,
            tt.topic_tweets_id, tt.content, tt.publish_date, tt.twitter_user,
            ttd.day, ttd.tweet_count, ttd.num_ch_tweets, ttd.tweets_fetched,
            ttu.url, tsu.stories_id
        from
            topics t
            join topic_tweet_days ttd on ( t.topics_id = ttd.topics_id )
            join topic_tweets tt using ( topic_tweet_days_id )
            join topic_tweet_urls ttu using ( topic_tweets_id )
            left join topic_seed_urls tsu
                on ( tsu.topics_id = t.topics_id and ttu.url = tsu.url );


create table snap.timespan_tweets (
    topic_tweets_id     int not null references topic_tweets on delete cascade,
    timespans_id        int not null references timespans on delete cascade
);

create unique index snap_timespan_tweets_u on snap.timespan_tweets( timespans_id, topic_tweets_id );

create table snap.tweet_stories (
    snapshots_id        int not null references snapshots on delete cascade,
    topic_tweets_id     int not null references topic_tweets on delete cascade,
    publish_date        date not null,
    twitter_user        varchar( 1024 ) not null,
    stories_id          int not null,
    media_id            int not null,
    num_ch_tweets       int not null,
    tweet_count         int not null
);

create index snap_tweet_stories on snap.tweet_stories ( snapshots_id );

create table media_stats_weekly (
    media_id        int not null references media on delete cascade,
    stories_rank    int not null,
    num_stories     numeric not null,
    sentences_rank  int not null,
    num_sentences   numeric not null,
    stat_week       date not null
);

create index media_stats_weekly_medium on media_stats_weekly ( media_id );

create table media_expected_volume (
    media_id            int not null references media on delete cascade,
    start_date          date not null,
    end_date            date not null,
    expected_stories    numeric not null,
    expected_sentences  numeric not null
);

create index media_expected_volume_medium on media_expected_volume ( media_id );

create table media_coverage_gaps (
    media_id                int not null references media on delete cascade,
    stat_week               date not null,
    num_stories             numeric not null,
    expected_stories        numeric not null,
    num_sentences           numeric not null,
    expected_sentences      numeric not null
);

create index media_coverage_gaps_medium on media_coverage_gaps ( media_id );

create table media_health (
    media_health_id     serial primary key,
    media_id            int not null references media on delete cascade,
    num_stories         numeric not null,
    num_stories_y       numeric not null,
    num_stories_w       numeric not null,
    num_stories_90      numeric not null,
    num_sentences       numeric not null,
    num_sentences_y     numeric not null,
    num_sentences_w     numeric not null,
    num_sentences_90    numeric not null,
    is_healthy          boolean not null default false,
    has_active_feed     boolean not null default true,
    start_date          date not null,
    end_date            date not null,
    expected_sentences  numeric not null,
    expected_stories    numeric not null,
    coverage_gaps       int not null
);

create index media_health_medium on media_health ( media_id );

create type media_suggestions_status as enum ( 'pending', 'approved', 'rejected' );

create table media_suggestions (
    media_suggestions_id        serial primary key,
    name                        text,
    url                         text not null,
    feed_url                    text,
    reason                      text,
    auth_users_id               int references auth_users on delete set null,
    mark_auth_users_id          int references auth_users on delete set null,
    date_submitted              timestamp not null default now(),
    media_id                    int references media on delete set null,
    date_marked                 timestamp not null default now(),
    mark_reason                 text,
    status                      media_suggestions_status not null default 'pending',

    CONSTRAINT media_suggestions_media_id CHECK ( ( status in ( 'pending', 'rejected' ) ) or ( media_id is not null ) )
);

create index media_suggestions_date on media_suggestions ( date_submitted );

create table media_suggestions_tags_map (
    media_suggestions_id        int references media_suggestions on delete cascade,
    tags_id                     int references tags on delete cascade
);

create index media_suggestions_tags_map_ms on media_suggestions_tags_map ( media_suggestions_id );
create index media_suggestions_tags_map_tag on media_suggestions_tags_map ( tags_id );

-- keep track of basic high level stats for mediacloud for access through api
create table mediacloud_stats (
    mediacloud_stats_id     serial primary key,
    stats_date              date not null default now(),
    daily_downloads         bigint not null,
    daily_stories           bigint not null,
    active_crawled_media    bigint not null,
    active_crawled_feeds    bigint not null,
    total_stories           bigint not null,
    total_downloads         bigint not null,
    total_sentences         bigint not null
);

-- job states as implemented in MediaWords::AbstractJob
create table job_states (
    job_states_id           serial primary key,

    --MediaWords::Job::* class implementing the job
    class                   varchar( 1024 ) not null,

    -- short class specific state
    state                   varchar( 1024 ) not null,

    -- optional longer message describing the state, such as a stack trace for an error
    message                 text,

    -- last time this job state was updated
    last_updated            timestamp not null default now(),

    -- details about the job
    args                    json not null,
    priority                text not  null,

    -- the hostname and process_id of the running process
    hostname                text not null,
    process_id              int not null
);

create index job_states_class_date on job_states( class, last_updated );

create view pending_job_states as select * from job_states where state in ( 'running', 'queued' );

create type retweeter_scores_match_type AS ENUM ( 'retweet', 'regex' );

-- definition of bipolar comparisons for retweeter polarization scores
create table retweeter_scores (
    retweeter_scores_id     serial primary key,
    topics_id               int not null references topics on delete cascade,
    group_a_id              int null,
    group_b_id              int null,
    name                    text not null,
    state                   text not null default 'created but not queued',
    message                 text null,
    num_partitions          int not null,
    match_type              retweeter_scores_match_type not null default 'retweet'
);

-- group retweeters together so that we an compare, for example, sanders/warren retweeters to cruz/kasich retweeters
create table retweeter_groups (
    retweeter_groups_id     serial primary key,
    retweeter_scores_id     int not null references retweeter_scores on delete cascade,
    name                    text not null
);

alter table retweeter_scores add constraint retweeter_scores_group_a
    foreign key ( group_a_id ) references retweeter_groups on delete cascade;
alter table retweeter_scores add constraint retweeter_scores_group_b
    foreign key ( group_b_id ) references retweeter_groups on delete cascade;

-- list of twitter users within a given topic that have retweeted the given user
create table retweeters (
    retweeters_id           serial primary key,
    retweeter_scores_id     int not null references retweeter_scores on delete cascade,
    twitter_user            varchar(1024) not null,
    retweeted_user          varchar(1024) not null
);

create unique index retweeters_user on retweeters( retweeter_scores_id, twitter_user, retweeted_user );

create table retweeter_groups_users_map (
    retweeter_groups_id     int not null references retweeter_groups on delete cascade,
    retweeter_scores_id     int not null references retweeter_scores on delete cascade,
    retweeted_user          varchar(1024) not null
);

-- count of shares by retweeters for each retweeted_user in retweeters
create table retweeter_stories (
    retweeter_shares_id     serial primary key,
    retweeter_scores_id     int not null references retweeter_scores on delete cascade,
    stories_id              int not null references stories on delete cascade,
    retweeted_user          varchar(1024) not null,
    share_count             int not null
);

create unique index retweeter_stories_psu
    on retweeter_stories ( retweeter_scores_id, stories_id, retweeted_user );

-- polarization scores for media within a topic for the given retweeter_scoresdefinition
create table retweeter_media (
    retweeter_media_id    serial primary key,
    retweeter_scores_id   int not null references retweeter_scores on delete cascade,
    media_id              int not null references media on delete cascade,
    group_a_count         int not null,
    group_b_count         int not null,
    group_a_count_n       float not null,
    score                 float not null,
    partition             int not null
);

create unique index retweeter_media_score on retweeter_media ( retweeter_scores_id, media_id );

create table retweeter_partition_matrix (
    retweeter_partition_matrix_id       serial primary key,
    retweeter_scores_id                 int not null references retweeter_scores on delete cascade,
    retweeter_groups_id                 int not null references retweeter_groups on delete cascade,
    group_name                          text not null,
    share_count                         int not null,
    group_proportion                    float not null,
    partition                           int not null
);

create index retweeter_partition_matrix_score on retweeter_partition_matrix ( retweeter_scores_id );


--
-- Schema to hold object caches
--

CREATE SCHEMA cache;

CREATE OR REPLACE LANGUAGE plpgsql;


-- Trigger to update "db_row_last_updated" for cache tables
CREATE OR REPLACE FUNCTION cache.update_cache_db_row_last_updated()
RETURNS TRIGGER AS $$
BEGIN
    NEW.db_row_last_updated = NOW();
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';


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

END;
$$
LANGUAGE plpgsql;


--
-- Raw downloads from S3 cache
--

CREATE UNLOGGED TABLE cache.s3_raw_downloads_cache (
    s3_raw_downloads_cache_id SERIAL    PRIMARY KEY,
    object_id                 BIGINT    NOT NULL
                                            REFERENCES public.downloads (downloads_id)
                                            ON DELETE CASCADE,

    -- Will be used to purge old cache objects;
    -- don't forget to update cache.purge_object_caches()
    db_row_last_updated       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    raw_data                  BYTEA     NOT NULL
);
CREATE UNIQUE INDEX s3_raw_downloads_cache_object_id
    ON cache.s3_raw_downloads_cache (object_id);
CREATE INDEX s3_raw_downloads_cache_db_row_last_updated
    ON cache.s3_raw_downloads_cache (db_row_last_updated);

ALTER TABLE cache.s3_raw_downloads_cache
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;

CREATE TRIGGER s3_raw_downloads_cache_db_row_last_updated_trigger
    BEFORE INSERT OR UPDATE ON cache.s3_raw_downloads_cache
    FOR EACH ROW EXECUTE PROCEDURE cache.update_cache_db_row_last_updated();


--
-- CLIFF annotations
--
CREATE TABLE cliff_annotations (
    cliff_annotations_id  SERIAL    PRIMARY KEY,
    object_id             INTEGER   NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    raw_data              BYTEA     NOT NULL
);
CREATE UNIQUE INDEX cliff_annotations_object_id ON cliff_annotations (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE cliff_annotations
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;



--
-- NYTLabels annotations
--
CREATE TABLE nytlabels_annotations (
    nytlabels_annotations_id  SERIAL    PRIMARY KEY,
    object_id                 INTEGER   NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    raw_data                  BYTEA     NOT NULL
);
CREATE UNIQUE INDEX nytlabels_annotations_object_id ON nytlabels_annotations (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE nytlabels_annotations
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;

-- keep track of per domain web requests so that we can throttle them using mediawords.util.web.user_agent.throttled.
-- this is unlogged because we don't care about anything more than about 10 seconds old.  we don't have a primary
-- key because we want it just to be a fast table for temporary storage.
create unlogged table domain_web_requests (
    domain          text not null,
    request_time    timestamp not null default now()
);

create index domain_web_requests_domain on domain_web_requests ( domain );

-- return false if there is a request for the given domain within the last domain_timeout_arg seconds.  otherwise
-- return true and insert a row into domain_web_request for the domain.  this function does not lock the table and
-- so may allow some parallel requests through.
create or replace function get_domain_web_requests_lock( domain_arg text, domain_timeout_arg int ) returns boolean as $$
begin

-- we don't want this table to grow forever or to have to manage it externally, so just truncate about every
-- 1 million requests.  only do this if there are more than 1000 rows in the table so that unit tests will not
-- randomly fail.
if ( select random() * 1000000 ) <  1 then
    if exists ( select 1 from domain_web_requests offset 1000 ) then
        truncate table domain_web_requests;
    end if;
end if;

if exists (
    select *
        from domain_web_requests
        where
            domain = domain_arg and
            extract( epoch from now() - request_time ) < domain_timeout_arg
    ) then

    return false;
end if;

delete from domain_web_requests where domain = domain_arg;
insert into domain_web_requests (domain) select domain_arg;

return true;
end
$$ language plpgsql;


--
-- SimilarWeb metrics
--
CREATE TABLE similarweb_metrics (
    similarweb_metrics_id  SERIAL                   PRIMARY KEY,
    domain                 VARCHAR(1024)            NOT NULL,
    month                  DATE,
    visits                 BIGINT,
    update_date            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX similarweb_metrics_domain_month
    ON similarweb_metrics (domain, month);


--
-- Unnormalized table
--
CREATE TABLE similarweb_media_metrics (
    similarweb_media_metrics_id    SERIAL                   PRIMARY KEY,
    media_id                       INTEGER                  NOT NULL UNIQUE references media,
    similarweb_domain              VARCHAR(1024)            NOT NULL,
    domain_exact_match             BOOLEAN                  NOT NULL,
    monthly_audience               INTEGER                  NOT NULL,
    update_date                    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
