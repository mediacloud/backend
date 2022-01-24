--
-- Schema for MediaWords database
--

-- main schema
CREATE SCHEMA IF NOT EXISTS public;
COMMENT ON SCHEMA public IS 'main schema for MediaWords database';

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

create unique index database_variables_name on database_variables ( name );

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4761;
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

COMMENT ON FUNCTION week_start_date (day date) IS 'Need b/c date_trunc("week", date) is not immutable; 
see http://www.mentby.com/Group/pgsql-general/datetrunc-on-date-is-immutable.html';

-- Returns first 64 bits (16 characters) of MD5 hash
--
-- Useful for reducing index sizes (e.g. in story_sentences.sentence) where
-- 64 bits of entropy is enough.
CREATE OR REPLACE FUNCTION half_md5(string TEXT) RETURNS bytea AS $$
    -- pgcrypto's functions are being referred with public schema prefix to make pg_upgrade work
    SELECT SUBSTRING(public.digest(string, 'md5'::text), 0, 9);
$$ LANGUAGE SQL;

COMMENT ON FUNCTION half_md5 (string TEXT) IS 'Returns first 64 bits (16 characters) of MD5 hash; 
useful for reducing index sizes (e.g. in story_sentences.sentence) where 64 bits of entropy is not enough
pgcrypto functions are being referred with public schema prefix to make pg_upgrade work';

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

COMMENT ON FUNCTION table_exists (target_table_name VARCHAR) IS 'Returns true if table exists 
(and user has access to it). Table name might be with ("public.stories") or without ("stories") schema.';

--
-- Common partitioning tools
--

-- Return partition table name for a given base table name and an integer ID
CREATE OR REPLACE FUNCTION partition_name(
    base_table_name TEXT,
    chunk_size BIGINT,
    object_id BIGINT
) RETURNS TEXT AS $$
DECLARE

    -- Up to 100 partitions, suffixed as "_00", "_01" ..., "_99"
    -- (having more of them is not feasible)
    to_char_format CONSTANT TEXT := '00';

    -- Partition table name (e.g. "stories_tags_map_01")
    table_name TEXT;

    chunk_number INT;

BEGIN
    SELECT object_id / chunk_size INTO chunk_number;

    SELECT base_table_name || '_' || TRIM(leading ' ' FROM TO_CHAR(chunk_number, to_char_format))
        INTO table_name;

    RETURN table_name;
END;
$$
LANGUAGE plpgsql IMMUTABLE;


create table media (
    media_id            serial          primary key,
    url                 varchar(1024)   not null,
    normalized_url      varchar(1024)   null,
    name                varchar(128)    not null,
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

    -- notes for internal media cloud consumption (eg. 'added this for yochai')
    editor_notes                text null,
    -- notes for public consumption (eg. 'leading dissident paper in anatarctica')
    public_notes                text null,

    -- if true, indicates that media cloud closely monitors the health of this source
    is_monitored                boolean not null default false,

    CONSTRAINT media_name_not_empty CHECK ( ( (name)::text <> ''::text ) ),
    CONSTRAINT media_self_dup CHECK ( dup_media_id IS NULL OR dup_media_id <> media_id )
);

COMMENT ON COLUMN media.foreign_rss_links IS 'ndicates that the media source includes a substantial 
number of links in its feeds that are not its own. These media sources cause problems for the 
topic mapper spider, which finds those foreign rss links an thinks that the urls belong to the 
parent media source.';
COMMENT ON COLUMN media.content_delay IS 'Delay content downloads for this media source for (int) hours';
COMMENT ON COLUMN media.editor_notes IS 'notes for internal MC consumption (e.g. "added this for yochai")';
COMMENT ON COLUMN media.public_notes IS 'notes for public consumption (e.g. "leading dissident paper in antarctica")';
COMMENT ON COLUMN media.is_monitored IS 'if true, indicates that MC closely monitors health of this source';

create unique index media_name on media(name);
create unique index media_url on media(url);
create index media_normalized_url on media(normalized_url);
create index media_name_fts on media using gin(to_tsvector('english', name));

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

COMMENT ON FUNCTION media_rescraping_add_initial_state_trigger () IS 'Insert new rows to "media_rescraping" 
for each new row in "media"';

CREATE TRIGGER media_rescraping_add_initial_state_trigger
    AFTER INSERT ON media
    FOR EACH ROW EXECUTE PROCEDURE media_rescraping_add_initial_state_trigger();


create table media_stats (
    media_stats_id              serial      primary key,
    media_id                    int         not null references media on delete cascade,
    num_stories                 int         not null,
    num_sentences               int         not null,
    stat_date                   date        not null
);

create unique index media_stats_medium_date on media_stats( media_id, stat_date );

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
          AND active = 't'

          -- Website might introduce RSS feeds later
          AND "type" = 'syndicated'

    ) THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;

END;
$$
LANGUAGE 'plpgsql';

COMMENT ON FUNCTION media_has_active_syndicated_feeds (param_media_id INT) IS 'true if media has active rss feeds';

create type feed_type AS ENUM (

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

create table feeds (
    feeds_id            serial              primary key,
    media_id            int                 not null references media on delete cascade,
    name                varchar(512)        not null,
    url                 varchar(1024)       not null,

    -- Feed type
    type                feed_type           NOT NULL DEFAULT 'syndicated',

    -- Whether or not feed is active (should be periodically fetched for new stories)
    active              BOOLEAN             NOT NULL DEFAULT 't',

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
create index feeds_last_attempted_download_time on feeds(last_attempted_download_time);
create index feeds_last_successful_download_time on feeds(last_successful_download_time);

-- Feeds for media item that were found after (re)scraping
CREATE TABLE feeds_after_rescraping (
    feeds_after_rescraping_id   SERIAL          PRIMARY KEY,
    media_id                    INT             NOT NULL REFERENCES media ON DELETE CASCADE,
    name                        VARCHAR(512)    NOT NULL,
    url                         VARCHAR(1024)   NOT NULL,
    type                        feed_type       NOT NULL DEFAULT 'syndicated'
);

COMMENT ON TABLE feeds_after_rescraping IS 'feeds for media item discovered after (re)scraping';

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

COMMENT ON FUNCTION feed_is_stale (param_feeds_id INT) IS '-- Feed is "stale" (has not provided a new story in some time)
-- Not to be confused with "stale feeds" in extractor!';

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

COMMENT ON COLUMN tag_sets.show_on_media IS 'should public interfaces show this as an option for
searching media sources?';
COMMENT ON COLUMN tag_sets.show_on_stories IS 'should public interfaces show this as an option 
for search stories?';

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

COMMENT ON COLUMN tags.show_on_media IS 'should public interfaces show this as an option for
searching media sources?';
COMMENT ON COLUMN tags.show_on_stories IS 'should public interfaces show this as an option 
for search stories?';
COMMENT ON COLUMN tags.is_static IS 'if true, users can expect this tag and its associations 
not to change in major ways';

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

create view media_with_media_types as
    select m.*, mtm.tags_id media_type_tags_id, t.label media_type
    from
        media m
        left join (
            tags t
            join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id and ts.name = 'media_type' )
            join media_tags_map mtm on ( mtm.tags_id = t.tags_id )
        ) on ( m.media_id = mtm.media_id );


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


--
-- Stories (news articles)
--

create table stories (
    stories_id                  serial          primary key,
    media_id                    int             not null references media on delete cascade,
    url                         varchar(1024)   not null,
    guid                        varchar(1024)   not null,
    title                       text            not null,
    normalized_title_hash       uuid            null,
    description                 text            null,
    publish_date                timestamp       null,
    collect_date                timestamp       not null default now(),
    full_text_rss               boolean         not null default 'f',
    language                    varchar(3)      null   -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
);

COMMENT ON TABLE stories IS 'stories (news articles)';
COMMENT ON COLUMN stories.language IS '2- or 3-character ISO 690 
language code; empty if unknown, NULL if unset';

create index stories_media_id on stories (media_id);
create unique index stories_guid on stories(guid, media_id);
create index stories_url on stories (url);
create index stories_publish_date on stories (publish_date);
create index stories_collect_date on stories (collect_date);
create index stories_md on stories(media_id, date_trunc('day'::text, publish_date));
create index stories_language on stories(language);
create index stories_title_hash on stories( md5( title ) );
create index stories_publish_day on stories( date_trunc( 'day', publish_date ) );
create index stories_normalized_title_hash on stories( media_id, normalized_title_hash );

-- get normalized story title by breaking the title into parts by the separator characters :-| and  using
-- the longest single part.  longest part must be at least 32 characters cannot be the same as the media source
-- name.  also remove all html, punctuation and repeated spaces, lowecase, and limit to 1024 characters.
CREATE OR REPLACE FUNCTION get_normalized_title(title text, title_media_id int)
 RETURNS text
 IMMUTABLE
AS $function$
declare
        title_part text;
        media_title text;
begin

        -- stupid simple html stripper to avoid html messing up title_parts
        select into title regexp_replace(title, '<[^\<]*>', '', 'gi');
        select into title regexp_replace(title, '\&#?[a-z0-9]*', '', 'gi');

        select into title lower(title);
        select into title regexp_replace(title,'(?:\- )|[:|]', 'SEPSEP', 'g');
        select into title regexp_replace(title, '[[:punct:]]', '', 'g');
        select into title regexp_replace(title, '\s+', ' ', 'g');
        select into title substr(title, 0, 1024);

        if title_media_id = 0 then
            return title;
        end if;

        select into title_part part
            from ( select regexp_split_to_table(title, ' *SEPSEP *') part ) parts
            order by length(part) desc limit 1;

        if title_part = title then
            return title;
        end if;

        if length(title_part) < 32 then
            return title;
        end if;

        select into media_title get_normalized_title(name, 0) from media where media_id = title_media_id;
        if media_title = title_part then
            return title;
        end if;

        return title_part;
end
$function$ language plpgsql;

COMMENT ON FUNCTION get_normalized_title (title text, title_media_id int) IS 'get normalized story title by breaking the title into parts by 
the separator characters :-| and  using the longest single part. longest part must be at least 32 characters, 
cannot be the same as the media source name.  also remove all html, punctuation and repeated spaces, 
lowecase, and limit to 1024 characters.';

create function add_normalized_title_hash() returns trigger as $function$
BEGIN

    if ( TG_OP = 'update' ) then
        if ( OLD.title = NEW.title ) then
            return new;
        end if;
    end if;

    select into NEW.normalized_title_hash md5( get_normalized_title( NEW.title, NEW.media_id ) )::uuid;
    
    return new;

END

$function$ language plpgsql;

create trigger stories_add_normalized_title before insert or update
    on stories for each row execute procedure add_normalized_title_hash();

create function insert_solr_import_story() returns trigger as $insert_solr_import_story$
DECLARE

    queue_stories_id INT;

BEGIN

    IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
        select NEW.stories_id into queue_stories_id;
    ELSE
        select OLD.stories_id into queue_stories_id;
	END IF;

    insert into solr_import_stories ( stories_id )
        select queue_stories_id
            where exists (
                select 1 from processed_stories where stories_id = queue_stories_id
         );

    IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
		RETURN NEW;
	ELSE
		RETURN OLD;
	END IF;

END;

$insert_solr_import_story$ LANGUAGE plpgsql;

create trigger stories_insert_solr_import_story after insert or update or delete
    on stories for each row execute procedure insert_solr_import_story();

create table stories_ap_syndicated (
    stories_ap_syndicated_id    serial primary key,
    stories_id                  int not null references stories on delete cascade,
    ap_syndicated               boolean not null
);

create unique index stories_ap_syndicated_story on stories_ap_syndicated ( stories_id );

--
-- Partitioning tools for tables partitioned by "stories_id"
--

-- Return partition size for every table that is partitioned by "stories_id"
CREATE OR REPLACE FUNCTION partition_by_stories_id_chunk_size()
RETURNS BIGINT AS $$
BEGIN
    RETURN 100 * 1000 * 1000;   -- 100m stories in each partition
END; $$
LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION partition_by_stories_id_chunk_size () IS 'Return partition size for every table 
that is partitioned by "stories_id"';

-- Return partition table name for a given base table name and "stories_id"
CREATE OR REPLACE FUNCTION partition_by_stories_id_partition_name(
    base_table_name TEXT,
    stories_id BIGINT
) RETURNS TEXT AS $$
BEGIN

    RETURN partition_name(
        base_table_name := base_table_name,
        chunk_size := partition_by_stories_id_chunk_size(),
        object_id := stories_id
    );

END;
$$
LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION partition_by_stories_id_partition_name (base_table_name TEXT, stories_id BIGINT) IS 'Return 
partition table name for a given base table name and "stories_id"';

-- Create missing partitions for tables partitioned by "stories_id", returning
-- a list of created partition tables
CREATE OR REPLACE FUNCTION partition_by_stories_id_create_partitions(base_table_name TEXT)
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

    SELECT partition_by_stories_id_chunk_size() INTO chunk_size;

    -- Create +1 partition for future insertions
    SELECT COALESCE(MAX(stories_id), 0) + chunk_size FROM stories INTO max_stories_id;

    SELECT 1 INTO partition_stories_id;
    WHILE partition_stories_id <= max_stories_id LOOP
        SELECT partition_by_stories_id_partition_name(
            base_table_name := base_table_name,
            stories_id := partition_stories_id
        ) INTO target_table_name;
        IF table_exists(target_table_name) THEN
            RAISE NOTICE 'Partition "%" for story ID % already exists.', target_table_name, partition_stories_id;
        ELSE
            RAISE NOTICE 'Creating partition "%" for story ID %', target_table_name, partition_stories_id;

            SELECT (partition_stories_id / chunk_size) * chunk_size INTO stories_id_start;
            SELECT ((partition_stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

            -- Kill all autovacuums before proceeding with DDL changes
            PERFORM pid
            FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
            WHERE backend_type = 'autovacuum worker'
              AND query ~ 'stories';

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

        SELECT partition_stories_id + chunk_size INTO partition_stories_id;
    END LOOP;

    RETURN;

END;
$$
LANGUAGE plpgsql;

COMMENT ON FUNCTION partition_by_stories_id_create_partitions (base_table_name TEXT) IS 'Create missing partitions for 
tables partitioned by "stories_id", returning a list of created partition tables';

-- list of all url or guid identifiers for each story
create table story_urls (
    story_urls_id   bigserial primary key,
    stories_id      int references stories on delete cascade,
    url             varchar(1024) not null
);

create unique index story_urls_url on story_urls ( url, stories_id );
create index stories_story on story_urls ( stories_id );

COMMENT ON TABLE story_urls IS 'list of all url or guid identifiers for each story';

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


CREATE TABLE downloads (
    downloads_id    BIGSERIAL       NOT NULL,
    feeds_id        INT             NOT NULL REFERENCES feeds (feeds_id),
    stories_id      INT             NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    parent          BIGINT          NULL,
    url             TEXT            NOT NULL,
    host            TEXT            NOT NULL,
    download_time   TIMESTAMP       NOT NULL DEFAULT NOW(),
    type            download_type   NOT NULL,
    state           download_state  NOT NULL,
    path            TEXT            NULL,
    error_message   TEXT            NULL,
    priority        SMALLINT        NOT NULL,
    sequence        SMALLINT        NOT NULL,
    extracted       BOOLEAN         NOT NULL DEFAULT 'f',

    -- Partitions require a composite primary key
    PRIMARY KEY (downloads_id, state, type)

) PARTITION BY LIST (state);

-- Imitate a foreign key by testing if a download with an INSERTed / UPDATEd
-- "downloads_id" exists in "downloads"
--
-- Partitioned tables don't support foreign keys being pointed to them, so this
-- trigger achieves the same referential integrity for tables that point to
-- "downloads".
--
-- Column name from NEW (NEW.<column_name>) that contains the
-- INSERTed / UPDATEd "downloads_id" should be passed as an trigger argument.
CREATE OR REPLACE FUNCTION test_referenced_download_trigger()
RETURNS TRIGGER AS $$
DECLARE
    param_column_name TEXT;
    param_downloads_id BIGINT;
BEGIN

    IF TG_NARGS != 1 THEN
        RAISE EXCEPTION 'Trigger should be called with an column name argument.';
    END IF;

    SELECT TG_ARGV[0] INTO param_column_name;
    SELECT to_json(NEW) ->> param_column_name INTO param_downloads_id;

    -- Might be NULL, e.g. downloads.parent
    IF (param_downloads_id IS NOT NULL) THEN

        IF NOT EXISTS (
            SELECT 1
            FROM downloads
            WHERE downloads_id = param_downloads_id
        ) THEN
            RAISE EXCEPTION 'Referenced download ID % from column "%" does not exist in "downloads".', param_downloads_id, param_column_name;
        END IF;

    END IF;

    RETURN NEW;

END;
$$
LANGUAGE plpgsql;

COMMENT ON FUNCTION test_referenced_download_trigger () IS 'Imitate a foreign key by testing if a download 
with an INSERTed / UPDATEd "downloads_id" exists in "downloads." Partitioned tables do not support foreign 
keys being pointed to them, so this trigger achieves the same referential integrity for tables that point 
to "downloads". Column name from NEW (NEW.<column_name>) that contains the INSERTed / UPDATEd "downloads_id" 
should be passed as an trigger argument.';

CREATE INDEX downloads_parent
    ON downloads (parent);

CREATE INDEX downloads_time
    ON downloads (download_time);

CREATE INDEX downloads_feed_download_time
    ON downloads (feeds_id, download_time);

CREATE INDEX downloads_story
    ON downloads (stories_id);


CREATE TABLE downloads_error
    PARTITION OF downloads
    FOR VALUES IN ('error');

CREATE TRIGGER downloads_error_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON downloads_error
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('parent');


CREATE TABLE downloads_feed_error
    PARTITION OF downloads
    FOR VALUES IN ('feed_error');

CREATE TRIGGER downloads_feed_error_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON downloads_feed_error
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('parent');


CREATE TABLE downloads_fetching
    PARTITION OF downloads
    FOR VALUES IN ('fetching');

CREATE TRIGGER downloads_fetching_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON downloads_fetching
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('parent');


CREATE TABLE downloads_pending
    PARTITION OF downloads
    FOR VALUES IN ('pending');

CREATE TRIGGER downloads_pending_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON downloads_pending
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('parent');


CREATE TABLE downloads_success
    PARTITION OF downloads (
        CONSTRAINT downloads_success_path_not_null
        CHECK (path IS NOT NULL)
    ) FOR VALUES IN ('success')
    PARTITION BY LIST (type);


CREATE TABLE downloads_success_feed
    PARTITION OF downloads_success (
        CONSTRAINT downloads_success_feed_stories_id_null
        CHECK (stories_id IS NULL)
    ) FOR VALUES IN ('feed')
    PARTITION BY RANGE (downloads_id);


CREATE TABLE downloads_success_content
    PARTITION OF downloads_success (
        CONSTRAINT downloads_success_content_stories_id_not_null
        CHECK (stories_id IS NOT NULL)
    ) FOR VALUES IN ('content')
    PARTITION BY RANGE (downloads_id);

-- We need a separate unique index for the "download_texts" foreign key to be
-- able to point to "downloads_success_content" partitions
CREATE UNIQUE INDEX downloads_success_content_downloads_id
    ON downloads_success_content (downloads_id);

COMMENT ON INDEX downloads_success_content_downloads_id IS 'We need a separate unique index for the 
"download_texts" foreign key to be able to point to "downloads_success_content" partitions';

CREATE INDEX downloads_success_content_extracted
    ON downloads_success_content (extracted);


CREATE VIEW downloads_media AS
    SELECT
        d.*,
        f.media_id AS _media_id
    FROM
        downloads AS d,
        feeds AS f
    WHERE d.feeds_id = f.feeds_id;

CREATE VIEW downloads_non_media AS
    SELECT d.*
    FROM downloads AS d
    WHERE d.feeds_id IS NULL;

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


--
-- Partitioning tools for tables partitioned by "downloads_id"
--

-- Return partition size for every table that is partitioned by "downloads_id"
CREATE OR REPLACE FUNCTION partition_by_downloads_id_chunk_size()
RETURNS BIGINT AS $$
BEGIN
    RETURN 100 * 1000 * 1000;   -- 100m downloads in each partition
END; $$
LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION partition_by_downloads_id_chunk_size () IS 
'Return partition size for every table that is partitioned by "downloads_id"';

-- Return partition table name for a given base table name and "downloads_id"
CREATE OR REPLACE FUNCTION partition_by_downloads_id_partition_name(
    base_table_name TEXT,
    downloads_id BIGINT
) RETURNS TEXT AS $$
BEGIN

    RETURN partition_name(
        base_table_name := base_table_name,
        chunk_size := partition_by_downloads_id_chunk_size(),
        object_id := downloads_id
    );

END;
$$
LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION partition_by_downloads_id_partition_name (base_table_name TEXT, downloads_id BIGINT) IS 'Return 
partition table name for a given base table name and "downloads_id"';

-- Create missing partitions for tables partitioned by "downloads_id", returning
-- a list of created partition tables
CREATE OR REPLACE FUNCTION partition_by_downloads_id_create_partitions(base_table_name TEXT)
RETURNS SETOF TEXT AS
$$
DECLARE
    chunk_size INT;
    max_downloads_id BIGINT;
    partition_downloads_id BIGINT;

    -- Partition table name (e.g. "downloads_success_content_01")
    target_table_name TEXT;

    -- Partition table owner (e.g. "mediaclouduser")
    target_table_owner TEXT;

    -- "downloads_id" chunk lower limit, inclusive (e.g. 30,000,000)
    downloads_id_start BIGINT;

    -- "downloads_id" chunk upper limit, exclusive (e.g. 31,000,000)
    downloads_id_end BIGINT;
BEGIN

    SELECT partition_by_downloads_id_chunk_size() INTO chunk_size;

    -- Create +1 partition for future insertions
    SELECT COALESCE(MAX(downloads_id), 0) + chunk_size FROM downloads INTO max_downloads_id;

    SELECT 1 INTO partition_downloads_id;
    WHILE partition_downloads_id <= max_downloads_id LOOP
        SELECT partition_by_downloads_id_partition_name(
            base_table_name := base_table_name,
            downloads_id := partition_downloads_id
        ) INTO target_table_name;
        IF table_exists(target_table_name) THEN
            RAISE NOTICE 'Partition "%" for download ID % already exists.', target_table_name, partition_downloads_id;
        ELSE
            RAISE NOTICE 'Creating partition "%" for download ID %', target_table_name, partition_downloads_id;

            SELECT (partition_downloads_id / chunk_size) * chunk_size INTO downloads_id_start;
            SELECT ((partition_downloads_id / chunk_size) + 1) * chunk_size INTO downloads_id_end;

            -- Kill all autovacuums before proceeding with DDL changes
            PERFORM pid
            FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
            WHERE backend_type = 'autovacuum worker'
              AND query ~ 'downloads';

            EXECUTE '
                CREATE TABLE ' || target_table_name || '
                    PARTITION OF ' || base_table_name || '
                    FOR VALUES FROM (' || downloads_id_start || ')
                               TO   (' || downloads_id_end   || ');
            ';

            -- Update owner
            SELECT u.usename AS owner
            FROM information_schema.tables AS t
                JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
                JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
            WHERE t.table_name = base_table_name
              AND t.table_schema = 'public'
            INTO target_table_owner;

            EXECUTE '
                ALTER TABLE ' || target_table_name || '
                    OWNER TO ' || target_table_owner || ';
            ';

            -- Add created partition name to the list of returned partition names
            RETURN NEXT target_table_name;

        END IF;

        SELECT partition_downloads_id + chunk_size INTO partition_downloads_id;
    END LOOP;

    RETURN;

END;
$$
LANGUAGE plpgsql;

COMMENT ON FUNCTION partition_by_downloads_id_create_partitions (base_table_name TEXT) IS 'Create 
missing partitions for tables partitioned by "downloads_id", returning a list of 
created partition tables';

-- Create subpartitions of "downloads_success_feed" or "downloads_success_content"
CREATE OR REPLACE FUNCTION downloads_create_subpartitions(base_table_name TEXT)
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_downloads_id_create_partitions(base_table_name));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;

        EXECUTE '
            CREATE TRIGGER ' || partition || '_test_referenced_download_trigger
                BEFORE INSERT OR UPDATE ON ' || partition || '
                FOR EACH ROW
                EXECUTE PROCEDURE test_referenced_download_trigger(''parent'');
        ';

    END LOOP;

END;
$$
LANGUAGE plpgsql;

COMMENT ON FUNCTION downloads_create_subpartitions (base_table_name TEXT) IS 'Create 
subpartitions of "downloads_success_feed" or "downloads_success_content"';

-- Create missing "downloads_success_content" partitions
CREATE OR REPLACE FUNCTION downloads_success_content_create_partitions()
RETURNS VOID AS
$$

    SELECT downloads_create_subpartitions('downloads_success_content');

$$
LANGUAGE SQL;

COMMENT ON FUNCTION downloads_success_content_create_partitions () IS 'Create 
missing "downloads_success_content" partitions';

-- Create initial "downloads_success_content" partitions for empty database
SELECT downloads_success_content_create_partitions();


-- Create missing "downloads_success_feed" partitions
CREATE OR REPLACE FUNCTION downloads_success_feed_create_partitions()
RETURNS VOID AS
$$

    SELECT downloads_create_subpartitions('downloads_success_feed');

$$
LANGUAGE SQL;

COMMENT ON FUNCTION downloads_success_feed_create_partitions () IS 'Create missing 
"downloads_success_feed" partitions';

-- Create initial "downloads_success_feed" partitions for empty database
SELECT downloads_success_feed_create_partitions();

-- table for object types used for mediawords.util.public_store
create schema public_store;

COMMENT ON SCHEMA public_store IS 'table for object types used for mediawords.util.public_store';

create table public_store.timespan_files (
    timespan_files_id   bigserial   primary key,
    object_id           bigint not null,
    raw_data            bytea not null
);

create unique index timespan_files_id on public_store.timespan_files ( object_id );

create table public_store.snapshot_files (
    snapshot_files_id   bigserial   primary key,
    object_id           bigint not null,
    raw_data            bytea not null
);

create unique index snapshot_files_id on public_store.snapshot_files ( object_id );

create table public_store.timespan_maps (
    timespan_maps_id   bigserial   primary key,
    object_id           bigint not null,
    raw_data            bytea not null
);

create unique index timespan_maps_id on public_store.timespan_maps ( object_id );

--
-- Raw downloads stored in the database
-- (if the "postgresql" download storage method is enabled)
--
CREATE TABLE raw_downloads (
    raw_downloads_id    BIGSERIAL   PRIMARY KEY,

    -- "downloads_id" from "downloads"
    object_id           BIGINT      NOT NULL,

    raw_data            BYTEA       NOT NULL
);

COMMENT ON TABLE raw_downloads IS 'Raw downloads stored in the database (if 
the "postgresql" download storage method is enabled)';
COMMENT ON COLUMN raw_downloads.object_id IS '"downloads_id" from "downloads"';

CREATE UNIQUE INDEX raw_downloads_object_id
    ON raw_downloads (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE raw_downloads
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;

CREATE TRIGGER raw_downloads_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON raw_downloads
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('object_id');

COMMENT ON COLUMN raw_downloads.raw_data IS 'Do not attempt to compress BLOBs in 
"raw_data" because they are going to becompressed already';

--
-- Feed -> story map
--

-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE feeds_stories_map_p (

    -- PRIMARY KEY on master table needed for database handler's primary_key_column() method to work
    feeds_stories_map_p_id    BIGSERIAL   PRIMARY KEY NOT NULL,

    feeds_id                  INT         NOT NULL,
    stories_id                INT         NOT NULL
);

COMMENT ON TABLE feeds_stories_map_p IS '"Master" table (no indexes, no foreign keys as 
they will be ineffective)';
COMMENT ON COLUMN feeds_stories_map_p.feeds_stories_map_p_id IS 'PRIMARY KEY on master table 
needed for database handler primary_key_column() method to work';

-- Note: "INSERT ... RETURNING *" doesn't work with the trigger, please use
-- "feeds_stories_map" view instead
CREATE OR REPLACE FUNCTION feeds_stories_map_p_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "feeds_stories_map_01")
BEGIN
    SELECT partition_by_stories_id_partition_name(
        base_table_name := 'feeds_stories_map_p',
        stories_id := NEW.stories_id
    ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

COMMENT ON FUNCTION feeds_stories_map_p_insert_trigger () IS 'Note: "INSERT ... RETURNING *" does not 
work with the trigger, please use "feeds_stories_map" view instead. target_table_name 
= partition table name (e.g. "feeds_stories_map_01")';

CREATE TRIGGER feeds_stories_map_p_insert_trigger
    BEFORE INSERT ON feeds_stories_map_p
    FOR EACH ROW EXECUTE PROCEDURE feeds_stories_map_p_insert_trigger();


-- Create missing "feeds_stories_map_p" partitions
CREATE OR REPLACE FUNCTION feeds_stories_map_create_partitions()
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_stories_id_create_partitions('feeds_stories_map_p'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;

        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_feeds_id_fkey
                FOREIGN KEY (feeds_id) REFERENCES feeds (feeds_id) MATCH FULL ON DELETE CASCADE;

            CREATE UNIQUE INDEX ' || partition || '_feeds_id_stories_id
                ON ' || partition || ' (feeds_id, stories_id);

            CREATE INDEX ' || partition || '_stories_id
                ON ' || partition || ' (stories_id);
        ';

    END LOOP;

END;
$$
LANGUAGE plpgsql;

COMMENT ON FUNCTION feeds_stories_map_create_partitions () IS 'Create missing 
"feeds_stories_map_p" partitions';

-- Create initial "feeds_stories_map_p" partitions for empty database
SELECT feeds_stories_map_create_partitions();


-- Proxy view to "feeds_stories_map_p" to make RETURNING work
CREATE OR REPLACE VIEW feeds_stories_map AS

    SELECT
        feeds_stories_map_p_id AS feeds_stories_map_id,
        feeds_id,
        stories_id
    FROM feeds_stories_map_p;

COMMENT ON VIEW feeds_stories_map IS 'Proxy view to "feeds_stories_map_p" 
to make RETURNING work with partitioned tables
 (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)';

-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW feeds_stories_map
    ALTER COLUMN feeds_stories_map_id
    SET DEFAULT nextval(pg_get_serial_sequence('feeds_stories_map_p', 'feeds_stories_map_p_id'));

-- Prevent the next INSERT from failing
SELECT nextval(pg_get_serial_sequence('feeds_stories_map_p', 'feeds_stories_map_p_id'));


-- Trigger that implements INSERT / UPDATE / DELETE behavior on "feeds_stories_map" view
CREATE OR REPLACE FUNCTION feeds_stories_map_view_insert_update_delete() RETURNS trigger AS $$

BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- By INSERTing into the master table, we're letting triggers choose
        -- the correct partition.
        INSERT INTO feeds_stories_map_p SELECT NEW.*;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE feeds_stories_map_p
            SET feeds_id = NEW.feeds_id,
                stories_id = NEW.stories_id
            WHERE feeds_id = OLD.feeds_id
              AND stories_id = OLD.stories_id;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        DELETE FROM feeds_stories_map_p
            WHERE feeds_id = OLD.feeds_id
              AND stories_id = OLD.stories_id;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION feeds_stories_map_view_insert_update_delete () IS 'Trigger that 
implements INSERT / UPDATE / DELETE behavior on "feeds_stories_map" view. By INSERTing 
into the master table (feeds_stories_map_p), we are letting triggers choose the correct partition.';

CREATE TRIGGER feeds_stories_map_view_insert_update_delete_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE ON feeds_stories_map
    FOR EACH ROW EXECUTE PROCEDURE feeds_stories_map_view_insert_update_delete();


--
-- Story -> tag map
--

-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE stories_tags_map_p (

    -- PRIMARY KEY on master table needed for database handler's
    -- primary_key_column() method to work
    stories_tags_map_p_id   BIGSERIAL   PRIMARY KEY NOT NULL,

    stories_id              INT         NOT NULL,
    tags_id                 INT         NOT NULL
);

COMMENT ON TABLE stories_tags_map_p IS '"Master" table (no indexes, 
no foreign keys as they will be ineffective)';
COMMENT ON COLUMN stories_tags_map_p.stories_tags_map_p_id IS 'PRIMARY KEY on 
master table needed for database handler primary_key_column() method to work';

-- Create missing "stories_tags_map" partitions
CREATE OR REPLACE FUNCTION stories_tags_map_create_partitions()
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_stories_id_create_partitions('stories_tags_map_p'));

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

COMMENT ON FUNCTION stories_tags_map_create_partitions () IS 'Create missing "stories_tags_map" 
partitions, add extra foreign keys / constraints to the newly created partitions';

-- Create initial "stories_tags_map" partitions for empty database
SELECT stories_tags_map_create_partitions();


-- Upsert row into correct partition
CREATE OR REPLACE FUNCTION stories_tags_map_p_upsert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "stories_tags_map_01")
BEGIN
    SELECT partition_by_stories_id_partition_name(
        base_table_name := 'stories_tags_map_p',
        stories_id := NEW.stories_id
    ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ON CONFLICT (stories_id, tags_id) DO NOTHING
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

COMMENT ON FUNCTION stories_tags_map_p_upsert_trigger () IS 'Upsert row into correct partition';

CREATE TRIGGER stories_tags_map_p_upsert_trigger
    BEFORE INSERT ON stories_tags_map_p
    FOR EACH ROW EXECUTE PROCEDURE stories_tags_map_p_upsert_trigger();


CREATE TRIGGER stories_tags_map_p_insert_solr_import_story
    BEFORE INSERT OR UPDATE OR DELETE ON stories_tags_map_p
    FOR EACH ROW EXECUTE PROCEDURE insert_solr_import_story();


-- Proxy view to "stories_tags_map_p" to make RETURNING work
CREATE OR REPLACE VIEW stories_tags_map AS

    SELECT
        stories_tags_map_p_id AS stories_tags_map_id,
        stories_id,
        tags_id
    FROM stories_tags_map_p;

COMMENT ON VIEW stories_tags_map IS 'Proxy view to "stories_tags_map_p" to make RETURNING work
with partitioned tables';

-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW stories_tags_map
    ALTER COLUMN stories_tags_map_id
    SET DEFAULT nextval(pg_get_serial_sequence('stories_tags_map_p', 'stories_tags_map_p_id'));

-- Prevent the next INSERT from failing
SELECT nextval(pg_get_serial_sequence('stories_tags_map_p', 'stories_tags_map_p_id'));


-- Trigger that implements INSERT / UPDATE / DELETE behavior on "stories_tags_map" view
CREATE OR REPLACE FUNCTION stories_tags_map_view_insert_update_delete() RETURNS trigger AS $$
BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- By INSERTing into the master table, we're letting triggers choose
        -- the correct partition.
        INSERT INTO stories_tags_map_p SELECT NEW.*;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE stories_tags_map_p
            SET stories_id = NEW.stories_id,
                tags_id = NEW.tags_id
            WHERE stories_id = OLD.stories_id
              AND tags_id = OLD.tags_id;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        DELETE FROM stories_tags_map_p
            WHERE stories_id = OLD.stories_id
              AND tags_id = OLD.tags_id;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION stories_tags_map_view_insert_update_delete () IS 'Trigger 
that implements INSERT / UPDATE / DELETE behavior on "stories_tags_map" view. By 
INSERTing into the master table, we are letting triggers choose the correct partition.';

CREATE TRIGGER stories_tags_map_view_insert_update_delete
    INSTEAD OF INSERT OR UPDATE OR DELETE ON stories_tags_map
    FOR EACH ROW EXECUTE PROCEDURE stories_tags_map_view_insert_update_delete();

create table queued_downloads (
    queued_downloads_id bigserial   primary key,
    downloads_id        bigint      not null
);

create unique index queued_downloads_download on queued_downloads(downloads_id);

-- do this as a plpgsql function because it wraps it in the necessary transaction without
-- having to know whether the calling context is in a transaction
create function pop_queued_download() returns bigint as $$

declare

    pop_downloads_id bigint;

begin

    select into pop_downloads_id downloads_id
        from queued_downloads
        order by downloads_id desc
        limit 1 for
        update skip locked;

    delete from queued_downloads where downloads_id = pop_downloads_id;

    return pop_downloads_id;
end;

$$ language plpgsql;

COMMENT ON FUNCTION pop_queued_download () IS 'do this as a plpgsql function 
because it wraps it in the necessary transaction without having to know whether 
the calling context is in a transaction';

--
-- Extracted plain text from every download
--

-- Partitioned table
CREATE TABLE download_texts (
    download_texts_id       BIGSERIAL   NOT NULL,
    downloads_id            BIGINT      NOT NULL,
    download_text           TEXT        NOT NULL,
    download_text_length    INT         NOT NULL,

    -- Partitions require a composite primary key
    PRIMARY KEY (download_texts_id, downloads_id)

) PARTITION BY RANGE (downloads_id);

CREATE UNIQUE INDEX download_texts_downloads_id
    ON download_texts (downloads_id);

ALTER TABLE download_texts
    ADD CONSTRAINT download_texts_length_is_correct
    CHECK (length(download_text) = download_text_length);


-- Create missing "download_texts" partitions
CREATE OR REPLACE FUNCTION download_texts_create_partitions()
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_downloads_id_create_partitions('download_texts'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Adding foreign key to created partition "%"...', partition;
        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || partition || '_downloads_id_fkey
                FOREIGN KEY (downloads_id)
                REFERENCES ' || REPLACE(partition, 'download_texts', 'downloads_success_content') || ' (downloads_id)
                ON DELETE CASCADE;
        ';

        RAISE NOTICE 'Adding trigger to created partition "%"...', partition;
        EXECUTE '
            CREATE TRIGGER ' || partition || '_test_referenced_download_trigger
                BEFORE INSERT OR UPDATE ON ' || partition || '
                FOR EACH ROW
                EXECUTE PROCEDURE test_referenced_download_trigger(''downloads_id'');
        ';

    END LOOP;

END;
$$
LANGUAGE plpgsql;

COMMENT ON FUNCTION download_texts_create_partitions () IS 'Create missing "download_texts" partitions';

-- Create initial "download_texts" partitions for empty database
SELECT download_texts_create_partitions();


--
-- Individual sentences of every story
--

-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE story_sentences_p (
    story_sentences_p_id    BIGSERIAL   PRIMARY KEY NOT NULL,
    stories_id              INT         NOT NULL,
    sentence_number         INT         NOT NULL,
    sentence                TEXT        NOT NULL,
    media_id                INT         NOT NULL,
    publish_date            TIMESTAMP   NULL,

    -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
    language                VARCHAR(3)  NULL,

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
    is_dup                   BOOLEAN    NULL
);

COMMENT ON TABLE story_sentences_p IS 'Master table for individual sentences of stories
(no indexes, no foreign keys as they will be ineffective)';
COMMENT ON COLUMN story_sentences_p.language IS '2- or 3-character ISO 690 
language code; empty if unknown, NULL if unset';
COMMENT ON COLUMN story_sentences_p.is_dup IS 'Set to true for every sentence for 
which a duplicate sentence was found in a future story (even though that duplicate sentence 
was not added to the table). We only use is_dup in the topic spidering, but I think it is critical
there. It is there because the first time I tried to run a spider on a broadly popular topic, 
it was unusable because of the amount of irrelevant content. When I dug in, I found that stories 
were getting included because of matches on boilerplate content that was getting duped out of 
most stories but not the first time it appeared. So I added the check to remove stories that match 
on a dup sentence, even if it is the dup sentence, and things cleaned up.';

-- Note: "INSERT ... RETURNING *" doesn't work with the trigger, please use
-- "story_sentences" view instead
CREATE OR REPLACE FUNCTION story_sentences_p_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "stories_tags_map_01")
BEGIN
    SELECT partition_by_stories_id_partition_name(
        base_table_name := 'story_sentences_p',
        stories_id := NEW.stories_id
    ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

COMMENT ON FUNCTION story_sentences_p_insert_trigger () IS 'Note: "INSERT ... RETURNING *" 
does not work with the trigger, please use "story_sentences" view instead';

CREATE TRIGGER story_sentences_p_insert_trigger
    BEFORE INSERT ON story_sentences_p
    FOR EACH ROW EXECUTE PROCEDURE story_sentences_p_insert_trigger();


-- Create missing "story_sentences_p" partitions
CREATE OR REPLACE FUNCTION story_sentences_create_partitions()
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_stories_id_create_partitions('story_sentences_p'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;

        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_media_id_fkey
                FOREIGN KEY (media_id) REFERENCES media (media_id) MATCH FULL ON DELETE CASCADE;

            CREATE UNIQUE INDEX ' || partition || '_stories_id_sentence_number
                ON ' || partition || ' (stories_id, sentence_number);

            CREATE INDEX ' || partition || '_sentence_media_week
                ON ' || partition || ' (half_md5(sentence), media_id, week_start_date(publish_date::date));
        ';

    END LOOP;

END;
$$
LANGUAGE plpgsql;

COMMENT ON FUNCTION story_sentences_create_partitions () IS 'Create missing "story_sentences_p" partitions';

-- Create initial "story_sentences_p" partitions for empty database
SELECT story_sentences_create_partitions();


-- Proxy view to "story_sentences_p" to make RETURNING work
CREATE OR REPLACE VIEW story_sentences AS

    SELECT
        story_sentences_p_id AS story_sentences_id,
        stories_id,
        sentence_number,
        sentence,
        media_id,
        publish_date,
        language,
        is_dup
    FROM story_sentences_p;

COMMENT ON VIEW story_sentences IS 'Proxy view to "story_sentences_p" to make RETURNING work 
with partitioned tables';

-- Make RETURNING work with partitioned tables
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW story_sentences
    ALTER COLUMN story_sentences_id
    SET DEFAULT nextval(pg_get_serial_sequence('story_sentences_p', 'story_sentences_p_id'));

-- Prevent the next INSERT from failing
SELECT nextval(pg_get_serial_sequence('story_sentences_p', 'story_sentences_p_id'));


-- Trigger that implements INSERT / UPDATE / DELETE behavior on "story_sentences" view
CREATE OR REPLACE FUNCTION story_sentences_view_insert_update_delete() RETURNS trigger AS $$
BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- By INSERTing into the master table, we're letting triggers choose
        -- the correct partition.
        INSERT INTO story_sentences_p SELECT NEW.*;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE story_sentences_p
            SET stories_id = NEW.stories_id,
                sentence_number = NEW.sentence_number,
                sentence = NEW.sentence,
                media_id = NEW.media_id,
                publish_date = NEW.publish_date,
                language = NEW.language,
                is_dup = NEW.is_dup
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        DELETE FROM story_sentences_p
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION story_sentences_view_insert_update_delete () IS 'Trigger that 
implements INSERT / UPDATE / DELETE behavior on "story_sentences" view. By INSERTing 
into the master table, we are letting triggers choose the correct partition.';

CREATE TRIGGER story_sentences_view_insert_update_delete_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE ON story_sentences
    FOR EACH ROW EXECUTE PROCEDURE story_sentences_view_insert_update_delete();

create table solr_imports (
    solr_imports_id     serial primary key,
    import_date         timestamp not null,
    full_import         boolean not null default false,
    num_stories         bigint
);

create index solr_imports_date on solr_imports ( import_date );

-- Extra stories to import into
create table solr_import_stories (
    stories_id          int not null references stories on delete cascade
);

COMMENT ON TABLE solr_import_stories IS 'Extra stories to import into';

create index solr_import_stories_story on solr_import_stories ( stories_id );

-- log of all stories import into solr, with the import date
create table solr_imported_stories (
    stories_id          int not null references stories on delete cascade,
    import_date         timestamp not null
);

COMMENT ON TABLE solr_imported_stories IS 'log of all stories import into solr, with the import date';

create index solr_imported_stories_story on solr_imported_stories ( stories_id );
create index solr_imported_stories_day on solr_imported_stories ( date_trunc( 'day', import_date ) );

create type topics_job_queue_type AS ENUM ( 'mc', 'public' );

-- the mode is how we analyze the data from the platform (as web pages, social media posts, url sharing posts, etc)
create table topic_modes (
    topic_modes_id          serial primary key,
    name                    varchar(1024) not null unique,
    description             text not null
);

COMMENT ON TABLE topic_modes IS 'the mode is how we analyze the data from the platform 
(as web pages, social media posts, url sharing posts, etc)';

create unique index topic_modes_name on topic_modes(name);

insert into topic_modes ( name, description ) values

    ('web', 'analyze urls using hyperlinks as network edges'),
    ('url_sharing', 'analyze urls shared on social media using co-sharing as network edges');

-- the platform is where the analyzed data lives (web, twitter, reddit, etc)
create table topic_platforms (
    topic_platforms_id      serial primary key,
    name                    varchar(1024) not null unique,
    description             text not null
);

COMMENT ON TABLE topic_platforms IS 'the platform is where the analyzed data lives (web, twitter, reddit, etc)';

create unique index topic_platforms_name on topic_platforms(name);

insert into topic_platforms (name, description) values
    ('web', 'pages on the open web'),
    ('twitter', 'tweets from twitter.com'),
    ('generic_post', 'generic social media posts'),
    ('reddit', 'submissions and comments from reddit.com');

-- the source is where we get the platforn data from (a particular database, api, csv, etc)
create table topic_sources (
    topic_sources_id        serial primary key,
    name                    varchar(1024) not null unique,
    description             text not null
);

COMMENT ON TABLE topic_sources IS 'the source is where we get the 
platforn data from (a particular database, api, csv, etc)';

create unique index topic_sources_name on topic_sources(name);

insert into topic_sources ( name, description ) values
    ('mediacloud', 'import from the mediacloud.org archive'),
    ('crimson_hexagon', 'import from the crimsonhexagon.com forsight api, only accessible to internal media cloud team'),
    ('brandwatch', 'import from the brandwatch api, only accessible to internal media cloud team'),
    ('csv', 'import generic posts directly from csv'),
    ('postgres', 'import generic posts from a postgres table'),
    ('pushshift', 'import from the pushshift.io api'),
    ('google', 'import from search results on google');

-- the pairs of platforms / sources for which the platform can fetch data
create table topic_platforms_sources_map (
    topic_platforms_id      int not null references topic_platforms on delete cascade,
    topic_sources_id        int not null references topic_sources on delete cascade
);

COMMENT ON TABLE topic_platforms_sources_map IS 'the pairs of platforms/sources 
for which the platform can fetch data';

create unique index topic_platforms_sources_map_ps
    on topic_platforms_sources_map ( topic_platforms_id, topic_sources_id );

-- easily create platform source pairs
create function insert_platform_source_pair( text, text ) returns void as $$
    insert into topic_platforms_sources_map ( topic_platforms_id, topic_sources_id )
        select 
                tp.topic_platforms_id,
                ts.topic_sources_id
            from
                topic_platforms tp
                cross join topic_sources ts
            where
                tp.name = $1  and
                ts.name = $2
$$ language sql;

COMMENT ON FUNCTION insert_platform_source_pair ( text, text ) IS 'easily create platform source pairs';

select insert_platform_source_pair( 'web', 'mediacloud' );
select insert_platform_source_pair( 'twitter', 'crimson_hexagon' );
select insert_platform_source_pair( 'generic_post', 'csv' );
select insert_platform_source_pair( 'generic_post', 'postgres' );
select insert_platform_source_pair( 'reddit', 'pushshift' );
select insert_platform_source_pair( 'web', 'google' );

create table topics (
    topics_id        serial primary key,
    name                    varchar(1024) not null,
    pattern                 text,
    solr_seed_query         text,
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

    -- if true, the topic_stories associated with this topic wilbe set to link_mined = 'f' on the next mining job
    respider_stories        boolean not null default false,
    respider_start_date     date null,
    respider_end_date       date null,

    -- space separate list of periods to snapshot
    snapshot_periods        text null,

    -- platform that topic is analyzing
    platform                varchar(1024) not null references topic_platforms(name),

    -- mode of analysis
    mode                    varchar(1024) not null references topic_modes(name) default 'web',

    -- job queue to use for spider and snapshot jobs for this topic
    job_queue               topics_job_queue_type not null,

    -- max stories allowed in the topic
    max_stories             int not null,

    -- if false, we should refuse to spider this topic because the use has not confirmed the new story query syntax
    is_story_index_ready     boolean not null default true,

    -- if true, snapshots are pruned to only stories with a minimum level of engagements (links, shares, etc)
    only_snapshot_engaged_stories   boolean not null default false
);

COMMENT ON COLUMN topics.respider_stories IS 'if true, the topic_stories 
associated with this topic wilbe set to link_mined = "f" on the next mining job';
COMMENT ON COLUMN topics.snapshot_periods IS 'space-separated list of periods to snapshot';
COMMENT ON COLUMN topics.platform IS 'platform that topic is analyzing';
COMMENT ON COLUMN topics.mode IS 'mode of analysis';
COMMENT ON COLUMN topics.job_queue IS 'job queue to use for spider and snapshot jobs for this topic';
COMMENT ON COLUMN topics.is_story_index_ready IS 'if false, we should refuse to spider 
this topic because the use has not confirmed the new story query syntax';
COMMENT ON COLUMN topics.only_snapshot_engaged_stories IS 'if true, snapshots 
are pruned to only stories with a minimum level of engagements (links, shares, etc)';

create unique index topics_name on topics( name );
create unique index topics_media_type_tag_set on topics( media_type_tag_sets_id );

create table topic_seed_queries (
    topic_seed_queries_id   serial primary key,
    topics_id               int not null references topics on delete cascade,
    source                  varchar(1024) not null references topic_sources(name),
    platform                varchar(1024) not null references topic_platforms(name),
    query                   text,
    imported_date           timestamp,
    ignore_pattern          text
);

create index topic_seed_queries_topic on topic_seed_queries( topics_id );

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

-- track self liks and all links for a given domain within a given topic
create table topic_domains (
    topic_domains_id        serial primary key,
    topics_id               int not null,
    domain                  text not null,
    self_links              int not null default 0
);

COMMENT ON TABLE topic_domains IS 'track self liks and all links for a given domain within a given topic';

create unique index topic_domains_domain on topic_domains (topics_id, md5(domain));

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

COMMENT ON TABLE topic_dead_links IS 'topic links for which the http request failed';

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

COMMENT ON TABLE topic_links IS 'no foreign key constraints on topics_id and stories_id 
because we have the combined foreign key constraint pointing to topic_stories below';

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
    bot_policy              bot_policy_type null,
    seed_queries            jsonb
);

create index snapshots_topic on snapshots ( topics_id );

create type snap_period_type AS ENUM ( 'overall', 'weekly', 'monthly', 'custom' );

create type focal_technique_type as enum ( 'Boolean Query', 'URL Sharing' );

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

    -- timespan is an active part of this snapshot
    snapshots_id                    int null references snapshots on delete cascade,

    -- timespan is an archived part of this snapshot (and thus mostly not visible)
    archive_snapshots_id            int null references snapshots on delete cascade,

    foci_id                         int null references foci,
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
    post_count                      int not null,

    -- keep on cascade to avoid accidental deletion
    tags_id                         int references tags,

    check ( ( snapshots_id is null and archive_snapshots_id is not null ) or 
        ( snapshots_id is not null and archive_snapshots_id is null ) )
);

COMMENT ON COLUMN timespans.snapshots_id IS 'individual timespans within a snapshot';
COMMENT ON COLUMN timespans.archive_snapshots_id IS 'timespan is an archived part of 
this snapshot (and thus mostly not visible)';
COMMENT ON COLUMN timespans.tags_id IS 'keep on cascade to avoid accidental deletion';

create index timespans_snapshot on timespans ( snapshots_id );
create unique index timespans_unique on timespans ( snapshots_id, foci_id, start_date, end_date, period );

create table timespan_maps (
    timespan_maps_id                serial primary key,
    timespans_id                    int not null references timespans on delete cascade,
    options                         jsonb not null,
    content                         bytea null,
    url                             text null,
    format                          varchar(1024) not null
);

create index topic_maps_timespan on timespan_maps ( timespans_id );

create table timespan_files (
    timespan_files_id                   serial primary key,
    timespans_id                        int not null references timespans on delete cascade,
    name                                text,
    url                                 text
);

create unique index timespan_files_timespan_name on timespan_files ( timespans_id, name );

create table snapshot_files (
    snapshot_files_id                       serial primary key,
    snapshots_id                        int not null references snapshots on delete cascade,
    name                                text,
    url                                 text
);

create unique index snapshot_files_snapshot_name on snapshot_files ( snapshots_id, name );

-- schema to hold the various snapshot snapshot tables
CREATE SCHEMA snap;

COMMENT ON SCHEMA snap IS 'schema to hold the various snapshot snapshot tables';

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
    publish_date                timestamp       null,
    collect_date                timestamp       not null,
    full_text_rss               boolean         not null default 'f',
    language                    varchar(3)      null   -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
);

COMMENT ON TABLE snap.stories IS 'create a table for each of these tables to hold a snapshot of stories 
relevant to a topic for each snapshot for that topic';
COMMENT ON COLUMN snap.stories.language IS '2- or 3-character ISO 690 
language code; empty if unknown, NULL if unset';

create index stories_id on snap.stories ( snapshots_id, stories_id );

-- stats for various externally dervied statistics about a story.
create table story_statistics (
    story_statistics_id         serial      primary key,
    stories_id                  int         not null references stories on delete cascade,

    facebook_share_count        int         null,
    facebook_comment_count      int         null,
    facebook_reaction_count     int         null,
    facebook_api_collect_date   timestamp   null,
    facebook_api_error          text        null
);

COMMENT ON TABLE story_statistics IS 'stats for various externally dervied statistics about a story.';

create unique index story_statistics_story on story_statistics ( stories_id );


-- stats for deprecated Twitter share counts
create table story_statistics_twitter (
    story_statistics_id         serial      primary key,
    stories_id                  int         not null references stories on delete cascade,

    twitter_url_tweet_count     int         null,
    twitter_api_collect_date    timestamp   null,
    twitter_api_error           text        null
);

COMMENT ON TABLE story_statistics_twitter IS 'stats for deprecated Twitter share counts';

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

-- story -> story links within a timespan
create table snap.story_links (
    timespans_id         int not null
                                            references timespans on delete cascade,
    source_stories_id                       int not null,
    ref_stories_id                          int not null
);

COMMENT ON TABLE snap.story_links IS 'story -> story links within a timespan';

-- TODO: add complex foreign key to check that *_stories_id exist for the snapshot stories snapshot
create index story_links_source on snap.story_links( timespans_id, source_stories_id );

COMMENT ON INDEX snap.story_links_source IS 'TODO: add complex foreign key to check that 
*_stories_id exist for the snapshot stories snapshot';

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

    post_count                              int null,
    author_count                            int null,
    channel_count                           int null
);

COMMENT ON TABLE snap.story_link_counts IS 'link counts for stories within a timespan';

-- TODO: add complex foreign key to check that stories_id exists for the snapshot stories snapshot
create index story_link_counts_ts on snap.story_link_counts ( timespans_id, stories_id );

COMMENT ON INDEX snap.story_link_counts_ts IS 'TODO: add complex foreign key to check that stories_id 
exists for the snapshot stories snapshot';

create index story_link_counts_story on snap.story_link_counts ( stories_id );
create index story_link_counts_fb on snap.story_link_counts ( timespans_id, facebook_share_count desc nulls last );
create index story_link_counts_post on snap.story_link_counts ( timespans_id, post_count desc nulls last);
create index story_link_counts_author on snap.story_link_counts ( timespans_id, author_count desc nulls last);
create index story_link_counts_channel on snap.story_link_counts ( timespans_id, channel_count desc nulls last);

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

    sum_post_count                  int null,
    sum_author_count                int null,
    sum_channel_count               int null
);

COMMENT ON TABLE snap.medium_link_counts IS 'links counts for media within a timespan';

-- TODO: add complex foreign key to check that media_id exists for the snapshot media snapshot
create index medium_link_counts_medium on snap.medium_link_counts ( timespans_id, media_id );

COMMENT ON INDEX snap.medium_link_counts_medium IS 'TODO: add complex foreign key 
to check that media_id exists for the snapshot media snapshot';

create index medium_link_counts_fb on snap.medium_link_counts ( timespans_id, facebook_share_count desc nulls last);
create index medium_link_counts_sum_post on snap.medium_link_counts ( timespans_id, sum_post_count desc nulls last);
create index medium_link_counts_sum_author on snap.medium_link_counts ( timespans_id, sum_author_count desc nulls last);
create index medium_link_counts_sum_channel on snap.medium_link_counts ( timespans_id, sum_channel_count desc nulls last);

create table snap.medium_links (
    timespans_id int not null
                                    references timespans on delete cascade,
    source_media_id                 int not null,
    ref_media_id                    int not null,
    link_count                      int not null
);

-- TODO: add complex foreign key to check that *_media_id exist for the snapshot media snapshot
create index medium_links_source on snap.medium_links( timespans_id, source_media_id );

COMMENT ON INDEX snap.medium_links_source IS 'TODO: add complex foreign key to check that 
*_media_id exist for the snapshot media snapshot';

create index medium_links_ref on snap.medium_links( timespans_id, ref_media_id );

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
    normalized_title_hash       uuid            null,
    description                 text            null,
    publish_date                timestamp       null,
    collect_date                timestamp       not null,
    full_text_rss               boolean         not null default 'f',
    language                    varchar(3)      null   -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
);

COMMENT ON TABLE snap.live_stories IS 'create a mirror of the stories table with the stories 
for each topic. this is to make it much faster to query the stories associated with a given topic, 
rather than querying the contested and bloated stories table.  only inserts and updates on stories 
are triggered, because deleted cascading stories_id and topics_id fields take care of deletes.';
COMMENT ON COLUMN snap.live_stories.language IS '2- or 3-character ISO 690 language code; 
empty if unknown, NULL if unset';

create index live_story_topic on snap.live_stories ( topics_id );
create unique index live_stories_story on snap.live_stories ( topics_id, stories_id );
create index live_stories_story_solo on snap.live_stories ( stories_id );
create index live_stories_topic_story on snap.live_stories ( topic_stories_id );
create index live_stories_title_hash 
    on snap.live_stories ( topics_id, media_id, date_trunc('day', publish_date), normalized_title_hash );


create function insert_live_story() returns trigger as $insert_live_story$
    begin

        insert into snap.live_stories
            ( topics_id, topic_stories_id, stories_id, media_id, url, guid, title, normalized_title_hash, description,
                publish_date, collect_date, full_text_rss, language )
            select NEW.topics_id, NEW.topic_stories_id, NEW.stories_id, s.media_id, s.url, s.guid,
                    s.title, s.normalized_title_hash, s.description, s.publish_date, s.collect_date, s.full_text_rss,
                    s.language
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
                normalized_title_hash = NEW.normalized_title_hash,
                description = NEW.description,
                publish_date = NEW.publish_date,
                collect_date = NEW.collect_date,
                full_text_rss = NEW.full_text_rss,
                language = NEW.language
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

COMMENT ON INDEX snap.snap_word2vec_models_object_id_creation_date IS 'We need to find the latest word2vec model';

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

COMMENT ON TABLE snap.word2vec_models_data IS 'Do not (attempt to) compress BLOBs in "raw_data" because 
they are going to be compressed already';

create table processed_stories (
    processed_stories_id        bigserial          primary key,
    stories_id                  int             not null references stories on delete cascade
);

create index processed_stories_story on processed_stories ( stories_id );

create trigger ps_insert_solr_import_story after insert or update or delete
    on processed_stories for each row execute procedure insert_solr_import_story();

-- list of stories that have been scraped and the source
create table scraped_stories (
    scraped_stories_id      serial primary key,
    stories_id              int not null references stories on delete cascade,
    import_module           text not null
);

COMMENT ON TABLE scraped_stories IS 'list of stories that have been scraped and the source';

create index scraped_stories_story on scraped_stories ( stories_id );

-- dates on which feeds have been scraped with MediaWords::ImportStories and the module used for scraping
create table scraped_feeds (
    feed_scrapes_id         serial primary key,
    feeds_id                int not null references feeds on delete cascade,
    scrape_date             timestamp not null default now(),
    import_module           text not null
);

COMMENT ON TABLE scraped_feeds IS 'dates on which feeds have been scraped with MediaWords::ImportStories 
and the module used for scraping';

create index scraped_feeds_feed on scraped_feeds ( feeds_id );

create view feedly_unscraped_feeds as
    select f.*
        from feeds f
            left join scraped_feeds sf on
                ( f.feeds_id = sf.feeds_id and sf.import_module = 'MediaWords::ImportStories::Feedly' )
        where
            f.type = 'syndicated' and
            f.active = 't' and
            sf.feeds_id is null;


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


--
-- Authentication
--

-- List of users
CREATE TABLE auth_users (
    auth_users_id   SERIAL  PRIMARY KEY,

    -- Emails are case-insensitive
    email           CITEXT  UNIQUE NOT NULL,

    -- Salted hash of a password
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
    
    -- Whether or not the user has consented to the privacy policy
    has_consented                       BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON COLUMN auth_users.email IS 'Emails are case-insensitive';
COMMENT ON COLUMN auth_users.password_hash IS 'salted hash of a password';
COMMENT ON COLUMN auth_users.password_reset_token_hash IS 'Salted hash of a 
password reset token (with Crypt::SaltedHash, algorithm => "SHA-256", salt_len=>64) or NULL';
COMMENT ON COLUMN auth_users.has_consented IS 'Whether user has consented to the privacy policy';

-- Used by daily stats script
CREATE INDEX auth_users_created_day ON auth_users (date_trunc('day', created_date));

COMMENT ON INDEX auth_users_created_day IS 'used by daily stats script';

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

COMMENT ON COLUMN auth_user_api_keys.api_key IS 'must  be 64 bytes in order to prevent someone 
from resetting it to empty string somehow';

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
    ('tm-readonly', 'Topic mapper; excludes media and story editing');


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
COMMENT ON INDEX auth_user_request_daily_counts_email_day IS 'Single index to enforce upsert uniqueness';

-- User limits for logged + throttled controller actions
CREATE TABLE auth_user_limits (

    auth_user_limits_id             SERIAL      PRIMARY KEY NOT NULL,

    auth_users_id                   INTEGER     NOT NULL UNIQUE REFERENCES auth_users(auth_users_id)
                                                ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE,

    -- Request limit (0 or belonging to 'admin' / 'admin-readonly' group = no
    -- limit)
    weekly_requests_limit           INTEGER     NOT NULL DEFAULT 10000,

    -- Requested items (stories) limit (0 or belonging to 'admin' /
    -- 'admin-readonly' group = no limit)
    weekly_requested_items_limit    INTEGER     NOT NULL DEFAULT 100000,

    max_topic_stories               INTEGER     NOT NULL DEFAULT 100000

);

COMMENT ON TABLE auth_user_limits IS 'User limits for logged + throttled controller actions';
COMMENT ON COLUMN auth_user_limits.weekly_requests_limit IS 'Request limit (0 or belonging to 
"admin"/"admin-readonly" group = no limit)';

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


--
-- Activity log
--

CREATE TABLE activities (
    activities_id       SERIAL          PRIMARY KEY,

    -- Activity's name (e.g. "tm_snapshot_topic")
    name                VARCHAR(255)    NOT NULL
                                        CONSTRAINT activities_name_can_not_contain_spaces CHECK(name NOT LIKE '% %'),

    -- When did the activity happen
    creation_date       TIMESTAMP       NOT NULL DEFAULT LOCALTIMESTAMP,

    -- User that executed the activity, either:
    --     * user's email from "auth_users.email" (e.g. "foo@bar.baz.com", or
    --     * username that initiated the action (e.g. "system:foo")
    -- (store user's email instead of ID in case the user gets deleted)
    user_identifier     CITEXT          NOT NULL,

    -- Indexed ID of the object that was modified in some way by the activity
    object_id           BIGINT          NULL,

    -- User-provided reason explaining why the activity was made
    reason              TEXT            NULL,

    -- Other free-form data describing the action in the JSON format
    -- (e.g.: '{ "field": "name", "old_value": "Foo.", "new_value": "Bar." }')
    -- FIXME: has potential to use 'JSON' type instead of 'TEXT' in
    -- PostgreSQL 9.2+
    description_json    TEXT            NOT NULL DEFAULT '{ }'

);

COMMENT ON COLUMN activities.name IS 'activity name, e.g. "tm_snapshot_topic"';
COMMENT ON COLUMN activities.object_id IS 'Indexed ID of the object that was modified 
in some way by the activity';
COMMENT ON COLUMN activities.reason IS 'user-provided reason why the activity was made';
COMMENT ON COLUMN activities.description_json IS 'Other free-form data describing the 
action in the JSON format (e.g.: { "field": "name", "old_value": "Foo.", "new_value": "Bar." }).
FIXME: has potential to use JSON type instead of TEXT in PostgreSQL 9.2+';

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


-- Copy of "feeds" table from yesterday; used for generating reports for rescraping efforts
CREATE TABLE feeds_from_yesterday (
    feeds_id            INT                 NOT NULL,
    media_id            INT                 NOT NULL,
    name                VARCHAR(512)        NOT NULL,
    url                 VARCHAR(1024)       NOT NULL,
    type                feed_type           NOT NULL,
    active              BOOLEAN             NOT NULL
);

COMMENT ON TABLE feeds_from_yesterday IS 'Copy of "feeds" table from yesterday; 
used for generating reports for rescraping efforts';

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
    INSERT INTO feeds_from_yesterday (feeds_id, media_id, name, url, type, active)
        SELECT feeds_id, media_id, name, url, type, active
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
                    SELECT feeds_id, media_id, type, active, url FROM feeds_from_yesterday
                    EXCEPT
                    SELECT feeds_id, media_id, type, active, url FROM feeds
                ) UNION ALL (
                    SELECT feeds_id, media_id, type, active, url FROM feeds
                    EXCEPT
                    SELECT feeds_id, media_id, type, active, url FROM feeds_from_yesterday
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
               feeds_before.type AS before_type,
               feeds_before.active AS before_active,

               feeds_after.name AS after_name,
               feeds_after.url AS after_url,
               feeds_after.type AS after_type,
               feeds_after.active AS after_active

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
$$
LANGUAGE 'plpgsql';


COMMENT ON FUNCTION rescraping_changes () IS 'Print out a diff between "feeds" and "feeds_from_yesterday"';

-- implements link_id as documented in the topics api spec
create table api_links (
    api_links_id        bigserial primary key,
    path                text not null,
    params_json         text not null,
    next_link_id        bigint null references api_links on delete set null deferrable,
    previous_link_id    bigint null references api_links on delete set null deferrable
);

COMMENT ON TABLE api_links IS 'implements link_id as documented in the topics api spec';

create unique index api_links_params on api_links ( path, md5( params_json ) );

-- Create missing partitions for partitioned tables
CREATE OR REPLACE FUNCTION create_missing_partitions()
RETURNS VOID AS
$$
BEGIN

    -- We have to create "downloads" partitions before "download_texts" ones
    -- because "download_texts" will have a foreign key reference to
    -- "downloads_success_content"

    RAISE NOTICE 'Creating partitions in "downloads_success_content" table...';
    PERFORM downloads_success_content_create_partitions();

    RAISE NOTICE 'Creating partitions in "downloads_success_feed" table...';
    PERFORM downloads_success_feed_create_partitions();

    RAISE NOTICE 'Creating partitions in "download_texts" table...';
    PERFORM download_texts_create_partitions();

    RAISE NOTICE 'Creating partitions in "stories_tags_map_p" table...';
    PERFORM stories_tags_map_create_partitions();

    RAISE NOTICE 'Creating partitions in "story_sentences_p" table...';
    PERFORM story_sentences_create_partitions();

    RAISE NOTICE 'Creating partitions in "feeds_stories_map_p" table...';
    PERFORM feeds_stories_map_create_partitions();

END;
$$
LANGUAGE plpgsql;

create view controversies as select topics_id controversies_id, * from topics;
create view controversy_dumps as
    select snapshots_id controversy_dumps_id, topics_id controversies_id, snapshot_date dump_date, * from snapshots;
create view controversy_dump_time_slices as
    select timespans_id controversy_dump_time_slices_id, snapshots_id controversy_dumps_id, foci_id controversy_query_slices_id, *
        from timespans;


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

COMMENT ON VIEW topics_with_user_permission IS 'topics table with auth_users_id and user_permission fields 
that indicate the permission level for the user for the topic.  permissions in decreasing order are admin, 
write, read, none.  users with the admin role have admin permission for every topic. users with admin-readonly 
role have at least read access to every topic.  all users have read access to every is_public topic. otherwise, 
the topic_permissions tableis used, with "none" for no topic_permission.';

-- list of tweet counts and fetching statuses for each day of each topic
create table topic_post_days (
    topic_post_days_id     serial primary key,
    topic_seed_queries_id  int not null references topic_seed_queries on delete cascade,
    day                    date not null,
    num_posts_stored       int not null,
    num_posts_fetched      int not null,
    posts_fetched          boolean not null default false
);

COMMENT ON TABLE topic_post_days IS 'list of tweet counts and fetching statuses for each day of each topic';

create index topic_post_days_td on topic_post_days ( topic_seed_queries_id, day );

-- list of posts associated with a given topic
create table topic_posts (
    topic_posts_id          serial primary key,
    topic_post_days_id      int not null references topic_post_days on delete cascade,
    data                    jsonb not null,
    post_id                 varchar( 1024 ) not null,
    content                 text not null,
    publish_date            timestamp not null,
    author                  varchar( 1024 ) not null,
    channel                 varchar( 1024 ) not null,
    url                     text null
);

COMMENT ON TABLE topic_posts IS 'list of posts associated with a given topic';

create unique index topic_posts_id on topic_posts( topic_post_days_id, post_id );
create index topic_post_topic_author on topic_posts( topic_post_days_id, author );
create index topic_post_topic_channel on topic_posts( topic_post_days_id, channel );

-- urls parsed from topic tweets and imported into topic_seed_urls
create table topic_post_urls (
    topic_post_urls_id      serial primary key,
    topic_posts_id          int not null references topic_posts on delete cascade,
    url                     varchar (1024) not null
);

COMMENT ON TABLE topic_post_urls IS 'urls parsed from topic tweets and imported into topic_seed_urls';

create index topic_post_urls_url on topic_post_urls ( url );
create unique index topic_post_urls_tt on topic_post_urls ( topic_posts_id, url );

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
    publish_date                    text,
    topic_seed_queries_id           int references topic_seed_queries on delete cascade,
    topic_post_urls_id              int references topic_post_urls on delete cascade
);

create index topic_seed_urls_topic on topic_seed_urls( topics_id );
create index topic_seed_urls_url on topic_seed_urls( url );
create index topic_seed_urls_story on topic_seed_urls ( stories_id );
create unique index topic_seed_urls_tpu on topic_seed_urls ( topic_post_urls_id );

-- view that joins together the chain of tables from topic_seed_queries all the way through to
-- topic_stories, so that you get back a topics_id, topic_posts_id stories_id, and topic_seed_queries_id in each
-- row to track which stories came from which posts in which seed queries
create view topic_post_stories as
    select 
            tsq.topics_id,
            tp.topic_posts_id, tp.content, tp.publish_date, tp.author, tp.channel, tp.data,
            tpd.topic_seed_queries_id,
            ts.stories_id,
            tpu.url, tpu.topic_post_urls_id
        from
            topic_seed_queries tsq
            join topic_post_days tpd using ( topic_seed_queries_id )
            join topic_posts tp using ( topic_post_days_id )
            join topic_post_urls tpu using ( topic_posts_id )
            join topic_seed_urls tsu using ( topic_post_urls_id )
            join topic_stories ts 
                on ( ts.topics_id = tsq.topics_id and ts.stories_id = tsu.stories_id );

COMMENT ON VIEW topic_post_stories IS 'view that joins together the chain of tables from topic_seed_queries 
all the way through to topic_stories, so that you get back a topics_id, topic_posts_id stories_id, and 
topic_seed_queries_id in each row to track which stories came from which posts in which seed queries';

create table snap.timespan_posts (
    topic_posts_id     int not null references topic_posts on delete cascade,
    timespans_id        int not null references timespans on delete cascade
);

create unique index snap_timespan_posts_u on snap.timespan_posts( timespans_id, topic_posts_id );

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

COMMENT ON TABLE mediacloud_stats IS 'keep track of basic high level stats for mediacloud for access through api';

-- job states as implemented in mediawords.job.StatefulJobBroker
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

COMMENT ON TABLE job_states IS 'job states as implemented in mediawords.job.StatefulJobBroker';
COMMENT ON COLUMN job_states.class IS 'MediaWords::Job::* class implementing the job';
COMMENT ON COLUMN job_states.state IS 'short class-specific state';
COMMENT ON COLUMN job_states.message IS 'optional longer message describing the state, such 
as a stack trace for an error';

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

COMMENT ON TABLE retweeter_scores IS 'definition of bipolar comparisons for retweeter polarization scores';

-- group retweeters together so that we an compare, for example, sanders/warren retweeters to cruz/kasich retweeters
create table retweeter_groups (
    retweeter_groups_id     serial primary key,
    retweeter_scores_id     int not null references retweeter_scores on delete cascade,
    name                    text not null
);

COMMENT ON TABLE retweeter_groups IS 'group retweeters together so that we 
can compare, for example, sanders/warren retweeters to cruz/kasich retweeters';

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

COMMENT ON TABLE retweeters IS 'list of twitter users within a given topic that have retweeted the given user';

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

COMMENT ON TABLE retweeter_stories IS 'count of shares by retweeters for each retweeted_user in retweeters';

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

COMMENT ON TABLE retweeter_media IS 'polarization scores for media within a topic for the given 
retweeter_scores definition';

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

COMMENT ON SCHEMA cache IS 'schema to hold object caches';

CREATE OR REPLACE LANGUAGE plpgsql;


-- Trigger to update "db_row_last_updated" for cache tables
CREATE OR REPLACE FUNCTION cache.update_cache_db_row_last_updated()
RETURNS TRIGGER AS $$
BEGIN
    NEW.db_row_last_updated = NOW();
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

COMMENT ON FUNCTION cache.update_cache_db_row_last_updated () IS 'Trigger 
to update "db_row_last_updated" for cache tables';

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
CREATE UNLOGGED TABLE cache.s3_raw_downloads_cache (
    s3_raw_downloads_cache_id SERIAL    PRIMARY KEY,

    -- "downloads_id" from "downloads"
    object_id                 BIGINT    NOT NULL,

    -- Will be used to purge old cache objects;
    -- don't forget to update cache.purge_object_caches()
    db_row_last_updated       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    raw_data                  BYTEA     NOT NULL
);


COMMENT ON COLUMN cache.s3_raw_downloads_cache.object_id IS '"downloads_id" from "downloads"';
COMMENT ON COLUMN cache.s3_raw_downloads_cache.db_row_last_updated IS 'Will be used to purge old cache objects; 
do not forget to update cache.purge_object_caches()';

CREATE UNIQUE INDEX s3_raw_downloads_cache_object_id
    ON cache.s3_raw_downloads_cache (object_id);
CREATE INDEX s3_raw_downloads_cache_db_row_last_updated
    ON cache.s3_raw_downloads_cache (db_row_last_updated);

ALTER TABLE cache.s3_raw_downloads_cache
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;

CREATE TRIGGER s3_raw_downloads_cache_db_row_last_updated_trigger
    BEFORE INSERT OR UPDATE ON cache.s3_raw_downloads_cache
    FOR EACH ROW EXECUTE PROCEDURE cache.update_cache_db_row_last_updated();

CREATE TRIGGER s3_raw_downloads_cache_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON cache.s3_raw_downloads_cache
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('object_id');


--
-- Cached extractor results for extraction jobs with use_cache set to true
--
CREATE UNLOGGED TABLE cache.extractor_results_cache (
    extractor_results_cache_id  SERIAL  PRIMARY KEY,
    extracted_html              TEXT    NULL,
    extracted_text              TEXT    NULL,
    downloads_id                BIGINT  NOT NULL,

    -- Will be used to purge old cache objects;
    -- don't forget to update cache.purge_object_caches()
    db_row_last_updated         TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE cache.extractor_results_cache IS 'Cached extractor results for 
extraction jobs with use_cache set to true';
COMMENT ON COLUMN cache.extractor_results_cache.db_row_last_updated IS 'Will be used to purge old cache objects; 
do not forget to update cache.purge_object_caches()';

CREATE UNIQUE INDEX extractor_results_cache_downloads_id
    ON cache.extractor_results_cache (downloads_id);
CREATE INDEX extractor_results_cache_db_row_last_updated
    ON cache.extractor_results_cache (db_row_last_updated);

ALTER TABLE cache.extractor_results_cache
    ALTER COLUMN extracted_html SET STORAGE EXTERNAL,
    ALTER COLUMN extracted_text SET STORAGE EXTERNAL;

CREATE TRIGGER extractor_results_cache_db_row_last_updated_trigger
    BEFORE INSERT OR UPDATE ON cache.extractor_results_cache
    FOR EACH ROW EXECUTE PROCEDURE cache.update_cache_db_row_last_updated();

CREATE TRIGGER extractor_results_cache_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON cache.extractor_results_cache
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('downloads_id');


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

COMMENT ON TABLE domain_web_requests IS 'keep track of per domain web requests so that we can throttle them 
using mediawords.util.web.user_agent.throttled. this is unlogged because we do not care about anything more 
than about 10 seconds old.  we do not have a primary key because we want it just to be a fast table for 
temporary storage.';

create index domain_web_requests_domain on domain_web_requests ( domain );

-- return false if there is a request for the given domain within the last domain_timeout_arg milliseconds.  otherwise
-- return true and insert a row into domain_web_request for the domain.  this function does not lock the table and
-- so may allow some parallel requests through.
create or replace function get_domain_web_requests_lock( domain_arg text, domain_timeout_arg float ) returns boolean as $$
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

COMMENT ON FUNCTION get_domain_web_requests_lock ( domain_arg text, domain_timeout_arg float ) IS 'return 
false if there is a request for the given domain within the last domain_timeout_arg milliseconds.  otherwise
return true and insert a row into domain_web_request for the domain.  this function does not lock the table and
so may allow some parallel requests through. we do not want this table to grow forever or to have to manage 
it externally, so just truncate about every 1 million requests.  only do this if there are more than 1000 rows 
in the table so that unit tests will not randomly fail.';

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
CREATE TABLE media_sitemap_pages (
    media_sitemap_pages_id  BIGSERIAL   PRIMARY KEY,
    media_id                INT         NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,

    -- <loc> -- URL of the page
    url                     TEXT                                  NOT NULL,

    -- <lastmod> -- date of last modification of the URL
    last_modified           TIMESTAMP WITH TIME ZONE              NULL,

    -- <changefreq> -- how frequently the page is likely to change
    change_frequency        media_sitemap_pages_change_frequency  NULL,

    -- <priority> -- priority of this URL relative to other URLs on your site
    priority                DECIMAL(2, 1)                         NOT NULL DEFAULT 0.5,

    -- <news:title> -- title of the news article
    news_title              TEXT                                  NULL,

    -- <news:publication_date> -- article publication date
    news_publish_date       TIMESTAMP WITH TIME ZONE              NULL,

    CONSTRAINT media_sitemap_pages_priority_within_bounds
        CHECK (priority IS NULL OR (priority >= 0.0 AND priority <= 1.0))

);

COMMENT ON TABLE media_sitemap_pages IS 'Pages derived from XML sitemaps (stories or not)';

CREATE INDEX media_sitemap_pages_media_id
    ON media_sitemap_pages (media_id);

CREATE UNIQUE INDEX media_sitemap_pages_url
    ON media_sitemap_pages (url);


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
CREATE TABLE similarweb_domains (
    similarweb_domains_id SERIAL PRIMARY KEY,

    -- Top-level (e.g. cnn.com) or second-level (e.g. edition.cnn.com) domain
    domain TEXT NOT NULL

);

COMMENT ON TABLE similarweb_domains IS 'Domains for which we have tried to fetch SimilarWeb stats.
Every media source domain for which we have tried to fetch estimated visits from SimilarWeb gets 
stored here. The domain might have been invalid or unpopular enough so "similarweb_estimated_visits" 
might not necessarily store stats for every domain in this table.';
COMMENT ON COLUMN similarweb_domains.domain IS 'Top-level (e.g. cnn.com) or second-level 
(e.g. edition.cnn.com) domain';

CREATE UNIQUE INDEX similarweb_domains_domain
    ON similarweb_domains (domain);


--
-- Media - SimilarWeb domain map
--
-- A few media sources might be pointing to one or more domains due to code
-- differences in how domain was extracted from media source's URL between
-- various implementations.
--
CREATE TABLE media_similarweb_domains_map (
    media_similarweb_domains_map_id SERIAL  PRIMARY KEY,

    media_id                        INT     NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,
    similarweb_domains_id           INT     NOT NULL REFERENCES similarweb_domains (similarweb_domains_id) ON DELETE CASCADE
);

COMMENT ON TABLE media_similarweb_domains_map IS 'Media - SimilarWeb domain map. A few media sources 
might be pointing to one or more domains due to code differences in how domain was extracted from media 
source URL between various implementations.';

-- Different media sources can point to the same domain
CREATE UNIQUE INDEX media_similarweb_domains_map_media_id_sdi
    ON media_similarweb_domains_map (media_id, similarweb_domains_id);

COMMENT ON INDEX media_similarweb_domains_map_media_id_sdi IS 'Different media sources can point 
to the same domain';

--
-- SimilarWeb estimated visits for domain
-- (https://www.similarweb.com/corp/developer/estimated_visits_api)
--
CREATE TABLE similarweb_estimated_visits (
    similarweb_estimated_visits_id  SERIAL  PRIMARY KEY,

    -- Domain for which the stats were fetched
    similarweb_domains_id           INT     NOT NULL REFERENCES similarweb_domains (similarweb_domains_id) ON DELETE CASCADE,

    -- Month, e.g. 2018-03-01 for March of 2018
    month                           DATE    NOT NULL,

    -- Visit count is for the main domain only (value of "main_domain_only" API call argument)
    main_domain_only                BOOLEAN NOT NULL,

    -- Visit count
    visits                          BIGINT  NOT NULL

);

COMMENT ON TABLE similarweb_estimated_visits IS 'https://www.similarweb.com/corp/developer/estimated_visits_api';

CREATE UNIQUE INDEX similarweb_estimated_visits_domain_month_mdo
    ON similarweb_estimated_visits (similarweb_domains_id, month, main_domain_only);


--
-- Enclosures added to the story's feed item
--
CREATE TABLE story_enclosures (
    story_enclosures_id     BIGSERIAL   PRIMARY KEY,
    stories_id              INT         NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,

    -- Podcast enclosure URL
    url                     TEXT        NOT NULL,

    -- RSS spec says that enclosure's "length" and "type" are required too but
    -- I guess some podcasts don't care that much about specs so both are
    -- allowed to be NULL:

    -- MIME type as reported by <enclosure />
    mime_type               CITEXT      NULL,

    -- Length in bytes as reported by <enclosure />
    length                  BIGINT      NULL
);

COMMENT ON TABLE story_enclosures IS 'Enclosures added to feed item of the story';

CREATE UNIQUE INDEX story_enclosures_stories_id_url
    ON story_enclosures (stories_id, url);

--
-- Celery job results
-- (configured as self.__app.conf.database_table_names; schema is dictated by Celery + SQLAlchemy)
--

CREATE TABLE celery_groups (
    id          BIGINT                      NOT NULL    PRIMARY KEY,
    taskset_id  CHARACTER VARYING(155)      NULL        UNIQUE,
    result      BYTEA                       NULL,
    date_done   TIMESTAMP WITHOUT TIME ZONE NULL
);

COMMENT ON TABLE celery_groups IS 'Celery job results (configured as self.__app.conf.database_table_names; 
schema is dictated by Celery + SQLAlchemy)';

CREATE TABLE celery_tasks (
    id          BIGINT                      NOT NULL    PRIMARY KEY,
    task_id     CHARACTER VARYING(155)      NULL        UNIQUE,
    status      CHARACTER VARYING(50)       NULL,
    result      BYTEA                       NULL,
    date_done   TIMESTAMP WITHOUT TIME ZONE NULL,
    traceback   TEXT                        NULL
);

CREATE SEQUENCE task_id_sequence AS BIGINT;
