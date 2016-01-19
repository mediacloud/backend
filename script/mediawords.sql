--
-- Schema for MediaWords database
--

-- CREATE LANGUAGE IF NOT EXISTS plpgsql

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION create_language_plpgsql()
RETURNS BOOLEAN AS $$
    CREATE LANGUAGE plpgsql;
    SELECT TRUE;
$$ LANGUAGE SQL;

SELECT CASE WHEN NOT
    (
        SELECT  TRUE AS exists
        FROM    pg_language
        WHERE   lanname = 'plpgsql'
        UNION
        SELECT  FALSE AS exists
        ORDER BY exists DESC
        LIMIT 1
    )
THEN
    create_language_plpgsql()
ELSE
    FALSE
END AS plpgsql_created;

DROP FUNCTION create_language_plpgsql();



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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4520;

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
INSERT INTO database_variables( name, value ) values ( 'LAST_STORY_SENTENCES_ID_PROCESSED', '0' );

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

CREATE OR REPLACE FUNCTION loop_forever()
    RETURNS VOID AS
$$
DECLARE
    temp integer;
BEGIN
   temp := 1;
   LOOP
    temp := temp + 1;
    perform pg_sleep( 1 );
    RAISE NOTICE 'time - %', temp;
   END LOOP;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE
  COST 10;


CREATE OR REPLACE FUNCTION purge_story_sentences(default_start_day date, default_end_day date)
  RETURNS VOID  AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
BEGIN
    current_time := timeofday()::timestamp;

    RAISE NOTICE 'time - %', current_time;

    FOR media_rec IN (
          SELECT media_id,
                 COALESCE( sw_data_start_date, default_start_day ) AS start_date
          FROM media
          WHERE NOT (COALESCE( sw_data_start_date, default_start_day ) IS NULL )
          ORDER BY media_id
      ) LOOP
        current_time := timeofday()::timestamp;

        RAISE NOTICE 'media_id is %, start_date - % time - %', media_rec.media_id, media_rec.start_date, current_time;

        DELETE FROM story_sentences
        WHERE media_id = media_rec.media_id
          AND date_trunc( 'day', publish_date ) < date_trunc( 'day', media_rec.start_date );

    END LOOP;

  RAISE NOTICE 'time - %', current_time;  -- Prints 30
  FOR media_rec IN (
          SELECT media_id,
                 COALESCE( sw_data_end_date, default_end_day ) AS end_date
          FROM media
          WHERE NOT (COALESCE( sw_data_end_date, default_end_day ) IS NULL )
          ORDER BY media_id
      ) LOOP
        current_time := timeofday()::timestamp;

        RAISE NOTICE 'media_id is %, end_date - % time - %', media_rec.media_id, media_rec.end_date, current_time;

        DELETE from story_sentences
        WHERE media_id = media_rec.media_id
          AND date_trunc( 'day', publish_date ) > date_trunc( 'day', media_rec.end_date );

    END LOOP;
END;
$$
LANGUAGE 'plpgsql'
 ;

CREATE OR REPLACE FUNCTION purge_story_sentence_counts(default_start_day date, default_end_day date)
  RETURNS VOID  AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
BEGIN
    current_time := timeofday()::timestamp;

    RAISE NOTICE 'time - %', current_time;
    FOR media_rec IN (
          SELECT media_id,
                 COALESCE( sw_data_start_date, default_start_day ) AS start_date
          FROM media
          WHERE NOT (COALESCE ( sw_data_start_date, default_start_day ) IS NULL )
          ORDER BY media_id
      ) LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, start_date - % time - %', media_rec.media_id, media_rec.start_date, current_time;
        DELETE from story_sentence_counts where media_id = media_rec.media_id and publish_week < date_trunc( 'day', media_rec.start_date );
    END LOOP;

  RAISE NOTICE 'time - %', current_time;  -- Prints 30
  FOR media_rec IN (
          SELECT media_id,
                 COALESCE( sw_data_end_date, default_end_day ) AS end_date
          FROM media
          WHERE NOT (COALESCE ( sw_data_end_date, default_end_day ) IS NULL )
          ORDER BY media_id
      ) LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, end_date - % time - %', media_rec.media_id, media_rec.end_date, current_time;
        DELETE from story_sentence_counts where media_id = media_rec.media_id and publish_week > date_trunc( 'day', media_rec.end_date );
    END LOOP;
END;
$$
LANGUAGE 'plpgsql'
 ;

CREATE OR REPLACE FUNCTION update_media_last_updated () RETURNS trigger AS
$$
   DECLARE
   BEGIN

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
      	 update media set db_row_last_updated = now() where media_id = NEW.media_id;
      END IF;

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
      	 update media set db_row_last_updated = now() where media_id = OLD.media_id;
      END IF;

      RETURN NEW;
   END;
$$
LANGUAGE 'plpgsql';

-- Store whether story triggers should be enable in PRIVATE.use_story_triggers
-- This variable is session based. If it's not set, set it to enable triggers and return true
CREATE OR REPLACE FUNCTION  story_triggers_enabled() RETURNS boolean  LANGUAGE  plpgsql AS $$
BEGIN

    BEGIN
       IF current_setting('PRIVATE.use_story_triggers') = '' THEN
          perform enable_story_triggers();
       END IF;
       EXCEPTION when undefined_object then
        perform enable_story_triggers();

     END;

    return true;
    return current_setting('PRIVATE.use_story_triggers') = 'yes';
END$$;

CREATE OR REPLACE FUNCTION  enable_story_triggers() RETURNS void LANGUAGE  plpgsql AS $$
DECLARE
BEGIN
        perform set_config('PRIVATE.use_story_triggers', 'yes', false );
END$$;

CREATE OR REPLACE FUNCTION  disable_story_triggers() RETURNS void LANGUAGE  plpgsql AS $$
DECLARE
BEGIN
        perform set_config('PRIVATE.use_story_triggers', 'no', false );
END$$;

CREATE OR REPLACE FUNCTION last_updated_trigger () RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
      table_with_trigger_column  boolean default false;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';
        IF TG_TABLE_NAME in ( 'processed_stories', 'stories', 'story_sentences') THEN
           table_with_trigger_column = true;
        ELSE
           table_with_trigger_column = false;
        END IF;

	IF table_with_trigger_column THEN
	   IF ( ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') ) AND NEW.disable_triggers THEN
     	       RETURN NEW;
           END IF;
      END IF;

      IF ( story_triggers_enabled() ) AND ( ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') ) then

      	 NEW.db_row_last_updated = now();

      END IF;

      RETURN NEW;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_trigger () RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN

        IF NOT story_triggers_enabled() THEN
           RETURN NULL;
        END IF;

        IF NEW.disable_triggers THEN
           RETURN NULL;
        END IF;

	UPDATE story_sentences set db_row_last_updated = now() where stories_id = NEW.stories_id;
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_stories_updated_time_by_stories_id_trigger () RETURNS trigger AS
$$
    DECLARE
        path_change boolean;
        table_with_trigger_column  boolean default false;
        reference_stories_id integer default null;
    BEGIN

       IF NOT story_triggers_enabled() THEN
           RETURN NULL;
        END IF;

        IF TG_TABLE_NAME in ( 'processed_stories', 'stories', 'story_sentences') THEN
           table_with_trigger_column = true;
        ELSE
           table_with_trigger_column = false;
        END IF;

	IF table_with_trigger_column THEN
	   IF TG_OP = 'INSERT' AND NEW.disable_triggers THEN
	       RETURN NULL;
	   ELSEIF ( ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') ) AND OLD.disable_triggers THEN
     	       RETURN NULL;
           END IF;
       END IF;

        IF TG_OP = 'INSERT' THEN
            -- The "old" record doesn't exist
            reference_stories_id = NEW.stories_id;
        ELSIF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
            reference_stories_id = OLD.stories_id;
        ELSE
            RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;
        END IF;

	IF table_with_trigger_column THEN
            UPDATE stories
               SET db_row_last_updated = now()
               WHERE stories_id = reference_stories_id;
            RETURN NULL;
        ELSE
            UPDATE stories
               SET db_row_last_updated = now()
               WHERE stories_id = reference_stories_id and (disable_triggers is NOT true);
            RETURN NULL;
        END IF;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_by_story_sentences_id_trigger () RETURNS trigger AS
$$
    DECLARE
        path_change boolean;
        table_with_trigger_column  boolean default false;
        reference_story_sentences_id bigint default null;
    BEGIN

       IF NOT story_triggers_enabled() THEN
           RETURN NULL;
        END IF;

       IF NOT story_triggers_enabled() THEN
           RETURN NULL;
        END IF;

        IF TG_TABLE_NAME in ( 'processed_stories', 'stories', 'story_sentences') THEN
           table_with_trigger_column = true;
        ELSE
           table_with_trigger_column = false;
        END IF;

	IF table_with_trigger_column THEN
	   IF TG_OP = 'INSERT' AND NEW.disable_triggers THEN
	       RETURN NULL;
	   ELSEIF ( ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') ) AND OLD.disable_triggers THEN
     	       RETURN NULL;
           END IF;
       END IF;

        IF TG_OP = 'INSERT' THEN
            -- The "old" record doesn't exist
            reference_story_sentences_id = NEW.story_sentences_id;
        ELSIF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
            reference_story_sentences_id = OLD.story_sentences_id;
        ELSE
            RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;
        END IF;

	IF table_with_trigger_column THEN
            UPDATE story_sentences
              SET db_row_last_updated = now()
              WHERE story_sentences_id = reference_story_sentences_id;
            RETURN NULL;
        ELSE
            UPDATE story_sentences
              SET db_row_last_updated = now()
              WHERE story_sentences_id = reference_story_sentences_id and (disable_triggers is NOT true);
            RETURN NULL;
        END IF;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_stories_updated_time_by_media_id_trigger () RETURNS trigger AS
$$
    DECLARE
        path_change boolean;
        reference_media_id integer default null;
    BEGIN

        IF TG_OP = 'INSERT' THEN
            -- The "old" record doesn't exist
            reference_media_id = EWEW.media_id;
        ELSIF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
            reference_media_id = OLD.media_id;
        ELSE
            RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;
        END IF;

        UPDATE stories
        SET db_row_last_updated = now()
        WHERE media_id = reference_media_id;

        RETURN NULL;
    END;
$$
LANGUAGE 'plpgsql';

create table media (
    media_id            serial          primary key,
    url                 varchar(1024)   not null,
    name                varchar(128)    not null,
    moderated           boolean         not null,
    moderation_notes    text            null,
    full_text_rss       boolean,
    extract_author      boolean         default(false),
    sw_data_start_date  date            default(null),
    sw_data_end_date    date            default(null),

    -- It indicates that the media source includes a substantial number of
    -- links in its feeds that are not its own. These media sources cause
    -- problems for the cm spider, which finds those foreign rss links and
    -- thinks that the urls belong to the parent media source.
    foreign_rss_links   boolean         not null default( false ),
    dup_media_id        int             null references media on delete set null deferrable,
    is_not_dup          boolean         null,
    use_pager           boolean         null,
    unpaged_stories     int             not null default 0,

    -- Annotate stories from this media source with CoreNLP?
    annotate_with_corenlp   BOOLEAN     NOT NULL DEFAULT(false),

    -- Delay content downloads for this media source this many hours
    content_delay       int             null,

    db_row_last_updated         timestamp with time zone,

    CONSTRAINT media_name_not_empty CHECK ( ( (name)::text <> ''::text ) ),
    CONSTRAINT media_self_dup CHECK ( dup_media_id IS NULL OR dup_media_id <> media_id )
);

create unique index media_name on media(name);
create unique index media_url on media(url);
create index media_moderated on media(moderated);
create index media_db_row_last_updated on media( db_row_last_updated );

CREATE INDEX media_name_trgm on media USING gin (name gin_trgm_ops);
CREATE INDEX media_url_trgm on media USING gin (url gin_trgm_ops);

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

create type feed_feed_type AS ENUM ( 'syndicated', 'web_page' );

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
    name                varchar(512)    not null,
    label               varchar(512),
    description         text,
    show_on_media       boolean,
    show_on_stories     boolean,
    CONSTRAINT tag_sets_name_not_empty CHECK (((name)::text <> ''::text))
);

create unique index tag_sets_name on tag_sets (name);

create table tags (
    tags_id                serial            primary key,
    tag_sets_id            int                not null references tag_sets,
    tag                    varchar(512)    not null,
    label                  varchar(512),
    description            text,
    show_on_media          boolean,
    show_on_stories        boolean,
        CONSTRAINT no_line_feed CHECK (((NOT ((tag)::text ~~ '%
%'::text)) AND (NOT ((tag)::text ~~ '%
%'::text)))),
        CONSTRAINT tag_not_empty CHECK (((tag)::text <> ''::text))
);

create index tags_tag_sets_id ON tags (tag_sets_id);
create unique index tags_tag on tags (tag, tag_sets_id);
create index tags_tag_1 on tags (split_part(tag, ' ', 1));
create index tags_tag_2 on tags (split_part(tag, ' ', 2));
create index tags_tag_3 on tags (split_part(tag, ' ', 3));

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
    tags_id                int                not null references tags on delete cascade
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


-- A dashboard defines which collections, dates, and topics appear together within a given dashboard screen.
-- For example, a dashboard might include three media_sets for russian collections, a set of dates for which
-- to generate a dashboard for those collections, and a set of topics to use for specific dates for all media
-- sets within the collection
create table dashboards (
    dashboards_id               serial          primary key,
    name                        varchar(1024)   not null,
    start_date                  timestamp       not null,
    end_date                    timestamp       not null,

    -- A "public" dashboard is the one that is shown in the web UI
    -- (e.g. the "create controversy" page)
    public                      boolean         not null default true
);

create unique index dashboards_name on dashboards ( name );
CREATE INDEX dashboards_name_trgm on dashboards USING gin (name gin_trgm_ops);

CREATE TYPE query_version_enum AS ENUM ('1.0');

create table queries (
    queries_id              serial              primary key,
    start_date              date                not null,
    end_date                date                not null,
    generate_page           boolean             not null default false,
    creation_date           timestamp           not null default now(),
    description             text                null,
    dashboards_id           int                 null references dashboards,
    md5_signature           varchar(32)         not null,
    query_version           query_version_enum  NOT NULL DEFAULT enum_last (null::query_version_enum )
);

create index queries_creation_date on queries (creation_date);
create unique index queries_hash_version on queries (md5_signature, query_version);
create index queries_md5_signature on queries  (md5_signature);

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

-- Sets of media sources that should appear in the dashboard
-- The contents of the row depend on the set_type, which can be one of:
--  medium -- a single medium (media_id)
--  collection -- all media associated with the given tag (tags_id)
--  cluster -- all media within the given clusters (clusters_id)
-- see the check constraint for the definition of which set_type has which rows set
create table media_sets (
    media_sets_id               serial      primary key,
    name                        text        not null,
    description                 text        null,
    set_type                    text        not null,
    media_id                    int         references media on delete cascade,
    tags_id                     int         references tags on delete cascade,
    creation_date               timestamp   default now(),
    vectors_added               boolean     default false,
    include_in_dump             boolean     default true
);

CREATE INDEX media_sets_name_trgm on media_sets USING gin (name gin_trgm_ops);
CREATE INDEX media_sets_description_trgm on media_sets USING gin (description gin_trgm_ops);

CREATE VIEW media_sets_tt2_locale_format AS
    SELECT '[% c.loc("' || COALESCE( name, '') || '") %]' || E'\n' ||  '[% c.loc("' || COALESCE (description, '') || '") %] ' AS tt2_value
    FROM media_sets
    WHERE set_type = 'collection'
    ORDER BY media_sets_id;

alter table media_sets add constraint dashboard_media_sets_type
check ( ( ( set_type = 'medium' ) and ( media_id is not null ) )
        or
        ( ( set_type = 'collection' ) and ( tags_id is not null ) )
        or
        ( ( set_type = 'cluster' ) ) );

create unique index media_sets_medium on media_sets ( media_id );
create index media_sets_tag on media_sets ( tags_id );
create index media_sets_vectors_added on media_sets ( vectors_added );

create table media_sets_media_map (
    media_sets_media_map_id     serial  primary key,
    media_sets_id               int     not null references media_sets on delete cascade,
    media_id                    int     not null references media on delete cascade
);


create index media_sets_media_map_set on media_sets_media_map ( media_sets_id );
create index media_sets_media_map_media on media_sets_media_map ( media_id );

DROP TRIGGER IF EXISTS msmm_last_updated on media_sets_media_map CASCADE;
CREATE TRIGGER msmm_last_updated BEFORE INSERT OR UPDATE OR DELETE
    ON media_sets_media_map FOR EACH ROW EXECUTE PROCEDURE update_media_last_updated() ;


CREATE OR REPLACE FUNCTION media_set_sw_data_retention_dates(
    v_media_sets_id int,
    default_start_day date,
    default_end_day date,

    OUT start_date date,
    OUT end_date date
) AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
BEGIN
    current_time := timeofday()::timestamp;

    --RAISE NOTICE 'time - % ', current_time;

    SELECT media_sets_id,
           MIN(coalesce (media.sw_data_start_date, default_start_day)) AS sw_data_start_date,
           max(coalesce (media.sw_data_end_date,  default_end_day)) AS sw_data_end_date
    INTO media_rec
    FROM media_sets_media_map
        JOIN media
          ON media_sets_media_map.media_id = media.media_id
         AND media_sets_id = v_media_sets_id
    GROUP BY media_sets_id;

    start_date = media_rec.sw_data_start_date;
    end_date = media_rec.sw_data_end_date;

    --RAISE NOTICE 'start date - %', start_date;
    --RAISE NOTICE 'end date - %', end_date;

    return;
END;
$$
LANGUAGE 'plpgsql' STABLE
 ;

CREATE VIEW media_sets_explict_sw_data_dates AS
    SELECT media_sets_id,
           MIN(media.sw_data_start_date) AS sw_data_start_date,
           MAX(media.sw_data_end_date) AS sw_data_end_date
    FROM media_sets_media_map
        JOIN media ON media_sets_media_map.media_id = media.media_id
    GROUP BY media_sets_id;

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


CREATE OR REPLACE FUNCTION media_set_retains_sw_data_for_date(
    v_media_sets_id int,
    test_date date,
    default_start_day date,
    default_end_day date
)
  RETURNS BOOLEAN AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
    start_date   date;
    end_date     date;
BEGIN
    current_time := timeofday()::timestamp;

    -- RAISE NOTICE 'time - %', current_time;

   media_rec = media_set_sw_data_retention_dates( v_media_sets_id, default_start_day,  default_end_day ); -- INTO (media_rec);

   start_date = media_rec.start_date;
   end_date = media_rec.end_date;

    -- RAISE NOTICE 'start date - %', start_date;
    -- RAISE NOTICE 'end date - %', end_date;

    return  ( ( start_date is null )  OR ( start_date <= test_date ) ) AND ( (end_date is null ) OR ( end_date >= test_date ) );
END;
$$
LANGUAGE 'plpgsql' STABLE
 ;

-- dashboard_media_sets associates certain 'collection' type media_sets with a given dashboard.
-- Those assocaited media_sets will appear on the dashboard page, and the media associated with
-- the collections will be available from autocomplete box.
-- This table is also used to determine for which dates to create [daily|weekly|top_500_weekly]_words
-- entries for which media_sets / topics
create table dashboard_media_sets (
    dashboard_media_sets_id     serial          primary key,
    dashboards_id               int             not null references dashboards on delete cascade,
    media_sets_id               int             not null references media_sets on delete cascade,
    color                       text            null
);

CREATE UNIQUE INDEX dashboard_media_sets_media_set_dashboard on dashboard_media_sets(media_sets_id, dashboards_id);
create index dashboard_media_sets_dashboard on dashboard_media_sets( dashboards_id );

-- A topic is a query used to generate dashboard results for a subset of matching stories.
-- For instance, a topic with a query of 'health' would generate dashboard results for only stories that
-- include the word 'health'.  a given topic is confined to a given dashbaord and optionally to date range
-- within the date range of the dashboard.
create table dashboard_topics (
    dashboard_topics_id         serial          primary key,
    name                        varchar(256)    not null,
    query                       varchar(1024)   not null,
    language                    varchar(3)      null,   -- 2- or 3-character ISO 690 language code
    dashboards_id               int             not null references dashboards on delete cascade,
    start_date                  timestamp       not null,
    end_date                    timestamp       not null,
    vectors_added               boolean         default false
);

create index dashboard_topics_dashboard on dashboard_topics ( dashboards_id );
create index dashboard_topics_vectors_added on dashboard_topics ( vectors_added );

CREATE VIEW dashboard_topics_tt2_locale_format AS
    SELECT DISTINCT ON (tt2_value) '[% c.loc("' || name || '") %]' || ' - ' || '[% c.loc("' || lower(name) || '") %]' AS tt2_value
    FROM (
        SELECT *
        FROM dashboard_topics
        ORDER BY name,
                 dashboard_topics_id
    ) AS dashboard_topic_names
    ORDER BY tt2_value;

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
    language                    varchar(3)      null,   -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
    disable_triggers            boolean  null
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
CREATE TRIGGER stories_last_updated_trigger BEFORE INSERT OR UPDATE ON stories FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger() ;
DROP TRIGGER IF EXISTS stories_update_story_sentences_last_updated_trigger on stories CASCADE;

CREATE TRIGGER stories_update_story_sentences_last_updated_trigger
    AFTER INSERT OR UPDATE ON stories
    FOR EACH ROW EXECUTE PROCEDURE update_story_sentences_updated_time_trigger() ;

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

CREATE TYPE download_file_status AS ENUM (
    'tbd',
    'missing',
    'na',
    'present',
    'inline',
    'redownloaded',
    'error_redownloading'
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
    extracted           boolean         not null default 'f',
    old_download_time   timestamp without time zone,
    old_state           download_state,
    file_status         download_file_status not null default 'tbd',
    relative_file_path  text            not null default 'tbd'
);

UPDATE downloads set old_download_time = download_time, old_state = state;


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

CREATE INDEX file_status_downloads_time_new_format
    ON downloads USING btree (file_status, download_time)
    WHERE relative_file_path ~~ 'mediacloud-%'::text;

CREATE INDEX relative_file_paths_new_format_to_verify
    ON downloads USING btree (relative_file_path)
    WHERE file_status = 'tbd'::download_file_status
      AND relative_file_path <> 'tbd'::text
      AND relative_file_path <> 'error'::text
      AND relative_file_path <> 'na'::text
      AND relative_file_path <> 'inline'::text
      AND relative_file_path ~~ 'mediacloud-%'::text;

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
    object_id           INTEGER     NOT NULL REFERENCES downloads ON DELETE CASCADE,
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

create table stories_tags_map
(
    stories_tags_map_id     serial  primary key,
    stories_id              int     not null references stories on delete cascade,
    tags_id                 int     not null references tags on delete cascade,
    db_row_last_updated                timestamp with time zone not null default now()
);

DROP TRIGGER IF EXISTS stories_tags_map_last_updated_trigger on stories_tags_map CASCADE;

CREATE TRIGGER stories_tags_map_last_updated_trigger
    BEFORE INSERT OR UPDATE ON stories_tags_map
    FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger() ;

DROP TRIGGER IF EXISTS stories_tags_map_update_stories_last_updated_trigger on stories_tags_map;

CREATE TRIGGER stories_tags_map_update_stories_last_updated_trigger
    AFTER INSERT OR UPDATE OR DELETE ON stories_tags_map
    FOR EACH ROW EXECUTE PROCEDURE update_stories_updated_time_by_stories_id_trigger();

CREATE index stories_tags_map_db_row_last_updated on stories_tags_map ( db_row_last_updated );
create unique index stories_tags_map_story on stories_tags_map (stories_id, tags_id);
create index stories_tags_map_tag on stories_tags_map (tags_id);
CREATE INDEX stories_tags_map_story_id ON stories_tags_map USING btree (stories_id);

create table extractor_training_lines
(
    extractor_training_lines_id     serial      primary key,
    line_number                     int         not null,
    required                        boolean     not null,
    downloads_id                    int         not null references downloads on delete cascade,
    "time" timestamp without time zone,
    submitter character varying(256)
);

create unique index extractor_training_lines_line on extractor_training_lines(line_number, downloads_id);
create index extractor_training_lines_download on extractor_training_lines(downloads_id);

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


create table extracted_lines
(
    extracted_lines_id          serial          primary key,
    line_number                 int             not null,
    download_texts_id           int             not null references download_texts on delete cascade
);

create index extracted_lines_download_text on extracted_lines(download_texts_id);

CREATE TYPE url_discovery_status_type as ENUM ('already_processed', 'not_yet_processed');
CREATE TABLE url_discovery_counts (
       url_discovery_status url_discovery_status_type PRIMARY KEY,
       num_urls INT DEFAULT  0);

INSERT  into url_discovery_counts VALUES ('already_processed');
INSERT  into url_discovery_counts VALUES ('not_yet_processed');

-- VIEWS

CREATE VIEW media_extractor_training_downloads_count AS
    SELECT media.media_id,
           COALESCE(foo.extractor_training_downloads_for_media_id, (0)::bigint) AS extractor_training_download_count
    FROM media
        LEFT JOIN (
            SELECT stories.media_id,
                   COUNT(stories.media_id) AS extractor_training_downloads_for_media_id
            FROM extractor_training_lines,
                 downloads,
                 stories
            WHERE extractor_training_lines.downloads_id = downloads.downloads_id
              AND downloads.stories_id = stories.stories_id
            GROUP BY stories.media_id
            ORDER BY stories.media_id
        ) AS foo ON media.media_id = foo.media_id;

CREATE VIEW yahoo_top_political_2008_media AS
    SELECT DISTINCT media_tags_map.media_id
    FROM media_tags_map,
         (
            SELECT tags.tags_id
            FROM tags,
                 (
                    SELECT DISTINCT media_tags_map.tags_id
                    FROM media_tags_map
                    ORDER BY media_tags_map.tags_id
                 ) AS media_tags
            WHERE tags.tags_id = media_tags.tags_id
              AND (tags.tag)::text ~~ 'yahoo_top_political_2008'::text
         ) AS interesting_media_tags
    WHERE media_tags_map.tags_id = interesting_media_tags.tags_id
    ORDER BY media_tags_map.media_id;

CREATE VIEW technorati_top_political_2008_media AS
    SELECT DISTINCT media_tags_map.media_id
    FROM media_tags_map,
         (
            SELECT tags.tags_id
            FROM tags,
                 (
                    SELECT DISTINCT media_tags_map.tags_id
                    FROM media_tags_map
                    ORDER BY media_tags_map.tags_id
                 ) AS media_tags
            WHERE tags.tags_id = media_tags.tags_id
              AND (tags.tag)::text ~~ 'technorati_top_political_2008'::text
         ) AS interesting_media_tags
    WHERE media_tags_map.tags_id = interesting_media_tags.tags_id
    ORDER BY media_tags_map.media_id;

CREATE VIEW media_extractor_training_downloads_count_adjustments AS
    SELECT yahoo.media_id,
           yahoo.yahoo_count_adjustment,
           tech.technorati_count_adjustment
    FROM (
            SELECT media_extractor_training_downloads_count.media_id,
                   COALESCE(foo.yahoo_count_adjustment, 0) AS yahoo_count_adjustment
            FROM (media_extractor_training_downloads_count
                LEFT JOIN (
                    SELECT yahoo_top_political_2008_media.media_id,
                           1 AS yahoo_count_adjustment
                    FROM yahoo_top_political_2008_media
                ) AS foo ON foo.media_id = media_extractor_training_downloads_count.media_id
        )) AS yahoo,
        (
            SELECT media_extractor_training_downloads_count.media_id,
                   COALESCE(foo.count_adjustment, 0) AS technorati_count_adjustment
            FROM (media_extractor_training_downloads_count
                LEFT JOIN (
                    SELECT technorati_top_political_2008_media.media_id,
                           1 AS count_adjustment
                    FROM technorati_top_political_2008_media
                ) AS foo ON foo.media_id = media_extractor_training_downloads_count.media_id
        )) AS tech
    WHERE tech.media_id = yahoo.media_id;

CREATE VIEW media_adjusted_extractor_training_downloads_count AS
    SELECT media_extractor_training_downloads_count.media_id,
           (
               (media_extractor_training_downloads_count.extractor_training_download_count -
               (2 * media_extractor_training_downloads_count_adjustments.yahoo_count_adjustment)) -
               (2 * media_extractor_training_downloads_count_adjustments.technorati_count_adjustment)
           ) AS count
    FROM media_extractor_training_downloads_count
        JOIN media_extractor_training_downloads_count_adjustments
            ON media_extractor_training_downloads_count.media_id = media_extractor_training_downloads_count_adjustments.media_id
    ORDER BY (
        (media_extractor_training_downloads_count.extractor_training_download_count -
        (2 * media_extractor_training_downloads_count_adjustments.yahoo_count_adjustment)) -
        (2 * media_extractor_training_downloads_count_adjustments.technorati_count_adjustment)
    );

CREATE TABLE extractor_results_cache (
    extractor_results_cache_id integer NOT NULL,
    is_story boolean NOT NULL,
    explanation text,
    discounted_html_density double precision,
    html_density double precision,
    downloads_id integer,
    line_number integer
);
CREATE SEQUENCE extractor_results_cache_extractor_results_cache_id_seq
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;
ALTER SEQUENCE extractor_results_cache_extractor_results_cache_id_seq OWNED BY extractor_results_cache.extractor_results_cache_id;

ALTER TABLE extractor_results_cache
    ALTER COLUMN extractor_results_cache_id
        SET DEFAULT nextval('extractor_results_cache_extractor_results_cache_id_seq'::regclass);

ALTER TABLE ONLY extractor_results_cache
    ADD CONSTRAINT extractor_results_cache_pkey PRIMARY KEY (extractor_results_cache_id);
CREATE INDEX extractor_results_cache_downloads_id_index ON extractor_results_cache USING btree (downloads_id);

create table story_sentences (
       story_sentences_id           bigserial       primary key,
       stories_id                   int             not null, -- references stories on delete cascade,
       sentence_number              int             not null,
       sentence                     text            not null,
       media_id                     int             not null, -- references media on delete cascade,
       publish_date                 timestamp       not null,
       db_row_last_updated          timestamp with time zone, -- time this row was last updated
       language                     varchar(3)      null,      -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
       disable_triggers             boolean  null
);

create index story_sentences_story on story_sentences (stories_id, sentence_number);
create index story_sentences_publish_day on story_sentences( date_trunc( 'day', publish_date ), media_id );
create index story_sentences_language on story_sentences(language);
create index story_sentences_media_id    on story_sentences( media_id );
create index story_sentences_db_row_last_updated    on story_sentences( db_row_last_updated );

ALTER TABLE story_sentences
    ADD CONSTRAINT story_sentences_media_id_fkey
        FOREIGN KEY (media_id) REFERENCES media(media_id) ON DELETE CASCADE;

ALTER TABLE story_sentences
    ADD CONSTRAINT story_sentences_stories_id_fkey
        FOREIGN KEY (stories_id) REFERENCES stories(stories_id) ON DELETE CASCADE;

DROP TRIGGER IF EXISTS story_sentences_last_updated_trigger on story_sentences CASCADE;

CREATE TRIGGER story_sentences_last_updated_trigger
    BEFORE INSERT OR UPDATE ON story_sentences
    FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger() ;


-- update media stats table for new story sentence.
create function insert_ss_media_stats() returns trigger as $$
begin


    IF NOT story_triggers_enabled() THEN
      RETURN NULL;
    END IF;

    update media_stats set num_sentences = num_sentences + 1
        where media_id = NEW.media_id and stat_date = date_trunc( 'day', NEW.publish_date );

    return NEW;
END;
$$ LANGUAGE plpgsql;
create trigger ss_insert_story_media_stats after insert
    on story_sentences for each row execute procedure insert_ss_media_stats();

-- update media stats table for updated story_sentence date
create function update_ss_media_stats() returns trigger as $$
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
create trigger ss_update_story_media_stats after update
    on story_sentences for each row execute procedure update_ss_media_stats();

-- update media stats table for deleted story sentence
create function delete_ss_media_stats() returns trigger as $$
begin

    IF NOT story_triggers_enabled() THEN
       RETURN NULL;
    END IF;

    update media_stats set num_sentences = num_sentences - 1
    where media_id = OLD.media_id and stat_date = date_trunc( 'day', OLD.publish_date );

    return NEW;
END;
$$ LANGUAGE plpgsql;
create trigger story_delete_ss_media_stats after delete
    on story_sentences for each row execute procedure delete_ss_media_stats();

-- update media stats table for new story. create the media / day row if needed.
create or replace function insert_story_media_stats() returns trigger as $insert_story_media_stats$
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
create trigger stories_insert_story_media_stats after insert
    on stories for each row execute procedure insert_story_media_stats();


-- update media stats and story_sentences tables for updated story date
create function update_story_media_stats() returns trigger as $update_story_media_stats$
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
create trigger stories_update_story_media_stats after update
    on stories for each row execute procedure update_story_media_stats();


-- update media stats table for deleted story
create function delete_story_media_stats() returns trigger as $delete_story_media_stats$
begin

    IF NOT story_triggers_enabled() THEN
       RETURN NULL;
    END IF;

    update media_stats set num_stories = num_stories - 1
    where media_id = OLD.media_id and stat_date = date_trunc( 'day', OLD.publish_date );

    return NEW;
END;
$delete_story_media_stats$ LANGUAGE plpgsql;
create trigger story_delete_story_media_stats after delete
    on stories for each row execute procedure delete_story_media_stats();

create table story_sentences_tags_map
(
    story_sentences_tags_map_id     bigserial  primary key,
    story_sentences_id              bigint     not null references story_sentences on delete cascade,
    tags_id                 int     not null references tags on delete cascade,
    db_row_last_updated                timestamp with time zone not null default now()
);

DROP TRIGGER IF EXISTS story_sentences_tags_map_last_updated_trigger on story_sentences_tags_map CASCADE;

CREATE TRIGGER story_sentences_tags_map_last_updated_trigger
    BEFORE INSERT OR UPDATE ON story_sentences_tags_map
    FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger() ;

DROP TRIGGER IF EXISTS story_sentences_tags_map_update_story_sentences_last_updated_trigger on story_sentences_tags_map;

CREATE TRIGGER story_sentences_tags_map_update_story_sentences_last_updated_trigger
    AFTER INSERT OR UPDATE OR DELETE ON story_sentences_tags_map FOR EACH ROW
    EXECUTE PROCEDURE update_story_sentences_updated_time_by_story_sentences_id_trigger();

CREATE index story_sentences_tags_map_db_row_last_updated on story_sentences_tags_map ( db_row_last_updated );
create unique index story_sentences_tags_map_story on story_sentences_tags_map (story_sentences_id, tags_id);
create index story_sentences_tags_map_tag on story_sentences_tags_map (tags_id);
CREATE INDEX story_sentences_tags_map_story_id ON story_sentences_tags_map USING btree (story_sentences_id);

create table story_sentence_counts (
       story_sentence_counts_id     bigserial       primary key,
       sentence_md5                 varchar(64)     not null,
       media_id                     int             not null, -- references media,
       publish_week                 timestamp       not null,
       sentence_count               int             not null,
       first_stories_id             int             not null,
       first_sentence_number        int             not null
);

-- We have chossen not to make the 'story_sentence_counts_md5' index unique purely for performance reasons.
-- Duplicate rows within this index are not desirable but are relatively rare in practice.
-- Thus we have decided to avoid the performance and code complexity implications of a unique index
-- See Issue 1599
create index story_sentence_counts_md5 on story_sentence_counts( media_id, publish_week, sentence_md5 );

create index story_sentence_counts_first_stories_id on story_sentence_counts( first_stories_id );

create table solr_imports (
    solr_imports_id     serial primary key,
    import_date         timestamp not null,
    full_import         boolean not null default false,
    num_stories         bigint
);

create table solr_import_stories (
    stories_id          int not null references stories on delete cascade
);

create index solr_import_stories_story on solr_import_stories ( stories_id );

create index solr_imports_date on solr_imports ( import_date );

create view story_extracted_texts as select stories_id, array_to_string(array_agg(download_text), ' ') as extracted_text
       from (select * from downloads natural join download_texts order by downloads_id) as downloads group by stories_id;



CREATE VIEW media_feed_counts as (SELECT media_id, count(*) as feed_count FROM feeds GROUP by media_id);

create table controversies (
    controversies_id        serial primary key,
    name                    varchar(1024) not null,
    pattern                 text not null,
    solr_seed_query         text not null,
    solr_seed_query_run     boolean not null default false,
    description             text not null,
    controversy_tag_sets_id int not null references tag_sets,
    media_type_tag_sets_id  int references tag_sets,
    process_with_bitly      boolean not null default false,
    max_iterations          int not null default 15
);

COMMENT ON COLUMN controversies.process_with_bitly
    IS 'Enable processing controversy''s stories with Bit.ly; enqueue all new controversy stories for Bit.ly processing';

create unique index controversies_name on controversies( name );
create unique index controversies_tag_set on controversies( controversy_tag_sets_id );
create unique index controversies_media_type_tag_set on controversies( media_type_tag_sets_id );

create function insert_controversy_tag_set() returns trigger as $insert_controversy_tag_set$
    begin
        insert into tag_sets ( name, label, description )
            select 'controversy_'||NEW.name, NEW.name||' controversy', 'Tag set for stories within the '||NEW.name||' controversy.';

        select tag_sets_id into NEW.controversy_tag_sets_id from tag_sets where name = 'controversy_'||NEW.name;

        return NEW;
    END;
$insert_controversy_tag_set$ LANGUAGE plpgsql;

create trigger controversy_tag_set before insert on controversies
    for each row execute procedure insert_controversy_tag_set();

create table controversy_dates (
    controversy_dates_id    serial primary key,
    controversies_id        int not null references controversies on delete cascade,
    start_date              date not null,
    end_date                date not null,
    boundary                boolean not null default 'false'
);

create view controversies_with_dates as
    select c.*,
            to_char( cd.start_date, 'YYYY-MM-DD' ) start_date,
            to_char( cd.end_date, 'YYYY-MM-DD' ) end_date
        from
            controversies c
            join controversy_dates cd on ( c.controversies_id = cd.controversies_id )
        where
            cd.boundary;

create table controversy_dump_tags (
    controversy_dump_tags_id    serial primary key,
    controversies_id            int not null references controversies on delete cascade,
    tags_id                     int not null references tags
);

create table controversy_media_codes (
    controversies_id        int not null references controversies on delete cascade,
    media_id                int not null references media on delete cascade,
    code_type               text,
    code                    text
);

create table controversy_merged_stories_map (
    source_stories_id       int not null references stories on delete cascade,
    target_stories_id       int not null references stories on delete cascade
);

create index controversy_merged_stories_map_source on controversy_merged_stories_map ( source_stories_id );
create index controversy_merged_stories_map_story on controversy_merged_stories_map ( target_stories_id );

create table controversy_stories (
    controversy_stories_id          serial primary key,
    controversies_id                int not null references controversies on delete cascade,
    stories_id                      int not null references stories on delete cascade,
    link_mined                      boolean default 'f',
    iteration                       int default 0,
    link_weight                     real,
    redirect_url                    text,
    valid_foreign_rss_story         boolean default false
);

create unique index controversy_stories_sc on controversy_stories ( stories_id, controversies_id );

-- no foreign key constraints on controversies_id and stories_id because
--   we have the combined foreign key constraint pointing to controversy_stories
--   below
create table controversy_links (
    controversy_links_id        serial primary key,
    controversies_id            int not null,
    stories_id                  int not null,
    url                         text not null,
    redirect_url                text,
    ref_stories_id              int references stories on delete cascade,
    link_spidered               boolean default 'f'
);

alter table controversy_links add constraint controversy_links_controversy_story_stories_id
    foreign key ( stories_id, controversies_id ) references controversy_stories ( stories_id, controversies_id )
    on delete cascade;

create unique index controversy_links_scr on controversy_links ( stories_id, controversies_id, ref_stories_id );
create index controversy_links_controversy on controversy_links ( controversies_id );
create index controversy_links_ref_story on controversy_links ( ref_stories_id );

CREATE VIEW controversy_links_cross_media AS
    SELECT s.stories_id,
           sm.name AS media_name,
           r.stories_id AS ref_stories_id,
           rm.name AS ref_media_name,
           cl.url AS url,
           cs.controversies_id,
           cl.controversy_links_id
    FROM media sm,
         media rm,
         controversy_links cl,
         stories s,
         stories r,
         controversy_stories cs
    WHERE cl.ref_stories_id != cl.stories_id
      AND s.stories_id = cl.stories_id
      AND cl.ref_stories_id = r.stories_id
      AND s.media_id != r.media_id
      AND sm.media_id = s.media_id
      AND rm.media_id = r.media_id
      AND cs.stories_id = cl.ref_stories_id
      AND cs.controversies_id = cl.controversies_id;

create table controversy_seed_urls (
    controversy_seed_urls_id        serial primary key,
    controversies_id                int not null references controversies on delete cascade,
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

create index controversy_seed_urls_controversy on controversy_seed_urls( controversies_id );
create index controversy_seed_urls_url on controversy_seed_urls( url );
create index controversy_seed_urls_story on controversy_seed_urls ( stories_id );

create table controversy_ignore_redirects (
    controversy_ignore_redirects_id     serial primary key,
    url                                 varchar( 1024 )
);

create index controversy_ignore_redirects_url on controversy_ignore_redirects ( url );

create table controversy_query_slices (
    controversy_query_slices_id     serial primary key,
    controversies_id                int not null references controversies on delete cascade,
    name                            varchar ( 1024 ) not null,
    query                           text not null,
    all_time_slices                 boolean not null
);

create index controversy_query_slices_controversy on controversy_query_slices ( controversies_id );

create table controversy_dumps (
    controversy_dumps_id            serial primary key,
    controversies_id                int not null references controversies on delete cascade,
    dump_date                       timestamp not null,
    start_date                      timestamp not null,
    end_date                        timestamp not null,
    note                            text
);

create index controversy_dumps_controversy on controversy_dumps ( controversies_id );

create type cd_period_type AS ENUM ( 'overall', 'weekly', 'monthly', 'custom' );

-- individual time slices within a controversy dump
create table controversy_dump_time_slices (
    controversy_dump_time_slices_id serial primary key,
    controversy_dumps_id            int not null references controversy_dumps on delete cascade,
    controversy_query_slices_id     int null references controversy_query_slices on delete set null,
    start_date                      timestamp not null,
    end_date                        timestamp not null,
    period                          cd_period_type not null,
    model_r2_mean                   float,
    model_r2_stddev                 float,
    model_num_media                 int,
    story_count                     int not null,
    story_link_count                int not null,
    medium_count                    int not null,
    medium_link_count               int not null,

    -- is this just a shell cdts with no data actually dumped into it
    -- we use shell cdtss to display query slices on live data with having to make a real dump
    -- first
    is_shell                        boolean not null default false,
    tags_id                         int references tags -- keep on cascade to avoid accidental deletion
);

create index controversy_dump_time_slices_dump on controversy_dump_time_slices ( controversy_dumps_id );

create table cdts_files (
    cdts_files_id                   serial primary key,
    controversy_dump_time_slices_id int not null references controversy_dump_time_slices on delete cascade,
    file_name                       text,
    file_content                    text
);

create index cdts_files_cdts on cdts_files ( controversy_dump_time_slices_id );

create table cd_files (
    cd_files_id                     serial primary key,
    controversy_dumps_id            int not null references controversy_dumps on delete cascade,
    file_name                       text,
    file_content                    text
);

create index cd_files_cd on cd_files ( controversy_dumps_id );

-- schema to hold the various controversy dump snapshot tables
create schema cd;

-- create a table for each of these tables to hold a snapshot of stories relevant
-- to a controversy for each dump for that controversy
create table cd.stories (
    controversy_dumps_id        int             not null references controversy_dumps on delete cascade,
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
create index stories_id on cd.stories ( controversy_dumps_id, stories_id );

-- stats for various externally dervied statistics about a story.  keeping this separate for now
-- from the bitly stats for simplicity sake during implementatino and testing
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


--
-- Bit.ly total story click counts
--

-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE bitly_clicks_total (
    bitly_clicks_id   BIGSERIAL NOT NULL,
    stories_id        INT       NOT NULL,

    -- Date when click data was collected (usually 3 days or 30 days since stories.publish_date)
    -- (NULL for Bit.ly click data that was collected for controversies)
    collect_date      DATE      NULL,

    -- Total click count that was aggregated at "collect_date"
    click_count       INT       NOT NULL
);

-- Automatic Bit.ly total click count partitioning to stories_id chunks of 1m rows
CREATE OR REPLACE FUNCTION bitly_clicks_total_partition_by_stories_id_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_total_000001")
    target_table_owner TEXT;      -- partition table owner (e.g. "mediaclouduser")

    chunk_size CONSTANT INT := 1000000;           -- 1m stories in a chunk
    to_char_format CONSTANT TEXT := '000000';     -- Up to 1m of chunks, suffixed as "_000001", ..., "_999999"

    stories_id_chunk_number INT;  -- millions part of stories_id (e.g. 30 for stories_id = 30,000,000)
    stories_id_start INT;         -- stories_id chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_end INT;           -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
BEGIN

    SELECT NEW.stories_id / chunk_size INTO stories_id_chunk_number;
    SELECT 'bitly_clicks_total_' || trim(leading ' ' from to_char(stories_id_chunk_number, to_char_format))
        INTO target_table_name;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables 
        WHERE table_schema = current_schema()
          AND table_name = target_table_name
    ) THEN

        SELECT (NEW.stories_id / chunk_size) * chunk_size INTO stories_id_start;
        SELECT ((NEW.stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

        EXECUTE '
            CREATE TABLE ' || target_table_name || ' (

                -- Primary key
                CONSTRAINT ' || target_table_name || '_pkey
                    PRIMARY KEY (bitly_clicks_id),

                -- Partition by stories_id
                CONSTRAINT ' || target_table_name || '_stories_id CHECK (
                    stories_id >= ''' || stories_id_start || '''
                AND stories_id <  ''' || stories_id_end   || '''),

                -- Foreign key to stories.stories_id
                CONSTRAINT ' || target_table_name || '_stories_id_fkey
                    FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL

            ) INHERITS (bitly_clicks_total);
        ';

        EXECUTE '
            CREATE UNIQUE INDEX ' || target_table_name || '_stories_id
            ON ' || target_table_name || ' (stories_id);
        ';

        -- Update owner
        SELECT u.usename AS owner
        FROM information_schema.tables AS t
            JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
            JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
        WHERE t.table_name = 'bitly_clicks_total'
          AND t.table_schema = 'public'
        INTO target_table_owner;

        EXECUTE 'ALTER TABLE ' || target_table_name || ' OWNER TO ' || target_table_owner || ';';

    END IF;

    EXECUTE '
        INSERT INTO ' || target_table_name || ' (stories_id, collect_date, click_count)
        VALUES ($1, $2, $3);
    ' USING NEW.stories_id, NEW.collect_date, NEW.click_count;

    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER bitly_clicks_total_partition_by_stories_id_insert_trigger
    BEFORE INSERT ON bitly_clicks_total
    FOR EACH ROW EXECUTE PROCEDURE bitly_clicks_total_partition_by_stories_id_insert_trigger();


-- Helper to INSERT / UPDATE story's Bit.ly statistics
CREATE OR REPLACE FUNCTION upsert_bitly_clicks_total (
    param_stories_id INT,
    param_collect_date DATE,
    param_click_count INT
) RETURNS VOID AS
$$
BEGIN
    LOOP
        -- Try UPDATing
        UPDATE bitly_clicks_total
            SET click_count = param_click_count,
                collect_date = param_collect_date
            WHERE stories_id = param_stories_id;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO bitly_clicks_total (stories_id, collect_date, click_count)
            VALUES (param_stories_id, param_collect_date, param_click_count);
            RETURN;
        EXCEPTION WHEN UNIQUE_VIOLATION THEN
            -- If someone else INSERTs the same key concurrently,
            -- we will get a unique-key failure. In that case, do
            -- nothing and loop to try the UPDATE again.
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;


--
-- Bit.ly daily story click counts
--

-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE bitly_clicks_daily (
    bitly_clicks_id   BIGSERIAL NOT NULL,
    stories_id        INT       NOT NULL,

    -- Day
    day               DATE      NOT NULL,

    -- Click count for that day
    click_count       INT       NOT NULL
);

-- Automatic Bit.ly daily click count partitioning to stories_id chunks of 1m rows
CREATE OR REPLACE FUNCTION bitly_clicks_daily_partition_by_stories_id_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_daily_000001")
    target_table_owner TEXT;      -- partition table owner (e.g. "mediaclouduser")

    chunk_size CONSTANT INT := 1000000;           -- 1m stories in a chunk
    to_char_format CONSTANT TEXT := '000000';     -- Up to 1m of chunks, suffixed as "_000001", ..., "_999999"

    stories_id_chunk_number INT;  -- millions part of stories_id (e.g. 30 for stories_id = 30,000,000)
    stories_id_start INT;         -- stories_id chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_end INT;           -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
BEGIN

    SELECT NEW.stories_id / chunk_size INTO stories_id_chunk_number;
    SELECT 'bitly_clicks_daily_' || trim(leading ' ' from to_char(stories_id_chunk_number, to_char_format))
        INTO target_table_name;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables 
        WHERE table_schema = current_schema()
          AND table_name = target_table_name
    ) THEN

        SELECT (NEW.stories_id / chunk_size) * chunk_size INTO stories_id_start;
        SELECT ((NEW.stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

        EXECUTE '
            CREATE TABLE ' || target_table_name || ' (

                -- Primary key
                CONSTRAINT ' || target_table_name || '_pkey
                    PRIMARY KEY (bitly_clicks_id),

                -- Partition by stories_id
                CONSTRAINT ' || target_table_name || '_stories_id CHECK (
                    stories_id >= ''' || stories_id_start || '''
                AND stories_id <  ''' || stories_id_end   || '''),

                -- Foreign key to stories.stories_id
                CONSTRAINT ' || target_table_name || '_stories_id_fkey
                    FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL

            ) INHERITS (bitly_clicks_daily);
        ';

        EXECUTE '
            CREATE INDEX ' || target_table_name || '_stories_id
            ON ' || target_table_name || ' (stories_id);
        ';

        -- To ensure uniqueness
        EXECUTE '
            CREATE UNIQUE INDEX ' || target_table_name || '_stories_id_day
            ON ' || target_table_name || ' (stories_id, day);
        ';

        -- Update owner
        SELECT u.usename AS owner
        FROM information_schema.tables AS t
            JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
            JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
        WHERE t.table_name = 'bitly_clicks_daily'
          AND t.table_schema = 'public'
        INTO target_table_owner;

        EXECUTE 'ALTER TABLE ' || target_table_name || ' OWNER TO ' || target_table_owner || ';';

    END IF;

    EXECUTE '
        INSERT INTO ' || target_table_name || ' (stories_id, day, click_count)
        VALUES ($1, $2, $3);
    ' USING NEW.stories_id, NEW.day, NEW.click_count;

    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER bitly_clicks_daily_partition_by_stories_id_insert_trigger
    BEFORE INSERT ON bitly_clicks_daily
    FOR EACH ROW EXECUTE PROCEDURE bitly_clicks_daily_partition_by_stories_id_insert_trigger();


-- Helper to INSERT / UPDATE story's Bit.ly statistics
CREATE OR REPLACE FUNCTION upsert_bitly_clicks_daily (
    param_stories_id INT,
    param_day DATE,
    param_click_count INT
) RETURNS VOID AS
$$
BEGIN
    LOOP
        -- Try UPDATing
        UPDATE bitly_clicks_daily
            SET click_count = param_click_count
            WHERE stories_id = param_stories_id
              AND day = param_day;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO bitly_clicks_daily (stories_id, day, click_count)
            VALUES (param_stories_id, param_day, param_click_count);
            RETURN;
        EXCEPTION WHEN UNIQUE_VIOLATION THEN
            -- If someone else INSERTs the same key concurrently,
            -- we will get a unique-key failure. In that case, do
            -- nothing and loop to try the UPDATE again.
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;


-- Helper to return a number of stories for which we don't have Bit.ly statistics yet
CREATE FUNCTION num_controversy_stories_without_bitly_statistics (param_controversies_id INT) RETURNS INT AS
$$
DECLARE
    controversy_exists BOOL;
    num_stories_without_bitly_statistics INT;
BEGIN

    SELECT 1 INTO controversy_exists
    FROM controversies
    WHERE controversies_id = param_controversies_id
      AND process_with_bitly = 't';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Controversy % does not exist or is not set up for Bit.ly processing.', param_controversies_id;
        RETURN FALSE;
    END IF;

    SELECT COUNT(stories_id) INTO num_stories_without_bitly_statistics
    FROM controversy_stories
    WHERE controversies_id = param_controversies_id
      AND stories_id NOT IN (
        SELECT stories_id
        FROM bitly_clicks_total
    )
    GROUP BY controversies_id;
    IF NOT FOUND THEN
        num_stories_without_bitly_statistics := 0;
    END IF;

    RETURN num_stories_without_bitly_statistics;
END;
$$
LANGUAGE plpgsql;


create table cd.controversy_stories (
    controversy_dumps_id            int not null references controversy_dumps on delete cascade,
    controversy_stories_id          int,
    controversies_id                int not null,
    stories_id                      int not null,
    link_mined                      boolean,
    iteration                       int,
    link_weight                     real,
    redirect_url                    text,
    valid_foreign_rss_story         boolean
);
create index controversy_stories_id on cd.controversy_stories ( controversy_dumps_id, stories_id );

create table cd.controversy_links_cross_media (
    controversy_dumps_id        int not null references controversy_dumps on delete cascade,
    controversy_links_id        int,
    controversies_id            int not null,
    stories_id                  int not null,
    url                         text not null,
    ref_stories_id              int
);
create index controversy_links_story on cd.controversy_links_cross_media ( controversy_dumps_id, stories_id );
create index controversy_links_ref on cd.controversy_links_cross_media ( controversy_dumps_id, ref_stories_id );

create table cd.controversy_media_codes (
    controversy_dumps_id    int not null references controversy_dumps on delete cascade,
    controversies_id        int not null,
    media_id                int not null,
    code_type               text,
    code                    text
);
create index controversy_media_codes_medium on cd.controversy_media_codes ( controversy_dumps_id, media_id );

create table cd.media (
    controversy_dumps_id    int not null references controversy_dumps on delete cascade,
    media_id                int,
    url                     varchar(1024)   not null,
    name                    varchar(128)    not null,
    moderated               boolean         not null,
    moderation_notes        text            null,
    full_text_rss           boolean,
    extract_author          boolean         default(false),
    sw_data_start_date      date            default(null),
    sw_data_end_date        date            default(null),
    foreign_rss_links       boolean         not null default( false ),
    dup_media_id            int             null,
    is_not_dup              boolean         null,
    use_pager               boolean         null,
    unpaged_stories         int             not null default 0
);
create index media_id on cd.media ( controversy_dumps_id, media_id );

create table cd.media_tags_map (
    controversy_dumps_id    int not null    references controversy_dumps on delete cascade,
    media_tags_map_id       int,
    media_id                int             not null,
    tags_id                 int             not null
);
create index media_tags_map_medium on cd.media_tags_map ( controversy_dumps_id, media_id );
create index media_tags_map_tag on cd.media_tags_map ( controversy_dumps_id, tags_id );

create table cd.stories_tags_map
(
    controversy_dumps_id    int not null    references controversy_dumps on delete cascade,
    stories_tags_map_id     int,
    stories_id              int,
    tags_id                 int
);
create index stories_tags_map_story on cd.stories_tags_map ( controversy_dumps_id, stories_id );
create index stories_tags_map_tag on cd.stories_tags_map ( controversy_dumps_id, tags_id );

create table cd.tags (
    controversy_dumps_id    int not null    references controversy_dumps on delete cascade,
    tags_id                 int,
    tag_sets_id             int,
    tag                     varchar(512),
    label                   text,
    description             text
);
create index tags_id on cd.tags ( controversy_dumps_id, tags_id );

create table cd.tag_sets (
    controversy_dumps_id    int not null    references controversy_dumps on delete cascade,
    tag_sets_id             int,
    name                    varchar(512),
    label                   text,
    description             text
);
create index tag_sets_id on cd.tag_sets ( controversy_dumps_id, tag_sets_id );

-- story -> story links within a cdts
create table cd.story_links (
    controversy_dump_time_slices_id         int not null
                                            references controversy_dump_time_slices on delete cascade,
    source_stories_id                       int not null,
    ref_stories_id                          int not null
);

-- TODO: add complex foreign key to check that *_stories_id exist for the controversy_dump stories snapshot
create index story_links_source on cd.story_links( controversy_dump_time_slices_id, source_stories_id );
create index story_links_ref on cd.story_links( controversy_dump_time_slices_id, ref_stories_id );

-- link counts for stories within a cdts
create table cd.story_link_counts (
    controversy_dump_time_slices_id         int not null
                                            references controversy_dump_time_slices on delete cascade,
    stories_id                              int not null,
    inlink_count                            int not null,
    outlink_count                           int not null,

    -- Bit.ly stats
    -- (values can be NULL if Bit.ly is not enabled / configured for a controversy)
    bitly_click_count                       int null
);

-- TODO: add complex foreign key to check that stories_id exists for the controversy_dump stories snapshot
create index story_link_counts_story on cd.story_link_counts ( controversy_dump_time_slices_id, stories_id );

-- links counts for media within a cdts
create table cd.medium_link_counts (
    controversy_dump_time_slices_id int not null
                                    references controversy_dump_time_slices on delete cascade,
    media_id                        int not null,
    inlink_count                    int not null,
    outlink_count                   int not null,
    story_count                     int not null,

    -- Bit.ly (aggregated) stats
    -- (values can be NULL if Bit.ly is not enabled / configured for a controversy)
    bitly_click_count               int null
);

-- TODO: add complex foreign key to check that media_id exists for the controversy_dump media snapshot
create index medium_link_counts_medium on cd.medium_link_counts ( controversy_dump_time_slices_id, media_id );

create table cd.medium_links (
    controversy_dump_time_slices_id int not null
                                    references controversy_dump_time_slices on delete cascade,
    source_media_id                 int not null,
    ref_media_id                    int not null,
    link_count                      int not null
);

-- TODO: add complex foreign key to check that *_media_id exist for the controversy_dump media snapshot
create index medium_links_source on cd.medium_links( controversy_dump_time_slices_id, source_media_id );
create index medium_links_ref on cd.medium_links( controversy_dump_time_slices_id, ref_media_id );

create table cd.daily_date_counts (
    controversy_dumps_id            int not null references controversy_dumps on delete cascade,
    publish_date                    date not null,
    story_count                     int not null,
    tags_id                         int
);

create index daily_date_counts_date on cd.daily_date_counts( controversy_dumps_id, publish_date );
create index daily_date_counts_tag on cd.daily_date_counts( controversy_dumps_id, tags_id );

create table cd.weekly_date_counts (
    controversy_dumps_id            int not null references controversy_dumps on delete cascade,
    publish_date                    date not null,
    story_count                     int not null,
    tags_id                         int
);

create index weekly_date_counts_date on cd.weekly_date_counts( controversy_dumps_id, publish_date );
create index weekly_date_counts_tag on cd.weekly_date_counts( controversy_dumps_id, tags_id );

-- create a mirror of the stories table with the stories for each controversy.  this is to make
-- it much faster to query the stories associated with a given controversy, rather than querying the
-- contested and bloated stories table.  only inserts and updates on stories are triggered, because
-- deleted cascading stories_id and controversies_id fields take care of deletes.
create table cd.live_stories (
    controversies_id            int             not null references controversies on delete cascade,
    controversy_stories_id      int             not null references controversy_stories on delete cascade,
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
create index live_story_controversy on cd.live_stories ( controversies_id );
create unique index live_stories_story on cd.live_stories ( controversies_id, stories_id );

create table cd.word_counts (
    controversy_dump_time_slices_id int             not null references controversy_dump_time_slices on delete cascade,
    term                            varchar(256)    not null,
    stem                            varchar(256)    not null,
    stem_count                      smallint        not null
);

create index word_counts_cdts_stem on cd.word_counts ( controversy_dump_time_slices_id, stem );

create function insert_live_story() returns trigger as $insert_live_story$
    begin

        insert into cd.live_stories
            ( controversies_id, controversy_stories_id, stories_id, media_id, url, guid, title, description,
                publish_date, collect_date, full_text_rss, language,
                db_row_last_updated )
            select NEW.controversies_id, NEW.controversy_stories_id, NEW.stories_id, s.media_id, s.url, s.guid,
                    s.title, s.description, s.publish_date, s.collect_date, s.full_text_rss, s.language,
                    s.db_row_last_updated
                from controversy_stories cs
                    join stories s on ( cs.stories_id = s.stories_id )
                where
                    cs.stories_id = NEW.stories_id and
                    cs.controversies_id = NEW.controversies_id;

        return NEW;
    END;
$insert_live_story$ LANGUAGE plpgsql;

create trigger controversy_stories_insert_live_story after insert on controversy_stories
    for each row execute procedure insert_live_story();

create function update_live_story() returns trigger as $update_live_story$
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
                db_row_last_updated = NEW.db_row_last_updated
            where
                stories_id = NEW.stories_id;

        return NEW;
    END;
$update_live_story$ LANGUAGE plpgsql;

create trigger stories_update_live_story after update on stories
    for each row execute procedure update_live_story();

create table processed_stories (
    processed_stories_id        bigserial          primary key,
    stories_id                  int             not null references stories on delete cascade,
    disable_triggers            boolean  null
);

create index processed_stories_story on processed_stories ( stories_id );

CREATE TRIGGER processed_stories_update_stories_last_updated_trigger
    AFTER INSERT OR UPDATE OR DELETE ON processed_stories
    FOR EACH ROW EXECUTE PROCEDURE update_stories_updated_time_by_stories_id_trigger();

create table story_subsets (
    story_subsets_id        bigserial          primary key,
    start_date              timestamp with time zone,
    end_date                timestamp with time zone,
    media_id                int references media null,
    media_sets_id           int references media_sets null,
    ready                   boolean default 'false',
    last_processed_stories_id bigint references processed_stories(processed_stories_id)
);

CREATE TABLE story_subsets_processed_stories_map (
   story_subsets_processed_stories_map_id bigserial primary key,
   story_subsets_id bigint NOT NULL references story_subsets on delete cascade,
   processed_stories_id bigint NOT NULL references processed_stories on delete cascade
);

create index story_subsets_processed_stories_map_processed_stories_id on story_subsets_processed_stories_map ( processed_stories_id );

create table controversy_query_story_searches_imported_stories_map (
    controversies_id            int not null references controversies on delete cascade,
    stories_id                  int not null references stories on delete cascade
);

create index cqssism_c on controversy_query_story_searches_imported_stories_map ( controversies_id );
create index cqssism_s on controversy_query_story_searches_imported_stories_map ( stories_id );

CREATE VIEW stories_collected_in_past_day as select * from stories where collect_date > now() - interval '1 day';

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



CREATE TABLE feedless_stories (
        stories_id integer,
        media_id integer
);
CREATE INDEX feedless_stories_story ON feedless_stories USING btree (stories_id);

CREATE TABLE queries_country_counts_json (
   queries_country_counts_json_id serial primary key,
   queries_id integer references queries on delete cascade not null unique,
   country_counts_json text not null
);


CREATE OR REPLACE FUNCTION add_query_version (new_query_version_enum_string character varying) RETURNS void
AS
$body$
DECLARE
    range_of_old_enum TEXT;
    new_type_sql TEXT;
BEGIN

LOCK TABLE queries;

SELECT '''' || array_to_string(ENUM_RANGE(null::query_version_enum), ''',''') || '''' INTO range_of_old_enum;

DROP TYPE IF EXISTS new_query_version_enum;

new_type_sql :=  'CREATE TYPE new_query_version_enum AS ENUM( ' || range_of_old_enum || ', ' || '''' || new_query_version_enum_string || '''' || ')' ;
--RAISE NOTICE 'Sql: %t', new_type_sql;

EXECUTE new_type_sql;

ALTER TABLE queries ADD COLUMN new_query_version new_query_version_enum DEFAULT enum_last (null::new_query_version_enum ) NOT NULL;
UPDATE queries set new_query_version = query_version::text::new_query_version_enum;
ALTER TYPE query_version_enum  RENAME to old_query_version_enum;
ALTER TABLE queries rename column query_version to old_query_version;
ALTER TABLE queries rename column new_query_version to query_version;
ALTER TYPE new_query_version_enum RENAME to query_version_enum;
ALTER TABLE queries DROP COLUMN old_query_version;
DROP TYPE old_query_version_enum ;


END;
$body$
    LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION get_relative_file_path(path text)
    RETURNS text AS
$$
DECLARE
    regex_tar_format text;
    relative_file_path text;
BEGIN
    IF path is null THEN
       RETURN 'na';
    END IF;

    regex_tar_format :=  E'tar\\:\\d*\\:\\d*\\:(mediacloud-content-\\d*\.tar).*';

    IF path ~ regex_tar_format THEN
         relative_file_path =  regexp_replace(path, E'tar\\:\\d*\\:\\d*\\:(mediacloud-content-\\d*\.tar).*', E'\\1') ;
    ELSIF  path like 'content:%' THEN
         relative_file_path =  'inline';
    ELSEIF path like 'content/%' THEN
         relative_file_path =  regexp_replace(path, E'content\\/', E'\/') ;
    ELSE
         relative_file_path = 'error';
    END IF;

--  RAISE NOTICE 'relative file path for %, is %', path, relative_file_path;

    RETURN relative_file_path;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE
  COST 10;

UPDATE downloads set relative_file_path = get_relative_file_path(path) where relative_file_path = 'tbd';

CREATE OR REPLACE FUNCTION download_relative_file_path_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';
      IF TG_OP = 'UPDATE' then
          -- RAISE NOTICE 'UPDATE ';

	  -- The second part is needed because of the way comparisons with null are handled.
	  path_change := ( OLD.path <> NEW.path )  AND (  ( OLD.path is not null) <> (NEW.path is not null) ) ;
	  -- RAISE NOTICE 'test result % ', path_change;

          IF path_change is null THEN
	       -- RAISE NOTICE 'Path change % != %', OLD.path, NEW.path;
               NEW.relative_file_path = get_relative_file_path(NEW.path);

               IF NEW.relative_file_path = 'inline' THEN
		  NEW.file_status = 'inline';
	       END IF;
	  ELSE
               -- RAISE NOTICE 'NO path change % = %', OLD.path, NEW.path;
          END IF;
      ELSIF TG_OP = 'INSERT' then
	  NEW.relative_file_path = get_relative_file_path(NEW.path);

          IF NEW.relative_file_path = 'inline' THEN
	     NEW.file_status = 'inline';
	  END IF;
      END IF;

      RETURN NEW;
   END;
$$
LANGUAGE 'plpgsql';

DROP TRIGGER IF EXISTS download_relative_file_path_trigger on downloads CASCADE;

CREATE TRIGGER download_relative_file_path_trigger
    BEFORE INSERT OR UPDATE ON downloads
    FOR EACH ROW EXECUTE PROCEDURE  download_relative_file_path_trigger() ;

CREATE INDEX relative_file_paths_to_verify
    ON downloads USING btree (relative_file_path)
    WHERE file_status = 'tbd'::download_file_status
      AND relative_file_path <> 'tbd'::text
      AND relative_file_path <> 'error'::text
      AND relative_file_path <> 'na'::text
      AND relative_file_path <> 'inline'::text;

CREATE OR REPLACE FUNCTION show_stat_activity()
 RETURNS SETOF  pg_stat_activity  AS
$$
DECLARE
BEGIN
    RETURN QUERY select * from pg_stat_activity;
    RETURN;
END;
$$
LANGUAGE 'plpgsql'
;

CREATE FUNCTION cat(text, text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
  DECLARE
    t text;
  BEGIN
return coalesce($1) || ' | ' || coalesce($2);
  END;
$_$;

CREATE OR REPLACE FUNCTION cancel_pg_process(cancel_pid integer) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
return pg_cancel_backend(cancel_pid);
END;
$$;


--
-- Authentication
--

-- Generate random API token
CREATE FUNCTION generate_api_token() RETURNS VARCHAR(64) LANGUAGE plpgsql AS $$
DECLARE
    token VARCHAR(64);
BEGIN
    SELECT encode(digest(gen_random_bytes(256), 'sha256'), 'hex') INTO token;
    RETURN token;
END;
$$;

-- List of users
CREATE TABLE auth_users (
    auth_users_id   SERIAL  PRIMARY KEY,
    email           TEXT    UNIQUE NOT NULL,

    -- Salted hash of a password (with Crypt::SaltedHash, algorithm => 'SHA-256', salt_len=>64)
    password_hash   TEXT    NOT NULL CONSTRAINT password_hash_sha256 CHECK(LENGTH(password_hash) = 137),

    -- API authentication token
    -- (must be 64 bytes in order to prevent someone from resetting it to empty string somehow)
    api_token       VARCHAR(64)     UNIQUE NOT NULL DEFAULT generate_api_token()
        CONSTRAINT api_token_64_characters
            CHECK(LENGTH(api_token) = 64),

    full_name       TEXT    NOT NULL,
    notes           TEXT    NULL,

    non_public_api  BOOLEAN NOT NULL DEFAULT false,
    active          BOOLEAN NOT NULL DEFAULT true,

    -- Salted hash of a password reset token (with Crypt::SaltedHash, algorithm => 'SHA-256',
    -- salt_len=>64) or NULL
    password_reset_token_hash TEXT  UNIQUE NULL
        CONSTRAINT password_reset_token_hash_sha256
            CHECK(LENGTH(password_reset_token_hash) = 137 OR password_reset_token_hash IS NULL),

    -- Timestamp of the last unsuccessful attempt to log in; used for delaying successive
    -- attempts in order to prevent brute-force attacks
    last_unsuccessful_login_attempt     TIMESTAMP NOT NULL DEFAULT TIMESTAMP 'epoch',

    created_date                        timestamp not null default now()

);

create index auth_users_email on auth_users( email );
create index auth_users_token on auth_users( api_token );

create table auth_registration_queue (
    auth_registration_queue_id  serial  primary key,
    name                        text    not null,
    email                       text    not null,
    organization                text    not null,
    motivation                  text    not null,
    approved                    boolean default false
);


create table auth_user_ip_tokens (
    auth_user_ip_tokens_id  serial      primary key,
    auth_users_id           int         not null references auth_users on delete cascade,
    api_token               varchar(64) unique not null default generate_api_token()
        constraint api_token_64_characters
            check( length( api_token ) = 64 ),
    ip_address              inet    not null
);

create index auth_user_ip_tokens_token on auth_user_ip_tokens ( api_token, ip_address );

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

-- Roles
INSERT INTO auth_roles (role, description) VALUES
    ('admin', 'Do everything, including editing users.'),
    ('admin-readonly', 'Read access to admin interface.'),
    ('query-create', 'Create query; includes ability to create clusters, maps, etc. under clusters.'),
    ('media-edit', 'Add / edit media; includes feeds.'),
    ('stories-edit', 'Add / edit stories.'),
    ('cm', 'Controversy mapper; includes media and story editing'),
    ('cm-readonly', 'Controversy mapper; excludes media and story editing'),
    ('stories-api', 'Access to the stories api'),
    ('search', 'Access to the /search pages');

--
-- User requests (the ones that are configured to be logged)
--
CREATE TABLE auth_user_requests (

    auth_user_requests_id   SERIAL          PRIMARY KEY,

    -- User's email (does *not* reference auth_users.email because the user
    -- might be deleted)
    email                   TEXT            NOT NULL,

    -- Request path (e.g. "api/v2/stories/list")
    request_path            TEXT            NOT NULL,

    -- When did the request happen?
    request_timestamp       TIMESTAMP       NOT NULL DEFAULT LOCALTIMESTAMP,

    -- Number of "items" requested in a request
    -- For example:
    -- * a single request to "/api/v2/stories/list" would count as one item;
    -- * a single request to "/search" would count as a single request plus the
    --   number of stories if "csv=1" is specified, or just as a single request
    --   if "csv=1" is not specified
    requested_items_count   INTEGER         NOT NULL DEFAULT 1

);

CREATE INDEX auth_user_requests_email ON auth_user_requests (email);
CREATE INDEX auth_user_requests_request_path ON auth_user_requests (request_path);


--
-- User request daily counts
--
CREATE TABLE auth_user_request_daily_counts (

    auth_user_request_daily_counts_id  SERIAL  PRIMARY KEY,

    -- User's email (does *not* reference auth_users.email because the user
    -- might be deleted)
    email                   TEXT    NOT NULL,

    -- Day (request timestamp, date_truncated to a day)
    day                     DATE    NOT NULL,

    -- Number of requests
    requests_count          INTEGER NOT NULL,

    -- Number of requested items
    requested_items_count   INTEGER NOT NULL

);

CREATE INDEX auth_user_request_daily_counts_email ON auth_user_request_daily_counts (email);
CREATE INDEX auth_user_request_daily_counts_day ON auth_user_request_daily_counts (day);


-- On each logged request, update "auth_user_request_daily_counts" table
CREATE OR REPLACE FUNCTION auth_user_requests_update_daily_counts() RETURNS trigger AS
$$

DECLARE
    request_date DATE;

BEGIN

    -- Try to prevent deadlocks
    LOCK TABLE auth_user_request_daily_counts IN SHARE ROW EXCLUSIVE MODE;

    request_date := DATE_TRUNC('day', NEW.request_timestamp)::DATE;

    WITH upsert AS (
        -- Try to UPDATE a previously INSERTed day
        UPDATE auth_user_request_daily_counts
        SET requests_count = requests_count + 1,
            requested_items_count = requested_items_count + NEW.requested_items_count
        WHERE email = NEW.email
          AND day = request_date
        RETURNING *
    )
    INSERT INTO auth_user_request_daily_counts (email, day, requests_count, requested_items_count)
        SELECT NEW.email, request_date, 1, NEW.requested_items_count
        WHERE NOT EXISTS (
            SELECT *
            FROM upsert
        );

    RETURN NULL;

END;
$$
LANGUAGE 'plpgsql';


CREATE TRIGGER auth_user_requests_update_daily_counts
    AFTER INSERT ON auth_user_requests
    FOR EACH ROW EXECUTE PROCEDURE auth_user_requests_update_daily_counts();

-- User limits for logged + throttled controller actions
CREATE TABLE auth_user_limits (

    auth_user_limits_id             SERIAL      NOT NULL,

    auth_users_id                   INTEGER     NOT NULL UNIQUE REFERENCES auth_users(auth_users_id)
                                                ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE,

    -- Request limit (0 or belonging to 'admin' / 'admin-readonly' group = no
    -- limit)
    weekly_requests_limit           INTEGER     NOT NULL DEFAULT 1000,

    -- Requested items (stories) limit (0 or belonging to 'admin' /
    -- 'admin-readonly' group = no limit)
    weekly_requested_items_limit    INTEGER     NOT NULL DEFAULT 20000

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
CREATE OR REPLACE FUNCTION auth_user_limits_weekly_usage(user_email TEXT)
RETURNS TABLE(email TEXT, weekly_requests_sum BIGINT, weekly_requested_items_sum BIGINT) AS
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

    -- Activity's name (e.g. "media_edit", "story_edit", etc.)
    name                VARCHAR(255)    NOT NULL
                                        CONSTRAINT activities_name_can_not_contain_spaces CHECK(name NOT LIKE '% %'),

    -- When did the activity happen
    creation_date       TIMESTAMP       NOT NULL DEFAULT LOCALTIMESTAMP,

    -- User that executed the activity, either:
    --     * user's email from "auth_users.email" (e.g. "lvaliukas@cyber.law.harvard.edu", or
    --     * username that initiated the action (e.g. "system:lvaliukas")
    -- (store user's email instead of ID in case the user gets deleted)
    user_identifier     VARCHAR(255)    NOT NULL,

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


--
-- Gearman job queue (jobs enqueued with enqueue_on_gearman())
--

CREATE TYPE gearman_job_queue_status AS ENUM (
    'enqueued',     -- Job is enqueued and waiting to be run
    'running',      -- Job is currently running
    'finished',     -- Job has finished successfully
    'failed'        -- Job has failed
);

CREATE TABLE gearman_job_queue (
    gearman_job_queue_id    SERIAL                      PRIMARY KEY,

    -- Last status update time
    last_modified           TIMESTAMP                   NOT NULL DEFAULT LOCALTIMESTAMP,

    -- Gearman function name (e.g. "MediaWords::GearmanFunction::CM::DumpControversy")
    function_name           VARCHAR(255)                NOT NULL,

    -- Gearman job handle (e.g. "H:tundra.local:8")
    --
    -- This table expects all job handles to be unique, and Gearman would not
    -- generate unique job handles if it is configured to store the job queue
    -- in memory (as it does by default), so you *must* configure a persistent
    -- queue storage.
    --
    -- For an instruction on how to store the Gearman job queue on PostgreSQL,
    -- see doc/README.gearman.markdown.
    job_handle              VARCHAR(255)                UNIQUE NOT NULL,

    -- Unique Gearman job identifier that describes the job that is being run.
    --
    -- In the Gearman::JobScheduler's case, this is a SHA256 of the serialized
    -- Gearman function name and its parameters, e.g.
    --
    --     sha256_hex("MediaWords::GearmanFunction::CM::DumpControversy({controversies_id => 1})")
    --     =
    --     "b9758abbd3811b0aaa53d0e97e188fcac54f58a876bb409b7395621411401ee8"
    --
    -- Although "job_handle" above also serves as an unique identifier of the
    -- specific job, and Gearman uses both at the same time to identify a job,
    -- it provides no way to fetch the "unique job ID" (e.g. this SHA256 string)
    -- by having a Gearman job handle (e.g. "H:tundra.local:8") and vice versa,
    -- so we have to store it somewhere ourselves.
    --
    -- The "unique job ID" is needed to check if the job with specific
    -- parameters (e.g. a "dump controversy" job for the controversy ID) is
    -- enqueued / running / failed.
    --
    -- The unique job ID's length is limited to Gearman internal
    -- GEARMAN_MAX_UNIQUE_SIZE which is set to 64 at the time of writing.
    unique_job_id           VARCHAR(64)                 NOT NULL,

    -- Job status
    status                  gearman_job_queue_status    NOT NULL,

    -- Error message (if any)
    error_message           TEXT                        NULL
);

CREATE INDEX gearman_job_queue_function_name ON gearman_job_queue (function_name);
CREATE UNIQUE INDEX gearman_job_queue_job_handle ON gearman_job_queue (job_handle);
CREATE INDEX gearman_job_queue_unique_job_id ON gearman_job_queue (unique_job_id);
CREATE INDEX gearman_job_queue_status ON gearman_job_queue (status);

-- Update "last_modified" on UPDATEs
CREATE FUNCTION gearman_job_queue_sync_lastmod() RETURNS trigger AS $$
BEGIN
    NEW.last_modified := NOW();
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER gearman_job_queue_sync_lastmod
    BEFORE UPDATE ON gearman_job_queue
    FOR EACH ROW EXECUTE PROCEDURE gearman_job_queue_sync_lastmod();


-- Extra stories to be annotated with CoreNLP that don't have "media.annotate_with_corenlp = 't'"
CREATE TABLE extra_corenlp_stories (
    extra_corenlp_stories_id  SERIAL  PRIMARY KEY,
    stories_id                INTEGER NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE
);
CREATE INDEX extra_corenlp_stories_stories_id ON extra_corenlp_stories (stories_id);

--
-- Returns true if the story can + should be annotated with CoreNLP
--
CREATE OR REPLACE FUNCTION story_is_annotatable_with_corenlp(corenlp_stories_id INT) RETURNS boolean AS $$
BEGIN

    -- FIXME this function is not really optimized for performance

    -- Check "media.annotate_with_corenlp" and "extra_corenlp_stories"
    IF NOT EXISTS (

        SELECT 1
        FROM stories
            INNER JOIN media ON stories.media_id = media.media_id
        WHERE stories.stories_id = corenlp_stories_id
          AND media.annotate_with_corenlp = 't'

    ) AND NOT EXISTS (

        SELECT 1
        FROM extra_corenlp_stories
        WHERE extra_corenlp_stories.stories_id = corenlp_stories_id

    ) THEN
        RAISE NOTICE 'Story % is not annotatable with CoreNLP because it is not enabled for annotation.', corenlp_stories_id;
        RETURN FALSE;

    -- Check if the story is extracted
    ELSEIF EXISTS (

        SELECT 1
        FROM downloads
        WHERE stories_id = corenlp_stories_id
          AND type = 'content'
          AND extracted = 'f'

    ) THEN
        RAISE NOTICE 'Story % is not annotatable with CoreNLP because it is not extracted.', corenlp_stories_id;
        RETURN FALSE;

    -- Annotate English language stories only because they're the only ones
    -- supported by CoreNLP at the time.
    ELSEIF NOT EXISTS (

        SELECT 1
        FROM stories
        WHERE stories_id = corenlp_stories_id

        -- Stories with language field set to NULL are the ones fetched before
        -- introduction of the multilanguage support, so they are assumed to be
        -- English.
          AND ( stories.language = 'en' OR stories.language IS NULL )

    ) THEN
        RAISE NOTICE 'Story % is not annotatable with CoreNLP because it is not in English.', corenlp_stories_id;
        RETURN FALSE;

    -- Check if story has sentences
    ELSEIF NOT EXISTS (

        SELECT 1
        FROM story_sentences
        WHERE stories_id = corenlp_stories_id

    ) THEN
        RAISE NOTICE 'Story % is not annotatable with CoreNLP because it has no sentences.', corenlp_stories_id;
        RETURN FALSE;

    -- Things are fine
    ELSE
        RETURN TRUE;

    END IF;

END;
$$
LANGUAGE 'plpgsql';


--
-- CoreNLP annotations
--
CREATE TABLE corenlp_annotations (
    corenlp_annotations_id  SERIAL    PRIMARY KEY,
    object_id               INTEGER   NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    raw_data                BYTEA     NOT NULL
);
CREATE UNIQUE INDEX corenlp_annotations_object_id ON corenlp_annotations (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE corenlp_annotations
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;


--
-- Bit.ly processing results
--
CREATE TABLE bitly_processing_results (
    bitly_processing_results_id   SERIAL    PRIMARY KEY,
    object_id                     INTEGER   NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,

    -- (Last) data collection timestamp; NULL for Bit.ly click data that was collected for controversies
    collect_date                  TIMESTAMP NULL DEFAULT NOW(),

    raw_data                      BYTEA     NOT NULL
);
CREATE UNIQUE INDEX bitly_processing_results_object_id ON bitly_processing_results (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE bitly_processing_results
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;


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
          AND nsp.nspname = 'public'
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
