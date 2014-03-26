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

-- CREATE LANGUAGE IF NOT EXISTS plperlu
CREATE OR REPLACE FUNCTION create_language_plperlu()
RETURNS BOOLEAN AS $$
    CREATE LANGUAGE plperlu;
    SELECT TRUE;
$$ LANGUAGE SQL;

SELECT CASE WHEN NOT
    (
        SELECT  TRUE AS exists
        FROM    pg_language
        WHERE   lanname = 'plperlu'
        UNION
        SELECT  FALSE AS exists
        ORDER BY exists DESC
        LIMIT 1
    )
THEN
    create_language_plperlu()
ELSE
    FALSE
END AS plperlu_created;

DROP FUNCTION create_language_plperlu();


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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4445;
    
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


CREATE OR REPLACE FUNCTION purge_story_words(default_start_day date, default_end_day date)
  RETURNS VOID  AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
BEGIN
    current_time := timeofday()::timestamp;

    RAISE NOTICE 'time - %', current_time;

    IF ( ( not default_start_day is null ) and ( not default_end_day is null ) ) THEN
       RAISE NOTICE 'deleting for media without explict sw dates';
       DELETE from story_sentence_words where not media_id in ( select media_id from media where ( not (sw_data_start_date is null)) and (not (sw_data_end_date is null)) )
          AND ( publish_day < default_start_day or publish_day > default_end_day);
    END IF;

    FOR media_rec in  SELECT media_id, coalesce( sw_data_start_date, default_start_day ) as start_date FROM media where not (coalesce ( sw_data_start_date, default_start_day ) is null ) and (not sw_data_start_date is null) and (not sw_data_end_date is null) ORDER BY media_id LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, start_date - % time - %', media_rec.media_id, media_rec.start_date, current_time;
        DELETE from story_sentence_words where media_id = media_rec.media_id and publish_day < media_rec.start_date; 
    END LOOP;

  RAISE NOTICE 'time - %', current_time;  -- Prints 30
  FOR media_rec in  SELECT media_id, coalesce( sw_data_end_date, default_end_day ) as end_date FROM media where not (coalesce ( sw_data_end_date, default_end_day ) is null ) and (not sw_data_start_date is null) and (not sw_data_end_date is null) ORDER BY media_id LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, end_date - % time - %', media_rec.media_id, media_rec.end_date, current_time;
        DELETE from story_sentence_words where media_id = media_rec.media_id and publish_day > media_rec.end_date; 
    END LOOP;
END;
$$
LANGUAGE 'plpgsql'
 ;

CREATE OR REPLACE FUNCTION purge_story_sentences(default_start_day date, default_end_day date)
  RETURNS VOID  AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
BEGIN
    current_time := timeofday()::timestamp;

    RAISE NOTICE 'time - %', current_time;
    FOR media_rec in  SELECT media_id, coalesce( sw_data_start_date, default_start_day ) as start_date FROM media where not (coalesce ( sw_data_start_date, default_start_day ) is null ) ORDER BY media_id LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, start_date - % time - %', media_rec.media_id, media_rec.start_date, current_time;
        DELETE from story_sentences where media_id = media_rec.media_id and date_trunc( 'day', publish_date ) < date_trunc( 'day', media_rec.start_date ); 
    END LOOP;

  RAISE NOTICE 'time - %', current_time;  -- Prints 30
  FOR media_rec in  SELECT media_id, coalesce( sw_data_end_date, default_end_day ) as end_date FROM media where not (coalesce ( sw_data_end_date, default_end_day ) is null ) ORDER BY media_id LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, end_date - % time - %', media_rec.media_id, media_rec.end_date, current_time;
        DELETE from story_sentences where media_id = media_rec.media_id and date_trunc( 'day', publish_date ) > date_trunc( 'day', media_rec.end_date ); 
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
    FOR media_rec in  SELECT media_id, coalesce( sw_data_start_date, default_start_day ) as start_date FROM media where not (coalesce ( sw_data_start_date, default_start_day ) is null ) ORDER BY media_id LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, start_date - % time - %', media_rec.media_id, media_rec.start_date, current_time;
        DELETE from story_sentence_counts where media_id = media_rec.media_id and publish_week < date_trunc( 'day', media_rec.start_date ); 
    END LOOP;

  RAISE NOTICE 'time - %', current_time;  -- Prints 30
  FOR media_rec in  SELECT media_id, coalesce( sw_data_end_date, default_end_day ) as end_date FROM media where not (coalesce ( sw_data_end_date, default_end_day ) is null ) ORDER BY media_id LOOP
        current_time := timeofday()::timestamp;
        RAISE NOTICE 'media_id is %, end_date - % time - %', media_rec.media_id, media_rec.end_date, current_time;
        DELETE from story_sentence_counts where media_id = media_rec.media_id and publish_week > date_trunc( 'day', media_rec.end_date ); 
    END LOOP;
END;
$$
LANGUAGE 'plpgsql'
 ;

CREATE OR REPLACE FUNCTION last_updated_trigger () RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';                                                                                                                            

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') then

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
	UPDATE story_sentences set db_row_last_updated = now() where stories_id = NEW.stories_id;
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_stories_updated_time_by_stories_id_trigger () RETURNS trigger AS
$$
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
        WHERE stories_id = reference_stories_id;
	RETURN NULL;
   END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION update_story_sentences_updated_time_by_story_sentences_id_trigger () RETURNS trigger AS
$$
    DECLARE
        path_change boolean;
        reference_story_sentences_id integer default null;
    BEGIN

        IF TG_OP = 'INSERT' THEN
            -- The "old" record doesn't exist
            reference_story_sentences_id = NEW.story_sentences_id;
        ELSIF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
            reference_story_sentences_id = OLD.story_sentences_id;
        ELSE
            RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;
        END IF;

        UPDATE story_sentences
        SET db_row_last_updated = now()
        WHERE story_sentences_id = reference_story_sentences_id;
	RETURN NULL;
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
            reference_media_id = NEW.media_id;
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
    feeds_added         boolean         not null,
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
    dup_media_id        int             null references media on delete set null,
    is_not_dup          boolean         null,
    use_pager           boolean         null,
    unpaged_stories     int             not null default 0,
    CONSTRAINT media_name_not_empty CHECK ( ( (name)::text <> ''::text ) ),
    CONSTRAINT media_self_dup CHECK ( dup_media_id IS NULL OR dup_media_id <> media_id )
);

create unique index media_name on media(name);
create unique index media_url on media(url);
create index media_moderated on media(moderated);

CREATE INDEX media_name_trgm on media USING gin (name gin_trgm_ops);
CREATE INDEX media_url_trgm on media USING gin (url gin_trgm_ops);

create table media_stats (
    media_stats_id              serial      primary key,
    media_id                    int         not null references media on delete cascade,
    num_stories                 int         not null,
    num_sentences               int         not null,
    mean_num_sentences          int         not null,
    mean_text_length            int         not null,
    num_stories_with_sentences  int         not null,
    num_stories_with_text       int         not null,
    stat_date                   date        not null
);

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

create table tag_sets (
    tag_sets_id            serial            primary key,
    name                varchar(512)    not null,
    CONSTRAINT tag_sets_name_not_empty CHECK (((name)::text <> ''::text))
);

create unique index tag_sets_name on tag_sets (name);

create table tags (
    tags_id                serial            primary key,
    tag_sets_id            int                not null references tag_sets,
    tag                    varchar(512)    not null,
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
    db_row_last_updated                timestamp with time zone not null
);

DROP TRIGGER IF EXISTS media_tags_map_last_updated_trigger on media_tags_map CASCADE;
CREATE TRIGGER media_tags_last_updated_trigger BEFORE INSERT OR UPDATE ON media_tags_map FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger() ;
CREATE TRIGGER media_tags_map_update_stories_last_updated_trigger AFTER INSERT OR UPDATE OR DELETE ON media_tags_map FOR EACH ROW EXECUTE PROCEDURE update_stories_updated_time_by_media_id_trigger();

CREATE index media_tags_map_db_row_last_updated on media_tags_map ( db_row_last_updated );
create unique index media_tags_map_media on media_tags_map (media_id, tags_id);
create index media_tags_map_tag on media_tags_map (tags_id);

-- A dashboard defines which collections, dates, and topics appear together within a given dashboard screen.
-- For example, a dashboard might include three media_sets for russian collections, a set of dates for which 
-- to generate a dashboard for those collections, and a set of topics to use for specific dates for all media
-- sets within the collection
create table dashboards (
    dashboards_id               serial          primary key,
    name                        varchar(1024)   not null,
    start_date                  timestamp       not null,
    end_date                    timestamp       not null
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

create table media_cluster_runs (
	media_cluster_runs_id   serial          primary key,
	queries_id              int             not null references queries,
	num_clusters			int			    not null,
	state                   varchar(32)     not null default 'pending',
    clustering_engine       varchar(256)    not null
);

alter table media_cluster_runs add constraint media_cluster_runs_state check (state in ('pending', 'executing', 'completed'));

create table media_clusters (
	media_clusters_id		serial	primary key,
	media_cluster_runs_id	int	    not null references media_cluster_runs on delete cascade,
	description             text    null,
	centroid_media_id       int     null references media on delete cascade
);
CREATE INDEX media_clusters_runs_id on media_clusters(media_cluster_runs_id);
   
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
    media_clusters_id           int         references media_clusters on delete cascade,
    creation_date               timestamp   default now(),
    vectors_added               boolean     default false,
    include_in_dump             boolean     default true
);

CREATE INDEX media_sets_name_trgm on media_sets USING gin (name gin_trgm_ops);
CREATE INDEX media_sets_description_trgm on media_sets USING gin (description gin_trgm_ops);

CREATE VIEW media_sets_tt2_locale_format as select  '[% c.loc("' || COALESCE( name, '') || '") %]' || E'\n' ||  '[% c.loc("' || COALESCE (description, '') || '") %] ' as tt2_value from media_sets where set_type = 'collection' order by media_sets_id;

    
create table queries_media_sets_map (
    queries_id              int                 not null references queries on delete cascade,
    media_sets_id           int                 not null references media_sets on delete cascade
);

create index queries_media_sets_map_query on queries_media_sets_map ( queries_id );
create index queries_media_sets_map_media_set on queries_media_sets_map ( media_sets_id );

create table media_cluster_maps (
    media_cluster_maps_id       serial          primary key,
    method                      varchar(256)    not null,
    map_type                    varchar(32)     not null default 'cluster',
    name                        text            not null,
    json                        text            not null,
    nodes_total                 int             not null,
    nodes_rendered              int             not null,
    links_rendered              int             not null,
    media_cluster_runs_id       int             not null references media_cluster_runs on delete cascade
);
    
alter table media_cluster_maps add constraint media_cluster_maps_type check( map_type in ('cluster', 'polar' ));

create index media_cluster_maps_run on media_cluster_maps( media_cluster_runs_id );

create table media_cluster_map_poles (
    media_cluster_map_poles_id      serial      primary key,
    name                            text        not null,
    media_cluster_maps_id           int         not null references media_cluster_maps on delete cascade,
    pole_number                     int         not null,
    queries_id                      int         not null references queries on delete cascade
);

create index media_cluster_map_poles_map on media_cluster_map_poles( media_cluster_maps_id );
    
create table media_cluster_map_pole_similarities (
    media_cluster_map_pole_similarities_id  serial  primary key,
    media_id                                int     not null references media on delete cascade,
    queries_id                              int     not null references queries on delete cascade,
    similarity                              int     not null,
    media_cluster_maps_id                   int     not null references media_cluster_maps on delete cascade
);

create index media_cluster_map_pole_similarities_map ON media_cluster_map_pole_similarities (media_cluster_maps_id);

create table media_clusters_media_map (
    media_clusters_media_map_id     serial primary key,
	media_clusters_id               int   not null references media_clusters on delete cascade,
	media_id		                int   not null references media on delete cascade
);

create index media_clusters_media_map_cluster on media_clusters_media_map (media_clusters_id);
create index media_clusters_media_map_media on media_clusters_media_map (media_id);

create table media_cluster_words (
	media_cluster_words_id	serial	primary key,
	media_clusters_id       int	    not null references media_clusters on delete cascade,
    internal                boolean not null,
	weight			        float	not null,
	stem			        text	not null,
	term                    text    not null
);

create index media_cluster_words_cluster on media_cluster_words (media_clusters_id);

-- Jon's table for storing links between media sources
-- -> Used in Protovis' force visualization. 
create table media_cluster_links (
  media_cluster_links_id    serial  primary key,
  media_cluster_runs_id	    int	    not null     references media_cluster_runs on delete cascade,
  source_media_id           int     not null     references media              on delete cascade,
  target_media_id           int     not null     references media              on delete cascade,
  weight                    float   not null
);

-- A table to store the internal/external zscores for
-- every source analyzed by Cluto
-- (the external/internal similarity scores for
-- clusters will be stored in media_clusters, if at all)
create table media_cluster_zscores (
  media_cluster_zscores_id  serial primary key,
	media_cluster_runs_id	    int 	 not null     references media_cluster_runs on delete cascade,
	media_clusters_id         int    not null     references media_clusters     on delete cascade,
  media_id                  int    not null     references media              on delete cascade,
  internal_zscore           float  not null, 
  internal_similarity       float  not null,
  external_zscore           float  not null,
  external_similarity       float  not null     
);

-- alter table media_cluster_runs add constraint media_cluster_runs_media_set_fk foreign key ( media_sets_id ) references media_sets;
  
alter table media_sets add constraint dashboard_media_sets_type
check ( ( ( set_type = 'medium' ) and ( media_id is not null ) )
        or
        ( ( set_type = 'collection' ) and ( tags_id is not null ) )
        or
        ( ( set_type = 'cluster' ) and ( media_clusters_id is not null ) ) );

create unique index media_sets_medium on media_sets ( media_id );
create index media_sets_tag on media_sets ( tags_id );
create index media_sets_cluster on media_sets ( media_clusters_id );
create index media_sets_vectors_added on media_sets ( vectors_added );
        
create table media_sets_media_map (
    media_sets_media_map_id     serial  primary key,
    media_sets_id               int     not null references media_sets on delete cascade,    
    media_id                    int     not null references media on delete cascade,
    db_row_last_updated                timestamp with time zone not null
);

DROP TRIGGER IF EXISTS media_sets_media_map_last_updated_trigger on media_sets_media_map CASCADE;
CREATE TRIGGER media_sets_media_map_last_updated_trigger BEFORE INSERT OR UPDATE ON media_sets_media_map FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger() ;
CREATE TRIGGER media_sets_media_map_update_stories_last_updated_trigger AFTER INSERT OR UPDATE OR DELETE ON media_sets_media_map FOR EACH ROW EXECUTE PROCEDURE update_stories_updated_time_by_media_id_trigger();

create index media_sets_media_map_set on media_sets_media_map ( media_sets_id );
create index media_sets_media_map_media on media_sets_media_map ( media_id );
CREATE index media_sets_media_map_db_row_last_updated on media_sets_media_map ( db_row_last_updated );

CREATE OR REPLACE FUNCTION media_set_sw_data_retention_dates(v_media_sets_id int, default_start_day date, default_end_day date, OUT start_date date, OUT end_date date) AS
$$
DECLARE
    media_rec record;
    current_time timestamp;
BEGIN
    current_time := timeofday()::timestamp;

    --RAISE NOTICE 'time - % ', current_time;

    SELECT media_sets_id, min(coalesce (media.sw_data_start_date, default_start_day )) as sw_data_start_date, max( coalesce ( media.sw_data_end_date,  default_end_day )) as sw_data_end_date INTO media_rec from media_sets_media_map join media on (media_sets_media_map.media_id = media.media_id ) and media_sets_id = v_media_sets_id  group by media_sets_id;

    start_date = media_rec.sw_data_start_date; 
    end_date = media_rec.sw_data_end_date;

    --RAISE NOTICE 'start date - %', start_date;
    --RAISE NOTICE 'end date - %', end_date;

    return;
END;
$$
LANGUAGE 'plpgsql' STABLE
 ;

CREATE VIEW media_sets_explict_sw_data_dates as  select media_sets_id, min(media.sw_data_start_date) as sw_data_start_date, max( media.sw_data_end_date) as sw_data_end_date from media_sets_media_map join media on (media_sets_media_map.media_id = media.media_id )   group by media_sets_id;

CREATE VIEW media_with_collections AS
    SELECT t.tag, m.media_id, m.url, m.name, m.moderated, m.feeds_added, m.moderation_notes, m.full_text_rss FROM media m, tags t, tag_sets ts, media_tags_map mtm WHERE (((((ts.name)::text = 'collection'::text) AND (ts.tag_sets_id = t.tag_sets_id)) AND (mtm.tags_id = t.tags_id)) AND (mtm.media_id = m.media_id)) ORDER BY m.media_id;


CREATE OR REPLACE FUNCTION media_set_retains_sw_data_for_date(v_media_sets_id int, test_date date, default_start_day date, default_end_day date)
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

CREATE OR REPLACE FUNCTION purge_daily_words_for_media_set(v_media_sets_id int, default_start_day date, default_end_day date)
RETURNS VOID AS 
$$
DECLARE
    media_rec record;
    current_time timestamp;
    start_date   date;
    end_date     date;
BEGIN
    current_time := timeofday()::timestamp;

    RAISE NOTICE ' purge_daily_words_for_media_set media_sets_id %, time - %', v_media_sets_id, current_time;

    media_rec = media_set_sw_data_retention_dates( v_media_sets_id, default_start_day,  default_end_day );

    start_date = media_rec.start_date; 
    end_date = media_rec.end_date;

    RAISE NOTICE 'start date - %', start_date;
    RAISE NOTICE 'end date - %', end_date;

    DELETE from daily_words where media_sets_id = v_media_sets_id and (publish_day < start_date or publish_day > end_date) ;
    DELETE from total_daily_words where media_sets_id = v_media_sets_id and (publish_day < start_date or publish_day > end_date) ;

    return;
END;
$$
LANGUAGE 'plpgsql' 
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
    media_cluster_runs_id       int             null references media_cluster_runs on delete set null,
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

CREATE VIEW dashboard_topics_tt2_locale_format as select distinct on (tt2_value) '[% c.loc("' || name || '") %]' || ' - ' || '[% c.loc("' || lower(name) || '") %]' as tt2_value from (select * from dashboard_topics order by name, dashboard_topics_id) AS dashboard_topic_names order by tt2_value;

create table stories (
    stories_id                  serial          primary key,
    media_id                    int             not null references media on delete cascade,
    url                         varchar(1024)   not null,
    guid                        varchar(1024)   not null,
    title                       text            not null,
    description                 text            null,
    publish_date                timestamp       not null,
    collect_date                timestamp       not null,
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
create index stories_db_row_last_updated on stories( db_row_last_updated );
create index stories_title_hash on stories( md5( title ) );
create index stories_publish_day on stories( date_trunc( 'day', publish_date ) );

DROP TRIGGER IF EXISTS stories_last_updated_trigger on stories CASCADE;
CREATE TRIGGER stories_last_updated_trigger BEFORE INSERT OR UPDATE ON stories FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger() ;
DROP TRIGGER IF EXISTS stories_update_story_sentences_last_updated_trigger on stories CASCADE;
CREATE TRIGGER stories_update_story_sentences_last_updated_trigger AFTER INSERT OR UPDATE ON stories FOR EACH ROW EXECUTE PROCEDURE update_story_sentences_updated_time_trigger() ;

CREATE TYPE download_state AS ENUM ('error', 'fetching', 'pending', 'queued', 'success', 'feed_error', 'extractor_error');    
CREATE TYPE download_type  AS ENUM ('Calais', 'calais', 'content', 'feed', 'spider_blog_home', 'spider_posting', 'spider_rss', 'spider_blog_friends_list', 'spider_validation_blog_home','spider_validation_rss','archival_only');    

CREATE TYPE download_file_status AS ENUM ( 'tbd', 'missing', 'na', 'present', 'inline', 'redownloaded', 'error_redownloading' );

create table downloads (
    downloads_id        serial          primary key,
    feeds_id            int             null references feeds,
    stories_id          int             null references stories on delete cascade,
    parent              int             null,
    url                 varchar(1024)   not null,
    host                varchar(1024)   not null,
    download_time       timestamp       not null,
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

CREATE UNIQUE INDEX downloads_file_status on downloads(file_status, downloads_id);
CREATE UNIQUE INDEX downloads_relative_path on downloads( relative_file_path, downloads_id);


alter table downloads add constraint downloads_parent_fkey 
    foreign key (parent) references downloads on delete set null;
alter table downloads add constraint downloads_path
    check ((state = 'success' and path is not null) or 
           (state != 'success'));
alter table downloads add constraint downloads_feed_id_valid
      check ((feeds_id is not null) or 
      ( type = 'spider_blog_home' or type = 'spider_posting' or type = 'spider_rss' or type = 'spider_blog_friends_list' or type = 'archival_only') );
alter table downloads add constraint downloads_story
    check (((type = 'feed' or type = 'spider_blog_home' or type = 'spider_posting' or type = 'spider_rss' or type = 'spider_blog_friends_list' or type = 'archival_only')
    and stories_id is null) or (stories_id is not null));

-- make the query optimizer get enough stats to use the feeds_id index
alter table downloads alter feeds_id set statistics 1000;

create index downloads_parent on downloads (parent);
-- create unique index downloads_host_fetching 
--     on downloads(host, (case when state='fetching' then 1 else null end));
create index downloads_time on downloads (download_time);
    
create index downloads_feed_download_time on downloads ( feeds_id, download_time );

-- create index downloads_sequence on downloads (sequence);
create index downloads_type on downloads (type);
create index downloads_host_state_priority on downloads (host, state, priority);
create index downloads_feed_state on downloads(feeds_id, state);
create index downloads_story on downloads(stories_id);
create index downloads_url on downloads(url);
CREATE INDEX downloads_state_downloads_id_pending on downloads(state,downloads_id) where state='pending';
create index downloads_extracted on downloads(extracted, state, type) 
    where extracted = 'f' and state = 'success' and type = 'content';
CREATE INDEX downloads_stories_to_be_extracted on downloads (stories_id) where extracted = false AND state = 'success' AND type = 'content';        

CREATE INDEX downloads_extracted_stories on downloads (stories_id) where type='content' and state='success';
CREATE INDEX downloads_spider_urls on downloads(url) where type = 'spider_blog_home' or type = 'spider_posting' or type = 'spider_rss' or type = 'spider_blog_friends_list';
CREATE INDEX downloads_spider_download_errors_to_clear on downloads(state,type,error_message) where state='error' and type in ('spider_blog_home','spider_posting','spider_rss','spider_blog_friends_list') and (error_message like '50%' or error_message= 'Download timed out by Fetcher::_timeout_stale_downloads') ;
CREATE INDEX downloads_state_queued_or_fetching on downloads(state) where state='queued' or state='fetching';
CREATE INDEX downloads_state_fetching ON downloads(state, downloads_id) where state = 'fetching';

CREATE INDEX downloads_in_old_format ON downloads USING btree (downloads_id) WHERE ((state = 'success'::download_state) AND (path ~~ 'content/%'::text));

CREATE INDEX file_status_downloads_time_new_format ON downloads USING btree (file_status, download_time) WHERE (relative_file_path ~~ 'mediacloud-%'::text);

CREATE INDEX relative_file_paths_new_format_to_verify ON downloads USING btree (relative_file_path) WHERE ((((((file_status = 'tbd'::download_file_status) AND (relative_file_path <> 'tbd'::text)) AND (relative_file_path <> 'error'::text)) AND (relative_file_path <> 'na'::text)) AND (relative_file_path <> 'inline'::text)) AND (relative_file_path ~~ 'mediacloud-%'::text));

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

CREATE UNIQUE INDEX downloads_for_extractor_trainer on downloads ( downloads_id, feeds_id) where file_status <> 'missing' and type = 'content' and state = 'success';

CREATE INDEX downloads_sites_pending on downloads ( site_from_host( host ) ) where state='pending';

CREATE INDEX downloads_queued_spider ON downloads(downloads_id) where state = 'queued' and  type in  ('spider_blog_home','spider_posting','spider_rss','spider_blog_friends_list','spider_validation_blog_home','spider_validation_rss');

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
    db_row_last_updated                timestamp with time zone not null
);

DROP TRIGGER IF EXISTS stories_tags_map_last_updated_trigger on stories_tags_map CASCADE;
CREATE TRIGGER stories_tags_map_last_updated_trigger BEFORE INSERT OR UPDATE ON stories_tags_map FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger() ;
DROP TRIGGER IF EXISTS stories_tags_map_update_stories_last_updated_trigger on stories_tags_map;
CREATE TRIGGER stories_tags_map_update_stories_last_updated_trigger AFTER INSERT OR UPDATE OR DELETE ON stories_tags_map FOR EACH ROW EXECUTE PROCEDURE update_stories_updated_time_by_stories_id_trigger();

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
    
CREATE TABLE top_ten_tags_for_media (
    media_id integer NOT NULL,
    tags_id integer NOT NULL,
    media_tag_count integer NOT NULL,
    tag_name character varying(512) NOT NULL,
    tag_sets_id integer NOT NULL
);


CREATE INDEX media_id_and_tag_sets_id_index ON top_ten_tags_for_media USING btree (media_id, tag_sets_id);
CREATE INDEX media_id_index ON top_ten_tags_for_media USING btree (media_id);
CREATE INDEX tag_sets_id_index ON top_ten_tags_for_media USING btree (tag_sets_id);

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
    SELECT media.media_id, COALESCE(foo.extractor_training_downloads_for_media_id, (0)::bigint) AS extractor_training_download_count FROM (media LEFT JOIN (SELECT stories.media_id, count(stories.media_id) AS extractor_training_downloads_for_media_id FROM extractor_training_lines, downloads, stories WHERE ((extractor_training_lines.downloads_id = downloads.downloads_id) AND (downloads.stories_id = stories.stories_id)) GROUP BY stories.media_id ORDER BY stories.media_id) foo ON ((media.media_id = foo.media_id)));

CREATE VIEW yahoo_top_political_2008_media AS
    SELECT DISTINCT media_tags_map.media_id FROM media_tags_map, (SELECT tags.tags_id FROM tags, (SELECT DISTINCT media_tags_map.tags_id FROM media_tags_map ORDER BY media_tags_map.tags_id) media_tags WHERE ((tags.tags_id = media_tags.tags_id) AND ((tags.tag)::text ~~ 'yahoo_top_political_2008'::text))) interesting_media_tags WHERE (media_tags_map.tags_id = interesting_media_tags.tags_id) ORDER BY media_tags_map.media_id;

CREATE VIEW technorati_top_political_2008_media AS
    SELECT DISTINCT media_tags_map.media_id FROM media_tags_map, (SELECT tags.tags_id FROM tags, (SELECT DISTINCT media_tags_map.tags_id FROM media_tags_map ORDER BY media_tags_map.tags_id) media_tags WHERE ((tags.tags_id = media_tags.tags_id) AND ((tags.tag)::text ~~ 'technorati_top_political_2008'::text))) interesting_media_tags WHERE (media_tags_map.tags_id = interesting_media_tags.tags_id) ORDER BY media_tags_map.media_id;

CREATE VIEW media_extractor_training_downloads_count_adjustments AS
    SELECT yahoo.media_id, yahoo.yahoo_count_adjustment, tech.technorati_count_adjustment FROM (SELECT media_extractor_training_downloads_count.media_id, COALESCE(foo.yahoo_count_adjustment, 0) AS yahoo_count_adjustment FROM (media_extractor_training_downloads_count LEFT JOIN (SELECT yahoo_top_political_2008_media.media_id, 1 AS yahoo_count_adjustment FROM yahoo_top_political_2008_media) foo ON ((foo.media_id = media_extractor_training_downloads_count.media_id)))) yahoo, (SELECT media_extractor_training_downloads_count.media_id, COALESCE(foo.count_adjustment, 0) AS technorati_count_adjustment FROM (media_extractor_training_downloads_count LEFT JOIN (SELECT technorati_top_political_2008_media.media_id, 1 AS count_adjustment FROM technorati_top_political_2008_media) foo ON ((foo.media_id = media_extractor_training_downloads_count.media_id)))) tech WHERE (tech.media_id = yahoo.media_id);

CREATE VIEW media_adjusted_extractor_training_downloads_count AS
    SELECT media_extractor_training_downloads_count.media_id, ((media_extractor_training_downloads_count.extractor_training_download_count - (2 * media_extractor_training_downloads_count_adjustments.yahoo_count_adjustment)) - (2 * media_extractor_training_downloads_count_adjustments.technorati_count_adjustment)) AS count FROM (media_extractor_training_downloads_count JOIN media_extractor_training_downloads_count_adjustments ON ((media_extractor_training_downloads_count.media_id = media_extractor_training_downloads_count_adjustments.media_id))) ORDER BY ((media_extractor_training_downloads_count.extractor_training_download_count - (2 * media_extractor_training_downloads_count_adjustments.yahoo_count_adjustment)) - (2 * media_extractor_training_downloads_count_adjustments.technorati_count_adjustment));

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
ALTER TABLE extractor_results_cache ALTER COLUMN extractor_results_cache_id SET DEFAULT nextval('extractor_results_cache_extractor_results_cache_id_seq'::regclass);
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
       language                     varchar(3)      null      -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
);

create index story_sentences_story on story_sentences (stories_id, sentence_number);
create index story_sentences_publish_day on story_sentences( date_trunc( 'day', publish_date ), media_id );
create index story_sentences_language on story_sentences(language);
create index story_sentences_media_id    on story_sentences( media_id );
create index story_sentences_db_row_last_updated    on story_sentences( db_row_last_updated );

ALTER TABLE  story_sentences ADD CONSTRAINT story_sentences_media_id_fkey FOREIGN KEY (media_id) REFERENCES media(media_id) ON DELETE CASCADE;
ALTER TABLE  story_sentences ADD CONSTRAINT story_sentences_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES stories(stories_id) ON DELETE CASCADE;

DROP TRIGGER IF EXISTS story_sentences_last_updated_trigger on story_sentences CASCADE;
CREATE TRIGGER story_sentences_last_updated_trigger BEFORE INSERT OR UPDATE ON story_sentences FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger() ;

create table story_sentences_tags_map
(
    story_sentences_tags_map_id     bigserial  primary key,
    story_sentences_id              bigint     not null references story_sentences on delete cascade,
    tags_id                 int     not null references tags on delete cascade,
    db_row_last_updated                timestamp with time zone not null
);

DROP TRIGGER IF EXISTS story_sentences_tags_map_last_updated_trigger on story_sentences_tags_map CASCADE;
CREATE TRIGGER story_sentences_tags_map_last_updated_trigger BEFORE INSERT OR UPDATE ON story_sentences_tags_map FOR EACH ROW EXECUTE PROCEDURE last_updated_trigger() ;
DROP TRIGGER IF EXISTS story_sentences_tags_map_update_story_sentences_last_updated_trigger on story_sentences_tags_map;
CREATE TRIGGER story_sentences_tags_map_update_story_sentences_last_updated_trigger AFTER INSERT OR UPDATE OR DELETE ON story_sentences_tags_map FOR EACH ROW EXECUTE PROCEDURE update_story_sentences_updated_time_by_story_sentences_id_trigger();

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

create table story_sentence_words (
       stories_id                   int             not null, -- references stories on delete cascade,
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   smallint        not null,
       sentence_number              smallint        not null,
       media_id                     int             not null, -- references media on delete cascade,
       publish_day                  date            not null
);

create index story_sentence_words_story on story_sentence_words (stories_id, sentence_number);
create index story_sentence_words_dsm on story_sentence_words (publish_day, stem, media_id);
create index story_sentence_words_dm on story_sentence_words (publish_day, media_id);
--ALTER TABLE  story_sentence_words ADD CONSTRAINT story_sentence_words_media_id_fkey FOREIGN KEY (media_id) REFERENCES media(media_id) ON DELETE CASCADE;
--ALTER TABLE  story_sentence_words ADD CONSTRAINT story_sentence_words_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES stories(stories_id) ON DELETE CASCADE;

create table daily_words (
       daily_words_id               bigserial          primary key,
       media_sets_id                int             not null, -- references media_sets,
       dashboard_topics_id          int             null,     -- references dashboard_topics,
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   int             not null,
       publish_day                  date            not null
);

create index daily_words_media on daily_words(publish_day, media_sets_id, dashboard_topics_id, stem);
create index daily_words_count on daily_words(publish_day, media_sets_id, dashboard_topics_id, stem_count);
create index daily_words_publish_week on daily_words(week_start_date(publish_day));

CREATE INDEX daily_words_day_topic ON daily_words USING btree (publish_day, dashboard_topics_id);

create table weekly_words (
       weekly_words_id              bigserial          primary key,
       media_sets_id                int             not null, -- references media_sets,
       dashboard_topics_id          int             null,     -- references dashboard_topics,
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   int             not null,
       publish_week                 date            not null
);

create UNIQUE index weekly_words_media on weekly_words(publish_week, media_sets_id, dashboard_topics_id, stem);
create index weekly_words_count on weekly_words(publish_week, media_sets_id, dashboard_topics_id, stem_count);
create index weekly_words_topic on weekly_words (publish_week, dashboard_topics_id);

ALTER TABLE  weekly_words ADD CONSTRAINT weekly_words_publish_week_is_monday CHECK ( EXTRACT ( ISODOW from publish_week) = 1 );

create table top_500_weekly_words (
       top_500_weekly_words_id      serial          primary key,
       media_sets_id                int             not null, -- references media_sets on delete cascade,
       dashboard_topics_id          int             null,     -- references dashboard_topics,
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   int             not null,
       publish_week                 date            not null
);

create UNIQUE index top_500_weekly_words_media on top_500_weekly_words(publish_week, media_sets_id, dashboard_topics_id, stem);
create index top_500_weekly_words_media_null_dashboard on top_500_weekly_words (publish_week,media_sets_id, dashboard_topics_id) 
    where dashboard_topics_id is null;
create index top_500_weekly_words_dmds on top_500_weekly_words using btree (publish_week, media_sets_id, dashboard_topics_id, stem);

ALTER TABLE  top_500_weekly_words ADD CONSTRAINT top_500_weekly_words_publish_week_is_monday CHECK ( EXTRACT ( ISODOW from publish_week) = 1 );
  
create table total_top_500_weekly_words (
       total_top_500_weekly_words_id       serial          primary key,
       media_sets_id                int             not null references media_sets on delete cascade, 
       dashboard_topics_id          int             null references dashboard_topics,
       publish_week                 date            not null,
       total_count                  int             not null
);
ALTER TABLE total_top_500_weekly_words ADD CONSTRAINT total_top_500_weekly_words_publish_week_is_monday CHECK ( EXTRACT ( ISODOW from publish_week) = 1 );

create unique index total_top_500_weekly_words_media 
    on total_top_500_weekly_words(publish_week, media_sets_id, dashboard_topics_id);

create view top_500_weekly_words_with_totals as select t5.*, tt5.total_count from top_500_weekly_words t5, total_top_500_weekly_words tt5       where t5.media_sets_id = tt5.media_sets_id and t5.publish_week = tt5.publish_week and         ( ( t5.dashboard_topics_id = tt5.dashboard_topics_id ) or           ( t5.dashboard_topics_id is null and tt5.dashboard_topics_id is null ) );

create view top_500_weekly_words_normalized
    as select t5.stem, min(t5.term) as term,             ( least( 0.01, sum(t5.stem_count)::numeric / sum(t5.total_count)::numeric ) * count(*) ) as stem_count, t5.media_sets_id, t5.publish_week, t5.dashboard_topics_id         from top_500_weekly_words_with_totals t5    group by t5.stem, t5.publish_week, t5.media_sets_id, t5.dashboard_topics_id;
    
create table total_daily_words (
       total_daily_words_id         serial          primary key,
       media_sets_id                int             not null, -- references media_sets on delete cascade,
       dashboard_topics_id           int            null,     -- references dashboard_topics,
       publish_day                  date            not null,
       total_count                  int             not null
);

create index total_daily_words_media_sets_id on total_daily_words (media_sets_id);
create index total_daily_words_media_sets_id_publish_day on total_daily_words (media_sets_id,publish_day);
create index total_daily_words_publish_day on total_daily_words (publish_day);
create index total_daily_words_publish_week on total_daily_words (week_start_date(publish_day));
create unique index total_daily_words_media_sets_id_dashboard_topic_id_publish_day ON total_daily_words (media_sets_id, dashboard_topics_id, publish_day);


create table total_weekly_words (
       total_weekly_words_id         serial          primary key,
       media_sets_id                 int             not null references media_sets on delete cascade, 
       dashboard_topics_id           int             null references dashboard_topics on delete cascade,
       publish_week                  date            not null,
       total_count                   int             not null
);
create index total_weekly_words_media_sets_id on total_weekly_words (media_sets_id);
create index total_weekly_words_media_sets_id_publish_day on total_weekly_words (media_sets_id,publish_week);
create unique index total_weekly_words_ms_id_dt_id_p_week on total_weekly_words(media_sets_id, dashboard_topics_id, publish_week);
CREATE INDEX total_weekly_words_publish_week on total_weekly_words(publish_week);
INSERT INTO total_weekly_words(media_sets_id, dashboard_topics_id, publish_week, total_count) select media_sets_id, dashboard_topics_id, publish_week, sum(stem_count) as total_count from weekly_words group by media_sets_id, dashboard_topics_id, publish_week order by publish_week asc, media_sets_id, dashboard_topics_id ;

create view daily_words_with_totals as select d.*, t.total_count from daily_words d, total_daily_words t where d.media_sets_id = t.media_sets_id and d.publish_day = t.publish_day and ( ( d.dashboard_topics_id = t.dashboard_topics_id ) or ( d.dashboard_topics_id is null and t.dashboard_topics_id is null ) );

create view story_extracted_texts as select stories_id, array_to_string(array_agg(download_text), ' ') as extracted_text 
       from (select * from downloads natural join download_texts order by downloads_id) as downloads group by stories_id;



CREATE VIEW media_feed_counts as (SELECT media_id, count(*) as feed_count FROM feeds GROUP by media_id);

CREATE TABLE daily_country_counts (
    media_sets_id integer  not null references media_sets on delete cascade,
    publish_day date not null,
    country character varying not null,
    country_count bigint not null,
    dashboard_topics_id integer references dashboard_topics on delete cascade
);

CREATE INDEX daily_country_counts_day_media_dashboard ON daily_country_counts USING btree (publish_day, media_sets_id, dashboard_topics_id);

CREATE TABLE authors (
    authors_id serial          PRIMARY KEY,
    author_name character varying UNIQUE NOT NULL
);
create index authors_name_varchar_pattern on authors(lower(author_name) varchar_pattern_ops);
create index authors_name_varchar_pattern_1 on authors(lower(split_part(author_name, ' ', 1)) varchar_pattern_ops);
create index authors_name_varchar_pattern_2 on authors(lower(split_part(author_name, ' ', 2)) varchar_pattern_ops);
create index authors_name_varchar_pattern_3 on authors(lower(split_part(author_name, ' ', 3)) varchar_pattern_ops);

CREATE TABLE authors_stories_map (
    authors_stories_map_id  serial            primary key,
    authors_id int                not null references authors on delete cascade,
    stories_id int                not null references stories on delete cascade
);

CREATE INDEX authors_stories_map_authors_id on authors_stories_map(authors_id);
CREATE INDEX authors_stories_map_stories_id on authors_stories_map(stories_id);

CREATE TYPE authors_stories_queue_type AS ENUM ('queued', 'pending', 'success', 'failed');

CREATE TABLE authors_stories_queue (
    authors_stories_queue_id  serial            primary key,
    stories_id int                not null references stories on delete cascade,
    state      authors_stories_queue_type not null
);
   
create table queries_dashboard_topics_map (
    queries_id              int                 not null references queries on delete cascade,
    dashboard_topics_id     int                 not null references dashboard_topics on delete cascade
);

create index queries_dashboard_topics_map_query on queries_dashboard_topics_map ( queries_id );
create index queries_dashboard_topics_map_dashboard_topic on queries_dashboard_topics_map ( dashboard_topics_id );

CREATE TABLE daily_author_words (
    daily_author_words_id           serial                  primary key,
    authors_id                      integer                 not null references authors on delete cascade,
    media_sets_id                   integer                 not null references media_sets on delete cascade,
    term                            character varying(256)  not null,
    stem                            character varying(256)  not null,
    stem_count                      int                     not null,
    publish_day                     date                    not null
);

create UNIQUE index daily_author_words_media on daily_author_words(publish_day, authors_id, media_sets_id, stem);
create index daily_author_words_count on daily_author_words(publish_day, authors_id, media_sets_id, stem_count);

create table total_daily_author_words (
       total_daily_author_words_id  serial          primary key,
       authors_id                   int             not null references authors on delete cascade,
       media_sets_id                int             not null references media_sets on delete cascade, 
       publish_day                  timestamp       not null,
       total_count                  int             not null
);

create index total_daily_author_words_authors_id_media_sets_id on total_daily_author_words (authors_id, media_sets_id);
create unique index total_daily_author_words_authors_id_media_sets_id_publish_day on total_daily_author_words (authors_id, media_sets_id,publish_day);

create table weekly_author_words (
       weekly_author_words_id       serial          primary key,
       media_sets_id                int             not null references media_sets on delete cascade,
       authors_id                   int             not null references authors on delete cascade,
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   int             not null,
       publish_week                 date            not null
);

create index weekly_author_words_media on weekly_author_words(publish_week, authors_id, media_sets_id, stem);
create index weekly_author_words_count on weekly_author_words(publish_week, authors_id, media_sets_id, stem_count);

create UNIQUE index weekly_author_words_unique on weekly_author_words(publish_week, authors_id, media_sets_id, stem);

create table top_500_weekly_author_words (
       top_500_weekly_author_words_id      serial          primary key,
       media_sets_id                int             not null references media_sets on delete cascade,
       authors_id                   int             not null references authors on delete cascade,
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   int             not null,
       publish_week                 date            not null
);

create index top_500_weekly_author_words_media on top_500_weekly_author_words(publish_week, media_sets_id, authors_id);
create index top_500_weekly_author_words_authors on top_500_weekly_author_words(authors_id, publish_week, media_sets_id);
create UNIQUE index top_500_weekly_author_words_authors_stem on top_500_weekly_author_words(authors_id, publish_week, media_sets_id, stem);
create index top_500_weekly_author_words_publish_week on top_500_weekly_author_words (publish_week);
    
create table total_top_500_weekly_author_words (
       total_top_500_weekly_author_words_id       serial          primary key,
       media_sets_id                int             not null references media_sets on delete cascade,
       authors_id                   int             not null references authors on delete cascade,
       publish_week                 date            not null,
       total_count                  int             not null
);

create UNIQUE index total_top_500_weekly_author_words_media 
    on total_top_500_weekly_author_words(publish_week, media_sets_id, authors_id);
create UNIQUE index total_top_500_weekly_author_words_authors 
    on total_top_500_weekly_author_words(authors_id, publish_week, media_sets_id);

CREATE TABLE popular_queries (
    popular_queries_id  serial          primary key,
    queries_id_0 integer NOT NULL,
    queries_id_1 integer,
    query_0_description character varying(1024) NOT NULL,
    query_1_description character varying(1024),
    dashboard_action character varying(1024),
    url_params character varying(1024),
    count integer DEFAULT 0,
    dashboards_id integer references dashboards NOT NULL
);

CREATE UNIQUE INDEX popular_queries_da_up ON popular_queries(dashboard_action, url_params);
CREATE UNIQUE INDEX popular_queries_query_ids ON popular_queries( queries_id_0,  queries_id_1);
CREATE INDEX popular_queries_dashboards_id_count on popular_queries(dashboards_id, count);

create table query_story_searches (
    query_story_searches_id     serial primary key,
    queries_id                  int not null references queries,
    pattern                     text,
    search_completed            boolean default false,
    csv_text                    text
);

create unique index query_story_searches_query_pattern on query_story_searches( queries_id, pattern );
  
create table query_story_searches_stories_map (
    query_story_searches_id     int references query_story_searches on delete cascade,
    stories_id                  int references stories on delete cascade
);

create unique index query_story_searches_stories_map_u on query_story_searches_stories_map ( query_story_searches_id, stories_id );
    
create table story_similarities (
    story_similarities_id   serial primary key,
    stories_id_a            int,
    publish_day_a           date,
    stories_id_b            int,
    publish_day_b           date,
    similarity              int
);

create index story_similarities_a_b on story_similarities ( stories_id_a, stories_id_b );
create index story_similarities_a_s on story_similarities ( stories_id_a, similarity, publish_day_b );
create index story_similarities_b_s on story_similarities ( stories_id_b, similarity, publish_day_a );
create index story_similarities_day on story_similarities ( publish_day_a, publish_day_b ); 
     
create view story_similarities_transitive as
    ( select story_similarities_id, stories_id_a, publish_day_a, stories_id_b, publish_day_b, similarity from story_similarities ) union  ( select story_similarities_id, stories_id_b as stories_id_a, publish_day_b as publish_day_a, stories_id_a as stories_id_b, publish_day_a as publish_day_b, similarity from story_similarities );
            
create table controversies (
    controversies_id        serial primary key,
    name                    varchar(1024) not null,
    query_story_searches_id int not null references query_story_searches
);

create unique index controversies_name on controversies( name );
    
create view controversies_with_search_info as
    select c.*, q.start_date::date, q.end_date::date, qss.pattern, qss.queries_id
        from controversies c
            left join query_story_searches qss on ( c.query_story_searches_id = qss.query_story_searches_id )
            left join queries q on ( qss.queries_id = q.queries_id );
    
create table controversy_dates (
    controversy_dates_id    serial primary key,
    controversies_id        int not null references controversies on delete cascade,
    start_date              date not null,
    end_date                date not null
);

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

create view controversy_links_cross_media as
  select s.stories_id, sm.name as media_name, r.stories_id as ref_stories_id, rm.name as ref_media_name, cl.url as url, cs.controversies_id, cl.controversy_links_id from media sm, media rm, controversy_links cl, stories s, stories r, controversy_stories cs where cl.ref_stories_id <> cl.stories_id and s.stories_id = cl.stories_id and cl.ref_stories_id = r.stories_id and s.media_id <> r.media_id and sm.media_id = s.media_id and rm.media_id = r.media_id and cs.stories_id = cl.ref_stories_id and cs.controversies_id = cl.controversies_id;

create table controversy_seed_urls (
    controversy_seed_urls_id        serial primary key,
    controversies_id                int not null references controversies on delete cascade,
    url                             text,
    source                          text,
    stories_id                      int references stories on delete cascade,
    processed                       boolean not null default false,
    assume_match                    boolean not null default false
);

create index controversy_seed_urls_controversy on controversy_seed_urls( controversies_id );
create index controversy_seed_urls_url on controversy_seed_urls( url );
    
create table controversy_ignore_redirects (
    controversy_ignore_redirects_id     serial primary key,
    url                                 varchar( 1024 )
);

create index controversy_ignore_redirects_url on controversy_ignore_redirects ( url );

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
    feeds_added             boolean         not null,
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
    tag                     varchar(512)
);
create index tags_id on cd.tags ( controversy_dumps_id, tags_id );

create table cd.tag_sets (
    controversy_dumps_id    int not null    references controversy_dumps on delete cascade,    
    tag_sets_id             int,
    name                    varchar(512)    
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
    outlink_count                           int not null
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
    story_count                     int not null
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
    stories_id                  int             not null references stories on delete cascade
);

create index processed_stories_story on processed_stories ( stories_id );
CREATE TRIGGER processed_stories_update_stories_last_updated_trigger AFTER INSERT OR UPDATE OR DELETE ON processed_stories FOR EACH ROW EXECUTE PROCEDURE update_stories_updated_time_by_stories_id_trigger();

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

CREATE VIEW daily_stats as select * from (SELECT count(*) as daily_downloads from downloads_in_past_day) as dd, (select count(*) as daily_stories from stories_collected_in_past_day) ds , (select count(*) as downloads_to_be_extracted from downloads_to_be_extracted) dex, (select count(*) as download_errors from downloads_with_error_in_past_day ) er;

CREATE TABLE queries_top_weekly_words_json (
   queries_top_weekly_words_json_id serial primary key,
   queries_id integer references queries on delete cascade not null unique,
   top_weekly_words_json text not null 
);

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
CREATE TRIGGER download_relative_file_path_trigger BEFORE INSERT OR UPDATE ON downloads FOR EACH ROW EXECUTE PROCEDURE  download_relative_file_path_trigger() ;

CREATE INDEX relative_file_paths_to_verify ON downloads USING btree (relative_file_path) WHERE (((((file_status = 'tbd'::download_file_status) AND (relative_file_path <> 'tbd'::text)) AND (relative_file_path <> 'error'::text)) AND (relative_file_path <> 'na'::text)) AND (relative_file_path <> 'inline'::text));

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
    api_token       VARCHAR(64)     UNIQUE NOT NULL DEFAULT generate_api_token() CONSTRAINT api_token_64_characters CHECK(LENGTH(api_token) = 64),

    full_name       TEXT    NOT NULL,
    notes           TEXT    NULL,
    active          BOOLEAN NOT NULL DEFAULT true,

    -- Salted hash of a password reset token (with Crypt::SaltedHash, algorithm => 'SHA-256',
    -- salt_len=>64) or NULL
    password_reset_token_hash TEXT  UNIQUE NULL CONSTRAINT password_reset_token_hash_sha256 CHECK(LENGTH(password_reset_token_hash) = 137 OR password_reset_token_hash IS NULL),

    -- Timestamp of the last unsuccessful attempt to log in; used for delaying successive
    -- attempts in order to prevent brute-force attacks
    last_unsuccessful_login_attempt     TIMESTAMP NOT NULL DEFAULT TIMESTAMP 'epoch'
);

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
    ('stories-api', 'Access to the stories api');

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


--
-- List of CoreNLP-annotated stories
--

CREATE TABLE corenlp_annotated_stories (
    corenlp_annotated_stories_id    BIGSERIAL   PRIMARY KEY,
    stories_id                      INT         NOT NULL REFERENCES stories ON DELETE CASCADE
);

CREATE INDEX corenlp_annotated_stories_stories_id ON corenlp_annotated_stories ( stories_id );
