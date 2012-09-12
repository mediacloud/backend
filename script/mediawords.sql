/* schema for MediaWords database */

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

create table media (
    media_id            serial          primary key,
    url                 varchar(1024)   not null,
    name                varchar(128)    not null,
    moderated           boolean         not null,
    feeds_added         boolean         not null,
    moderation_notes    text            null,       
    full_text_rss       boolean         ,
    extract_author      boolean         default(false),
    sw_data_start_date  date            default(null),
    sw_data_end_date    date            default(null),
    CONSTRAINT media_name_not_empty CHECK (((name)::text <> ''::text))
);

create unique index media_name on media(name);
create unique index media_url on media(url);
create index media_moderated on media(moderated);

create table feeds (
    feeds_id            serial            primary key,
    media_id            int                not null references media on delete cascade,
    name                varchar(512)    not null,        
    url                       varchar(1024)    not null,
    reparse             boolean         null,
    last_download_time  timestamp       null    
);

create index feeds_media on feeds(media_id);
create index feeds_name on feeds(name);
create unique index feeds_url on feeds (url, media_id);
create index feeds_reparse on feeds(reparse);
create index feeds_last_download_time on feeds(last_download_time);

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
        CONSTRAINT no_lead_or_trailing_whitspace CHECK ((((((tag_sets_id = 13) OR (tag_sets_id = 9)) OR (tag_sets_id = 8)) OR (tag_sets_id = 6)) OR ((tag)::text = btrim((tag)::text, ' 
    '::text)))),
        CONSTRAINT no_line_feed CHECK (((NOT ((tag)::text ~~ '%
%'::text)) AND (NOT ((tag)::text ~~ '%
%'::text)))),
        CONSTRAINT tag_not_empty CHECK (((tag)::text <> ''::text))
);

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
    tags_id                int                not null references tags on delete cascade
);

create unique index media_tags_map_media on media_tags_map (media_id, tags_id);
create index media_tags_map_tag on media_tags_map (tags_id);

CREATE TYPE query_version_enum AS ENUM ('1.0');

create table queries (
    queries_id              serial              primary key,
    start_date              date                not null,
    end_date                date                not null,
    generate_page           boolean             not null default false,
    creation_date           timestamp           not null default now(),
    description             text                null
);


create index queries_creation_date on queries (creation_date);
create index queries_hash on queries ( md5( description ) );
ALTER TABLE queries ADD COLUMN query_version query_version_enum DEFAULT enum_last (null::query_version_enum ) NOT NULL;
create unique index queries_hash_version on queries ( md5( description ), query_version );
CREATE INDEX queries_description ON queries USING btree (description);

create table media_cluster_runs (
	media_cluster_runs_id   serial          primary key,
	queries_id              int             not null references queries,
	num_clusters			int			    not null,
	state                   varchar(32)     not null default 'pending'
);

alter table media_cluster_runs add constraint media_cluster_runs_state check (state in ('pending', 'executing', 'completed'));

create table media_clusters (
	media_clusters_id		serial	primary key,
	media_cluster_runs_id	int	    not null references media_cluster_runs on delete cascade,
	description             text    null,
	centroid_media_id       int     null references media on delete cascade
);
CREATE INDEX media_clusters_runs_id on media_clusters(media_cluster_runs_id);
   
/* 
sets of media sources that should appear in the dashboard

the contents of the row depend on the set_type, which can be one of:
medium -- a single medium (media_id)
collection -- all media associated with the given tag (tags_id)
cluster -- all media within the given clusters (clusters_id)

see the check constraint for the definition of which set_type has which rows set
*/
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

/****************************************************** 
 * Jon's table for storing links between media sources
 *  -> Used in Protovis' force visualization. 
 ******************************************************/

create table media_cluster_links (
  media_cluster_links_id    serial  primary key,
  media_cluster_runs_id	    int	    not null     references media_cluster_runs on delete cascade,
  source_media_id           int     not null     references media              on delete cascade,
  target_media_id           int     not null     references media              on delete cascade,
  weight                    float   not null
);

/****************************************************** 
 * A table to store the internal/external zscores for
 *   every source analyzed by Cluto
 *   (the external/internal similarity scores for
 *     clusters will be stored in media_clusters, if at all)
 ******************************************************/

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
    media_id                    int     not null references media on delete cascade
);

create index media_sets_media_map_set on media_sets_media_map ( media_sets_id );
create index media_sets_media_map_media on media_sets_media_map ( media_id );

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

    return  ( start_date <= test_date ) and ( end_date >= test_date );    
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

/*
A dashboard defines which collections, dates, and topics appear together within a given dashboard screen.

For example, a dashboard might include three media_sets for russian collections, a set of dates for which 
to generate a dashboard for those collections, and a set of topics to use for specific dates for all media
sets within the collection
*/
create table dashboards (
    dashboards_id               serial          primary key,
    name                        varchar(1024)   not null,
    start_date                  timestamp       not null,
    end_date                    timestamp       not null
);

create unique index dashboards_name on dashboards ( name );

/*
dashboard_media_sets associates certain 'collection' type media_sets with a given dashboard.  Those assocaited media_sets will
appear on the dashboard page, and the media associated with the collections will be available from autocomplete box.

this table is also used to determine for which dates to create [daily|weekly|top_500_weekly]_words entries for which 
media_sets / topics
*/
create table dashboard_media_sets (
    dashboard_media_sets_id     serial          primary key,
    dashboards_id               int             not null references dashboards on delete cascade,
    media_sets_id               int             not null references media_sets on delete cascade,
    media_cluster_runs_id       int             null references media_cluster_runs on delete set null
);

create unique index dashboard_media_sets_media_set on dashboard_media_sets( media_sets_id );
CREATE UNIQUE INDEX dashboard_media_sets_media_set_dashboard on dashboard_media_sets(media_sets_id, dashboards_id);
create index dashboard_media_sets_dashboard on dashboard_media_sets( dashboards_id );

/*
a topic is a query used to generate dashboard results for a subset of matching stories.  for instance,
a topic with a query of 'health' would generate dashboard results for only stories that include
the word 'health'.  a given topic is confined to a given dashbaord and optionally to date range
within the date range of the dashboard.
*/
create table dashboard_topics (
    dashboard_topics_id         serial          primary key,
    name                        varchar(256)    not null,
    query                       varchar(1024)   not null,
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
    full_text_rss               boolean         not null default 'f'
);

/*create index stories_media on stories (media_id, guid);*/
create index stories_media_id on stories (media_id);
create unique index stories_guid on stories(guid, media_id);
create index stories_url on stories (url);
create index stories_publish_date on stories (publish_date);
create index stories_collect_date on stories (collect_date);
create index stories_title_pubdate on stories(title, publish_date);
create index stories_md on stories(media_id, date_trunc('day'::text, publish_date));

CREATE TYPE download_state AS ENUM ('error', 'fetching', 'pending', 'queued', 'success');    
CREATE TYPE download_type  AS ENUM ('Calais', 'calais', 'content', 'feed', 'spider_blog_home', 'spider_posting', 'spider_rss', 'spider_blog_friends_list', 'spider_validation_blog_home','spider_validation_rss','archival_only');    

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
    extracted           boolean         not null default 'f'
);

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

/*create index downloads_sequence on downloads (sequence);*/
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

create view downloads_media as select d.*, f.media_id as _media_id from downloads d, feeds f where d.feeds_id = f.feeds_id;

create view downloads_non_media as select d.* from downloads d where d.feeds_id is null;

CREATE INDEX downloads_sites_index on downloads (regexp_replace(host, $q$^(.)*?([^.]+)\.([^.]+)$$q$ ,E'\\2.\\3'));
CREATE INDEX downloads_sites_pending on downloads (regexp_replace(host, $q$^(.)*?([^.]+)\.([^.]+)$$q$ ,E'\\2.\\3')) where state='pending';

CREATE INDEX downloads_queued_spider ON downloads(downloads_id) where state = 'queued' and  type in  ('spider_blog_home','spider_posting','spider_rss','spider_blog_friends_list','spider_validation_blog_home','spider_validation_rss');

CREATE INDEX downloads_sites_downloads_id_pending ON downloads USING btree (regexp_replace((host)::text, E'^(.)*?([^.]+)\\.([^.]+)$'::text, E'\\2.\\3'::text), downloads_id) WHERE (state = 'pending'::download_state);

/*
CREATE INDEX downloads_sites_index_downloads_id on downloads (regexp_replace(host, $q$^(.)*?([^.]+)\.([^.]+)$$q$ ,E'\\2.\\3'), downloads_id);
*/

CREATE VIEW downloads_sites as select regexp_replace(host, $q$^(.)*?([^.]+)\.([^.]+)$$q$ ,E'\\2.\\3') as site, * from downloads_media;

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
    tags_id                 int     not null references tags on delete cascade
);

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
    download_text_length int not null
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

ALTER TABLE download_texts ALTER COLUMN download_text_length set NOT NULL;

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
    
create table word_cloud_topics (
        word_cloud_topics_id    serial      primary key,
        source_tags_id          int         not null references tags,
        set_tag_names           text        not null,
        creator                 text        not null,
        query                   text        not null,
        type                    text        not null,
        start_date              date        not null,
        end_date                date        not null,
        state                   text        not null,
        url                     text        not null
);

alter table word_cloud_topics add constraint word_cloud_topics_type check (type in ('words', 'phrases'));
alter table word_cloud_topics add constraint word_cloud_topics_state check (state in ('pending', 'generating', 'completed'));

/* VIEWS */

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
       stories_id                   int             not null, /*references stories on delete cascade,*/
       sentence_number              int             not null,
       sentence                     text            not null,
       media_id                     int             not null, /* references media on delete cascade, */
       publish_date                 timestamp       not null
);

create index story_sentences_story on story_sentences (stories_id, sentence_number);
create index story_sentences_publish_day on story_sentences( date_trunc( 'day', publish_date ), media_id );
ALTER TABLE  story_sentences ADD CONSTRAINT story_sentences_media_id_fkey FOREIGN KEY (media_id) REFERENCES media(media_id) ON DELETE CASCADE;
ALTER TABLE  story_sentences ADD CONSTRAINT story_sentences_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES stories(stories_id) ON DELETE CASCADE;
    
create table story_sentence_counts (
       story_sentence_counts_id     bigserial       primary key,
       sentence_md5                 varchar(64)     not null,
       media_id                     int             not null, /* references media */
       publish_week                 timestamp       not null,
       sentence_count               int             not null,
       first_stories_id             int             not null,
       first_sentence_number        int             not null
);

--# We have chossen not to make the 'story_sentence_counts_md5' index unique purely for performance reasons.
--# Duplicate rows within this index are not desirable but are relatively rare in practice.
--# Thus we have decided to avoid the performance and code complexity implications of a unique index
-- See Issue 1599
create index story_sentence_counts_md5 on story_sentence_counts( media_id, publish_week, sentence_md5 );

create index story_sentence_counts_first_stories_id on story_sentence_counts( first_stories_id );

create table story_sentence_words (
       stories_id                   int             not null, /* references stories on delete cascade, */
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   smallint        not null,
       sentence_number              smallint        not null,
       media_id                     int             not null, /* references media on delete cascade, */
       publish_day                  date            not null
);

create index story_sentence_words_story on story_sentence_words (stories_id, sentence_number);
create index story_sentence_words_dsm on story_sentence_words (publish_day, stem, media_id);
create index story_sentence_words_day on story_sentence_words(publish_day);
create index story_sentence_words_media_day on story_sentence_words (media_id, publish_day);
--ALTER TABLE  story_sentence_words ADD CONSTRAINT story_sentence_words_media_id_fkey FOREIGN KEY (media_id) REFERENCES media(media_id) ON DELETE CASCADE;
--ALTER TABLE  story_sentence_words ADD CONSTRAINT story_sentence_words_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES stories(stories_id) ON DELETE CASCADE;

create table daily_words (
       daily_words_id               serial          primary key,
       media_sets_id                int             not null, /* references media_sets */
       dashboard_topics_id          int             null, /* references dashboard_topics */
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   int             not null,
       publish_day                  date            not null
);

create index daily_words_media on daily_words(publish_day, media_sets_id, dashboard_topics_id, stem);
create index daily_words_count on daily_words(publish_day, media_sets_id, dashboard_topics_id, stem_count);
create index daily_words_publish_week on daily_words(week_start_date(publish_day));

create UNIQUE index daily_words_unique on daily_words(publish_day, media_sets_id, dashboard_topics_id, stem);
CREATE INDEX daily_words_day_topic ON daily_words USING btree (publish_day, dashboard_topics_id);

create table weekly_words (
       weekly_words_id              serial          primary key,
       media_sets_id                int             not null, /* references media_sets */
       dashboard_topics_id          int             null, /* references dashboard_topics */
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   int             not null,
       publish_week                 date            not null
);

create UNIQUE index weekly_words_media on weekly_words(publish_week, media_sets_id, dashboard_topics_id, stem);
create index weekly_words_count on weekly_words(publish_week, media_sets_id, dashboard_topics_id, stem_count);
CREATE INDEX weekly_words_publish_week on weekly_words(publish_week);
ALTER TABLE  weekly_words ADD CONSTRAINT weekly_words_publish_week_is_monday CHECK ( EXTRACT ( ISODOW from publish_week) = 1 );

create table top_500_weekly_words (
       top_500_weekly_words_id      serial          primary key,
       media_sets_id                int             not null, /* references media_sets on delete cascade, */
       dashboard_topics_id          int             null, /* references dashboard_topics */
       term                         varchar(256)    not null,
       stem                         varchar(256)    not null,
       stem_count                   int             not null,
       publish_week                 date            not null
);

create UNIQUE index top_500_weekly_words_media on top_500_weekly_words(publish_week, media_sets_id, dashboard_topics_id, stem);
create index top_500_weekly_words_media_null_dashboard on top_500_weekly_words (publish_week,media_sets_id, dashboard_topics_id) where dashboard_topics_id is null;
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

create view top_500_weekly_words_with_totals
    as select t5.*, tt5.total_count from top_500_weekly_words t5, total_top_500_weekly_words tt5
      where t5.media_sets_id = tt5.media_sets_id and t5.publish_week = tt5.publish_week and
        ( ( t5.dashboard_topics_id = tt5.dashboard_topics_id ) or
          ( t5.dashboard_topics_id is null and tt5.dashboard_topics_id is null ) );

create view top_500_weekly_words_normalized
    as select t5.stem, min(t5.term) as term, 
            ( least( 0.01, sum(t5.stem_count)::numeric / sum(t5.total_count)::numeric ) * count(*) ) as stem_count,
            t5.media_sets_id, t5.publish_week, t5.dashboard_topics_id
        from top_500_weekly_words_with_totals t5
        group by t5.stem, t5.publish_week, t5.media_sets_id, t5.dashboard_topics_id;
    
create table total_daily_words (
       total_daily_words_id         serial          primary key,
       media_sets_id                int             not null, /* references media_sets on delete cascade, */
       dashboard_topics_id           int            null, /* references dashboard_topics, */
       publish_day                  date            not null,
       total_count                  int             not null
);

create index total_daily_words_media_sets_id on total_daily_words (media_sets_id);
create index total_daily_words_media_sets_id_publish_day on total_daily_words (media_sets_id,publish_day);
create index total_daily_words_publish_day on total_daily_words (publish_day);
create index total_daily_words_publish_week on total_daily_words (week_start_date(publish_day));
CREATE UNIQUE INDEX total_daily_words_media_sets_id_dashboard_topic_id_publish_day ON total_daily_words (media_sets_id, dashboard_topics_id, publish_day);


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

create view daily_words_with_totals 
    as select d.*, t.total_count from daily_words d, total_daily_words t
      where d.media_sets_id = t.media_sets_id and d.publish_day = t.publish_day and
        ( ( d.dashboard_topics_id = t.dashboard_topics_id ) or
          ( d.dashboard_topics_id is null and t.dashboard_topics_id is null ) );
             
create schema stories_tags_map_media_sub_tables;

create table ssw_queue (
       stories_id                   int             not null,
       publish_date                 timestamp       not null,
       media_id                     int             not null
);

create view story_extracted_texts
       as select stories_id, 
       array_to_string(array_agg(download_text), ' ') as extracted_text 
       from (select * from downloads natural join download_texts order by downloads_id) 
       	    as downloads group by stories_id;

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
    daily_author_words_id serial primary key,
    authors_id integer not null references authors on delete cascade,
    media_sets_id integer not null references media_sets on delete cascade,
    term character varying(256) not null,
    stem character varying(256) not null,
    stem_count int not null,
    publish_day date not null
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
    LANGUAGE plpgsql;
--

select enum.enum_add( 'download_state', 'feed_error' );
DROP LANGUAGE IF EXISTS plperlu CASCADE;


            -- PostgreSQL sends notices about implicit keys that are being created,
            -- and the test suite takes them for warnings.
            SET client_min_messages=WARNING;

            -- "Full" stopwords
            DROP TABLE IF EXISTS stopwords_tiny;
            CREATE TABLE stopwords_tiny (
                stopwords_id SERIAL PRIMARY KEY,
                stopword VARCHAR(256) NOT NULL
            ) WITH (OIDS=FALSE);
            CREATE UNIQUE INDEX stopwords_tiny_stopword ON stopwords_tiny(stopword);

            -- Stopword stems
            DROP TABLE IF EXISTS stopword_stems_tiny;
            CREATE TABLE stopword_stems_tiny (
                stopword_stems_id SERIAL PRIMARY KEY,
                stopword_stem VARCHAR(256) NOT NULL
            ) WITH (OIDS=FALSE);
            CREATE UNIQUE INDEX stopword_stems_tiny_stopword_stem ON stopword_stems_tiny(stopword_stem);

            -- Reset the message level back to "notice".
            SET client_min_messages=NOTICE;

INSERT INTO stopwords_tiny (stopword) VALUES ('these'), ('you'), ('при'), ('both'), ('my'), ('как'), ('для'), ('Как'), ('дело'), ('what'), ('эти'), ('them'), ('there''s'), ('еще'), ('к'), ('лишь'), ('again'), ('деньги'), ('жизни'), ('why''s'), ('когда'), ('него'), ('of'), ('будет'), ('they''ll'), ('all'), ('being'), ('she'), ('nor'), ('за'), ('года'), ('when'), ('там'), ('where'), ('коп'), ('Я'), ('Если'), ('i''ve'), ('a'), ('you''ll'), ('would'), ('no'), ('по'), ('how''s'), ('мы'), ('нас'), ('они'), ('ни'), ('in'), ('лет'), ('wouldn''t'), ('i''ll'), ('very'), ('only'), ('своих'), ('me'), ('кто'), ('they''re'), ('by'), ('В'), ('can''t'), ('это'), ('мне'), ('let''s'), ('если'), ('этой'), ('hers'), ('after'), ('не'), ('doing'), ('am'), ('того'), ('свою'), ('А'), ('there'), ('weren''t'), ('couldn''t'), ('as'), ('который'), ('why'), ('Он'), ('itself'), ('ourselves'), ('между'), ('has'), ('время'), ('on'), ('i''d'), ('further'), ('won''t'), ('об'), ('out'), ('ему'), ('их'), ('aren''t'), ('И'), ('Но'), ('theirs'), ('ought'), ('более'), ('которые'), ('может'), ('так'), ('into'), ('чтобы'), ('и'), ('herself'), ('он'), ('ее'), ('below'), ('К'), ('during'), ('they''d'), ('then'), ('he''d'), ('we''re'), ('можно'), ('don''t'), ('it''s'), ('его'), ('few'), ('about'), ('down'), ('свои'), ('whom'), ('how'), ('wasn''t'), ('без'), ('those'), ('their'), ('other'), ('хотя'), ('up'), ('having'), ('где'), ('была'), ('Иллюстрация'), ('я'), ('been'), ('should'), ('what''s'), ('yourselves'), ('she''ll'), ('he'), ('которых'), ('несколько'), ('всех'), ('них'), ('until'), ('was'), ('which'), ('вот'), ('из'), ('didn''t'), ('пока'), ('if'), ('we''ll'), ('есть'), ('также'), ('himself'), ('him'), ('всего'), ('от'), ('только'), ('own'), ('doesn''t'), ('he''ll'), ('yours'), ('each'), ('у'), ('уже'), ('быть'), ('your'), ('but'), ('too'), ('and'), ('over'), ('теперь'), ('год'), ('shan''t'), ('о'), ('here''s'), ('ли'), ('через'), ('is'), ('have'), ('больше'), ('чем'), ('все'), ('we''d'), ('it'), ('им'), ('со'), ('who''s'), ('shouldn''t'), ('Однако'), ('were'), ('этот'), ('yourself'), ('you''d'), ('hadn''t'), ('off'), ('под'), ('сегодня'), ('году'), ('в'), ('было'), ('where''s'), ('По'), ('ours'), ('С'), ('том'), ('бы'), ('i''m'), ('даже'), ('человек'), ('haven''t'), ('myself'), ('they'), ('you''re'), ('same'), ('she''d'), ('У'), ('his'), ('i'), ('under'), ('she''s'), ('раз'), ('hasn''t'), ('through'), ('while'), ('themselves'), ('because'), ('нет'), ('руб'), ('сейчас'), ('просто'), ('cannot'), ('этом'), ('that'), ('not'), ('mustn''t'), ('our'), ('who'), ('после'), ('its'), ('этого'), ('были'), ('же'), ('себя'), ('Что'), ('some'), ('with'), ('here'), ('you''ve'), ('did'), ('do'), ('но'), ('we'), ('на'), ('что'), ('to'), ('from'), ('when''s'), ('тех'), ('она'), ('her'), ('any'), ('себе'), ('isn''t'), ('один'), ('На'), ('своей'), ('more'), ('an'), ('the'), ('against'), ('they''ve'), ('то'), ('до'), ('Это'), ('we''ve'), ('or'), ('could'), ('два'), ('тем'), ('does'), ('before'), ('this'), ('so'), ('once'), ('Не'), ('for'), ('а'), ('be'), ('such'), ('был'), ('очень'), ('most'), ('he''s'), ('во'), ('процентов'), ('are'), ('с'), ('above'), ('at'), ('день'), ('that''s'), ('здесь'), ('будут'), ('или'), ('had'), ('between'), ('than'), ('три');INSERT INTO stopword_stems_tiny (stopword_stem) VALUES ('these'), ('you'), ('both'), ('при'), ('my'), ('тепер'), ('как'), ('е'), ('для'), ('what'), ('them'), ('тольк'), ('dure'), ('к'), ('again'), ('of'), ('будет'), ('they''ll'), ('all'), ('хот'), ('she'), ('nor'), ('за'), ('when'), ('там'), ('where'), ('коп'), ('a'), ('you''ll'), ('would'), ('ег'), ('no'), ('по'), ('мы'), ('прост'), ('нас'), ('нескольк'), ('ни'), ('in'), ('лет'), ('wouldn''t'), ('i''ll'), ('me'), ('кто'), ('by'), ('себ'), ('однак'), ('can''t'), ('мне'), ('doe'), ('тог'), ('after'), ('не'), ('am'), ('we''r'), ('there'), ('weren''t'), ('as'), ('couldn''t'), ('itself'), ('has'), ('you''r'), ('i''v'), ('on'), ('i''d'), ('further'), ('won''t'), ('об'), ('межд'), ('out'), ('их'), ('aren''t'), ('ought'), ('может'), ('так'), ('into'), ('и'), ('herself'), ('он'), ('below'), ('эт'), ('they''d'), ('зде'), ('they''r'), ('нег'), ('then'), ('he''d'), ('уж'), ('don''t'), ('пок'), ('быт'), ('few'), ('about'), ('down'), ('whom'), ('лиш'), ('how'), ('whi'), ('wasn''t'), ('иллюстрац'), ('без'), ('those'), ('their'), ('other'), ('сегодн'), ('up'), ('onc'), ('где'), ('я'), ('been'), ('should'), ('ourselv'), ('такж'), ('she''ll'), ('he'), ('ещ'), ('всех'), ('них'), ('until'), ('ani'), ('was'), ('котор'), ('yourselv'), ('which'), ('вот'), ('из'), ('didn''t'), ('if'), ('we''ll'), ('himself'), ('him'), ('от'), ('abov'), ('own'), ('doesn''t'), ('he''ll'), ('each'), ('у'), ('your'), ('жизн'), ('but'), ('too'), ('and'), ('деньг'), ('год'), ('over'), ('shan''t'), ('о'), ('ли'), ('через'), ('is'), ('сво'), ('have'), ('чем'), ('все'), ('ест'), ('we''d'), ('даж'), ('it'), ('им'), ('со'), ('shouldn''t'), ('we''v'), ('were'), ('этот'), ('yourself'), ('you''d'), ('врем'), ('hadn''t'), ('off'), ('под'), ('becaus'), ('очен'), ('в'), ('когд'), ('том'), ('бы'), ('i''m'), ('человек'), ('haven''t'), ('myself'), ('they'), ('befor'), ('same'), ('she''d'), ('his'), ('i'), ('under'), ('раз'), ('ем'), ('hasn''t'), ('they''v'), ('through'), ('onli'), ('бол'), ('while'), ('you''v'), ('нет'), ('руб'), ('сейчас'), ('cannot'), ('that'), ('not'), ('mustn''t'), ('our'), ('who'), ('ил'), ('дел'), ('же'), ('veri'), ('some'), ('with'), ('here'), ('did'), ('do'), ('но'), ('we'), ('на'), ('что'), ('to'), ('from'), ('тех'), ('her'), ('isn''t'), ('один'), ('more'), ('an'), ('the'), ('against'), ('всег'), ('то'), ('до'), ('let'), ('or'), ('could'), ('два'), ('тем'), ('this'), ('themselv'), ('so'), ('for'), ('а'), ('be'), ('such'), ('был'), ('most'), ('во'), ('are'), ('ден'), ('с'), ('at'), ('есл'), ('чтоб'), ('будут'), ('had'), ('between'), ('посл'), ('than'), ('больш'), ('процент'), ('можн'), ('три');
            -- PostgreSQL sends notices about implicit keys that are being created,
            -- and the test suite takes them for warnings.
            SET client_min_messages=WARNING;

            -- "Full" stopwords
            DROP TABLE IF EXISTS stopwords_short;
            CREATE TABLE stopwords_short (
                stopwords_id SERIAL PRIMARY KEY,
                stopword VARCHAR(256) NOT NULL
            ) WITH (OIDS=FALSE);
            CREATE UNIQUE INDEX stopwords_short_stopword ON stopwords_short(stopword);

            -- Stopword stems
            DROP TABLE IF EXISTS stopword_stems_short;
            CREATE TABLE stopword_stems_short (
                stopword_stems_id SERIAL PRIMARY KEY,
                stopword_stem VARCHAR(256) NOT NULL
            ) WITH (OIDS=FALSE);
            CREATE UNIQUE INDEX stopword_stems_short_stopword_stem ON stopword_stems_short(stopword_stem);

            -- Reset the message level back to "notice".
            SET client_min_messages=NOTICE;

INSERT INTO stopwords_short (stopword) VALUES ('группа'), ('при'), ('знаю'), ('мог'), ('hat'), ('million'), ('как'), ('january'), ('stead'), ('serve'), ('thousand'), ('what'), ('завода'), ('light'), ('проект'), ('captain'), ('village'), ('дать'), ('gray'), ('века'), ('again'), ('happen'), ('molecule'), ('twenty'), ('недавно'), ('него'), ('of'), ('wall'), ('будет'), ('rule'), ('corn'), ('still'), ('wind'), ('cover'), ('winter'), ('will'), ('Пресс'), ('much'), ('срок'), ('imagine'), ('skin'), ('НЕ'), ('новой'), ('part'), ('board'), ('can'), ('exercise'), ('magnet'), ('where'), ('wild'), ('land'), ('главы'), ('doctor'), ('settle'), ('wait'), ('похоже'), ('одну'), ('Я'), ('favor'), ('left'), ('rain'), ('experiment'), ('bit'), ('быстро'), ('fact'), ('представителей'), ('первой'), ('дом'), ('новостей'), ('cause'), ('quite'), ('Когда'), ('knew'), ('crop'), ('only'), ('very'), ('понять'), ('me'), ('кто'), ('становится'), ('имеют'), ('by'), ('В'), ('moon'), ('thank'), ('которой'), ('inch'), ('type'), ('неделю'), ('fair'), ('мне'), ('cool'), ('если'), ('части'), ('этой'), ('problem'), ('check'), ('cow'), ('share'), ('часть'), ('beauty'), ('того'), ('death'), ('председателя'), ('А'), ('доме'), ('nature'), ('note'), ('свой'), ('мере'), ('there'), ('eye'), ('деле'), ('dry'), ('market'), ('решили'), ('работе'), ('ведь'), ('нужно'), ('fight'), ('stretch'), ('warm'), ('лучше'), ('перед'), ('лично'), ('делаем'), ('прямо'), ('gone'), ('около'), ('matter'), ('первых'), ('игры'), ('dictionary'), ('race'), ('ran'), ('south'), ('уровне'), ('trouble'), ('Причем'), ('quart'), ('strong'), ('свет'), ('их'), ('целом'), ('lift'), ('people'), ('top'), ('одной'), ('представители'), ('более'), ('т'), ('П'), ('dress'), ('главного'), ('массовой'), ('front'), ('meet'), ('чтобы'), ('seven'), ('второй'), ('certain'), ('и'), ('good'), ('он'), ('occur'), ('ее'), ('совершенно'), ('master'), ('vowel'), ('руководителей'), ('west'), ('fish'), ('самый'), ('Кроме'), ('едва'), ('ear'), ('then'), ('человека'), ('которым'), ('возможность'), ('возможности'), ('выборах'), ('hear'), ('segment'), ('truck'), ('сообщили'), ('От'), ('roll'), ('начале'), ('отдела'), ('state'), ('столько'), ('комментариев'), ('bear'), ('atom'), ('few'), ('pitch'), ('свои'), ('sand'), ('show'), ('told'), ('rub'), ('swim'), ('win'), ('партия'), ('ring'), ('Об'), ('steam'), ('bell'), ('трех'), ('heard'), ('york'), ('трудно'), ('руки'), ('suit'), ('flat'), ('wheel'), ('хотя'), ('direct'), ('wash'), ('even'), ('вопрос'), ('adriver'), ('finish'), ('amp'), ('famous'), ('crease'), ('Иллюстрация'), ('вместе'), ('власть'), ('mountain'), ('should'), ('утверждают'), ('против'), ('нибудь'), ('Во'), ('plane'), ('значит'), ('he'), ('sail'), ('fresh'), ('никогда'), ('них'), ('blood'), ('остается'), ('gather'), ('Вот'), ('оказались'), ('sat'), ('скорее'), ('команды'), ('почта'), ('городе'), ('come'), ('fly'), ('stone'), ('Эти'), ('Теперь'), ('получил'), ('rose'), ('bar'), ('least'), ('liquid'), ('river'), ('less'), ('от'), ('better'), ('fine'), ('keep'), ('разных'), ('эта'), ('deep'), ('этому'), ('фонда'), ('уже'), ('cgi'), ('interest'), ('chick'), ('supply'), ('факт'), ('dance'), ('final'), ('poor'), ('sun'), ('and'), ('июля'), ('год'), ('пять'), ('о'), ('six'), ('tall'), ('той'), ('говоря'), ('Д'), ('якобы'), ('условия'), ('spend'), ('surprise'), ('men'), ('watch'), ('сути'), ('миллион'), ('think'), ('удалось'), ('paper'), ('Через'), ('именно'), ('last'), ('danger'), ('build'), ('г'), ('food'), ('often'), ('Однако'), ('являетесь'), ('Еще'), ('равно'), ('next'), ('работает'), ('число'), ('square'), ('off'), ('thus'), ('связи'), ('horse'), ('сегодня'), ('similar'), ('году'), ('всегда'), ('bright'), ('С'), ('наши'), ('circle'), ('toward'), ('value'), ('summer'), ('первый'), ('бы'), ('contain'), ('evening'), ('push'), ('word'), ('такое'), ('hold'), ('лидер'), ('оказался'), ('слишком'), ('felt'), ('position'), ('hit'), ('indicate'), ('same'), ('придется'), ('deal'), ('city'), ('science'), ('У'), ('free'), ('person'), ('rich'), ('shell'), ('первого'), ('company'), ('crowd'), ('make'), ('operate'), ('сделаем'), ('industry'), ('big'), ('august'), ('участие'), ('другое'), ('allow'), ('happy'), ('nothing'), ('сейчас'), ('hour'), ('просто'), ('да'), ('руководство'), ('table'), ('развития'), ('that'), ('choose'), ('milk'), ('green'), ('tool'), ('после'), ('двух'), ('наших'), ('весьма'), ('sent'), ('line'), ('property'), ('yellow'), ('должен'), ('grew'), ('middle'), ('Таким'), ('тоже'), ('были'), ('mount'), ('предприятия'), ('рядом'), ('dollar'), ('shout'), ('среди'), ('же'), ('четыре'), ('some'), ('те'), ('комитета'), ('with'), ('result'), ('eat'), ('here'), ('находившегося'), ('тебе'), ('но'), ('born'), ('на'), ('говорят'), ('solution'), ('cat'), ('силы'), ('student'), ('real'), ('set'), ('teach'), ('country'), ('house'), ('считать'), ('документы'), ('кого'), ('wire'), ('ты'), ('job'), ('spot'), ('spread'), ('Александр'), ('кроме'), ('Рейтер'), ('glass'), ('against'), ('то'), ('конца'), ('yet'), ('числе'), ('need'), ('Это'), ('earth'), ('white'), ('or'), ('could'), ('wonder'), ('два'), ('does'), ('music'), ('дома'), ('какой'), ('ваш'), ('стать'), ('broke'), ('почти'), ('else'), ('port'), ('process'), ('первую'), ('engine'), ('роль'), ('глава'), ('separate'), ('busy'), ('Александра'), ('solve'), ('процентов'), ('НА'), ('young'), ('center'), ('делам'), ('сторону'), ('никак'), ('ныне'), ('bring'), ('insect'), ('день'), ('begin'), ('laugh'), ('connect'), ('link'), ('sight'), ('arrange'), ('прокуратуры'), ('feed'), ('новых'), ('between'), ('space'), ('Сергея'), ('либо'), ('reply'), ('Сейчас'), ('такие'), ('book'), ('времени'), ('три'), ('difficult'), ('sleep'), ('melody'), ('знает'), ('you'), ('Владимира'), ('both'), ('выяснилось'), ('put'), ('print'), ('пресс'), ('работу'), ('verb'), ('pound'), ('power'), ('весь'), ('Как'), ('discuss'), ('period'), ('substance'), ('сказать'), ('примеру'), ('claim'), ('old'), ('нам'), ('выше'), ('к'), ('интервью'), ('деньги'), ('though'), ('Фото'), ('отношении'), ('всю'), ('Вы'), ('girl'), ('all'), ('этим'), ('speed'), ('апреля'), ('за'), ('должно'), ('pass'), ('километров'), ('крупных'), ('branch'), ('наш'), ('площади'), ('thought'), ('offer'), ('spell'), ('would'), ('no'), ('наиболее'), ('д'), ('kill'), ('мы'), ('могла'), ('нас'), ('женщин'), ('работа'), ('red'), ('лет'), ('столице'), ('час'), ('salt'), ('valley'), ('total'), ('За'), ('cent'), ('иначе'), ('mind'), ('mine'), ('процента'), ('support'), ('www'), ('object'), ('women'), ('add'), ('invent'), ('Ни'), ('недели'), ('опять'), ('am'), ('вовсе'), ('get'), ('полностью'), ('huge'), ('control'), ('bat'), ('don'), ('считает'), ('этих'), ('свою'), ('car'), ('go'), ('своем'), ('hundred'), ('pattern'), ('кому'), ('фирмы'), ('мене'), ('довольно'), ('product'), ('why'), ('новый'), ('february'), ('Он'), ('complete'), ('делу'), ('Известиям'), ('know'), ('tree'), ('third'), ('заместитель'), ('миллиона'), ('знают'), ('годы'), ('которая'), ('время'), ('consider'), ('boy'), ('day'), ('break'), ('govern'), ('course'), ('дней'), ('людей'), ('wrote'), ('black'), ('agree'), ('силу'), ('ничего'), ('которые'), ('behind'), ('must'), ('wood'), ('Из'), ('ситуация'), ('так'), ('делать'), ('design'), ('body'), ('bad'), ('html'), ('легко'), ('которыми'), ('create'), ('able'), ('К'), ('Более'), ('during'), ('работавшую'), ('style'), ('bread'), ('path'), ('bottom'), ('впервые'), ('hole'), ('single'), ('observe'), ('probable'), ('района'), ('hot'), ('speak'), ('события'), ('since'), ('multiply'), ('self'), ('Все'), ('метров'), ('Алексей'), ('drink'), ('счет'), ('dad'), ('character'), ('сделать'), ('enter'), ('Его'), ('дает'), ('Пока'), ('rather'), ('other'), ('пор'), ('которого'), ('lady'), ('вроде'), ('ever'), ('немало'), ('эту'), ('gun'), ('age'), ('term'), ('ТАСС'), ('plain'), ('членов'), ('except'), ('call'), ('loud'), ('Этот'), ('специалисты'), ('При'), ('blog'), ('quotient'), ('excite'), ('smell'), ('народа'), ('могут'), ('comment'), ('данным'), ('говорит'), ('сто'), ('capital'), ('compare'), ('want'), ('сколько'), ('plural'), ('считают'), ('вот'), ('предприятий'), ('late'), ('steel'), ('key'), ('save'), ('средств'), ('foot'), ('view'), ('итоге'), ('Многие'), ('дальше'), ('plan'), ('lost'), ('always'), ('Потом'), ('glad'), ('tone'), ('следует'), ('ship'), ('appear'), ('open'), ('sit'), ('ИТАР'), ('noon'), ('touch'), ('tire'), ('usual'), ('Сегодня'), ('written'), ('gas'), ('populate'), ('ли'), ('area'), ('должны'), ('через'), ('hope'), ('forest'), ('прежнему'), ('точки'), ('die'), ('Даже'), ('have'), ('cook'), ('директора'), ('взгляд'), ('часа'), ('sheet'), ('organ'), ('принять'), ('помощь'), ('right'), ('talk'), ('dog'), ('necessary'), ('первые'), ('собственности'), ('одно'), ('led'), ('тысяч'), ('post'), ('Николай'), ('soft'), ('natural'), ('М'), ('опыт'), ('tail'), ('write'), ('суда'), ('guide'), ('stream'), ('всему'), ('том'), ('arrive'), ('человек'), ('постоянно'), ('card'), ('opposite'), ('посколько'), ('ready'), ('свое'), ('four'), ('ними'), ('прошлого'), ('м'), ('lone'), ('they'), ('мало'), ('центра'), ('помощью'), ('пятая'), ('cotton'), ('war'), ('fill'), ('две'), ('приходится'), ('fire'), ('select'), ('store'), ('образом'), ('последних'), ('track'), ('trip'), ('имени'), ('условиях'), ('компания'), ('office'), ('well'), ('wear'), ('поэтому'), ('meat'), ('прошлом'), ('Анатолий'), ('condition'), ('туда'), ('стали'), ('труда'), ('experience'), ('tiny'), ('самого'), ('travel'), ('who'), ('воскресение'), ('row'), ('ball'), ('sharp'), ('некоторые'), ('возможно'), ('этого'), ('caught'), ('котором'), ('Михаил'), ('grass'), ('region'), ('цены'), ('нашего'), ('вновь'), ('bank'), ('level'), ('simple'), ('train'), ('season'), ('провести'), ('friend'), ('нескольких'), ('словам'), ('главное'), ('do'), ('дни'), ('первым'), ('вести'), ('garden'), ('shoulder'), ('ней'), ('oh'), ('создать'), ('продукции'), ('stood'), ('бывший'), ('Так'), ('hair'), ('зам'), ('feet'), ('language'), ('suggest'), ('sea'), ('tie'), ('strange'), ('Только'), ('один'), ('давно'), ('своей'), ('театра'), ('месте'), ('меры'), ('Юрий'), ('decide'), ('hill'), ('the'), ('одним'), ('речь'), ('done'), ('вам'), ('начальника'), ('spring'), ('dream'), ('случай'), ('пути'), ('so'), ('право'), ('заявил'), ('стоит'), ('wife'), ('Не'), ('for'), ('meant'), ('конференции'), ('duck'), ('pick'), ('clean'), ('main'), ('near'), ('станет'), ('morning'), ('idea'), ('corner'), ('оказалось'), ('basic'), ('world'), ('такого'), ('акций'), ('фирма'), ('never'), ('ноября'), ('с'), ('blue'), ('drive'), ('straight'), ('early'), ('Здесь'), ('fig'), ('at'), ('joy'), ('equal'), ('silent'), ('команда'), ('достаточно'), ('Без'), ('надо'), ('mother'), ('trade'), ('город'), ('Именно'), ('hurry'), ('broad'), ('летний'), ('air'), ('road'), ('sid'), ('shine'), ('каким'), ('vary'), ('form'), ('shore'), ('baby'), ('кстате'), ('many'), ('buy'), ('fat'), ('slave'), ('помощи'), ('для'), ('give'), ('life'), ('над'), ('soldier'), ('дело'), ('subject'), ('место'), ('нельзя'), ('them'), ('последнее'), ('последний'), ('еще'), ('вообще'), ('moment'), ('хорошо'), ('лишь'), ('Чтобы'), ('жизни'), ('energy'), ('figure'), ('system'), ('story'), ('month'), ('true'), ('каждая'), ('fraction'), ('seed'), ('she'), ('december'), ('nor'), ('press'), ('lie'), ('года'), ('act'), ('when'), ('throw'), ('chief'), ('exact'), ('every'), ('количество'), ('февраля'), ('руководитель'), ('ground'), ('man'), ('закон'), ('provide'), ('жителей'), ('семьи'), ('коп'), ('Если'), ('мая'), ('way'), ('ранее'), ('neighbor'), ('a'), ('естественно'), ('coast'), ('меня'), ('july'), ('они'), ('http'), ('wrong'), ('in'), ('вице'), ('stand'), ('may'), ('корреспонденту'), ('начальник'), ('believe'), ('dark'), ('это'), ('care'), ('isn'), ('дня'), ('не'), ('livejournal'), ('заявление'), ('sky'), ('период'), ('нему'), ('друга'), ('рук'), ('spoke'), ('fruit'), ('премьера'), ('каждого'), ('heat'), ('история'), ('который'), ('Мы'), ('раньше'), ('numeral'), ('quick'), ('fast'), ('главный'), ('slow'), ('получили'), ('yes'), ('soil'), ('on'), ('map'), ('места'), ('shall'), ('об'), ('study'), ('sign'), ('colony'), ('base'), ('arm'), ('change'), ('Тем'), ('главным'), ('match'), ('хочет'), ('стал'), ('И'), ('чего'), ('необходимо'), ('walk'), ('november'), ('poem'), ('вы'), ('про'), ('hard'), ('family'), ('октября'), ('number'), ('visit'), ('обычно'), ('сообщил'), ('апрель'), ('case'), ('одна'), ('climb'), ('интересы'), ('proper'), ('могли'), ('никаких'), ('mouth'), ('Ну'), ('лица'), ('syllable'), ('remember'), ('процесс'), ('ago'), ('Борис'), ('silver'), ('руках'), ('now'), ('little'), ('жить'), ('shoe'), ('районе'), ('surface'), ('уж'), ('test'), ('produce'), ('slip'), ('точнее'), ('blow'), ('step'), ('его'), ('mass'), ('down'), ('about'), ('column'), ('how'), ('новые'), ('прежде'), ('суббота'), ('event'), ('без'), ('those'), ('prove'), ('О'), ('Тогда'), ('their'), ('найти'), ('scale'), ('best'), ('кстати'), ('ним'), ('chart'), ('wing'), ('Среди'), ('декабря'), ('up'), ('oxygen'), ('где'), ('была'), ('правда'), ('dead'), ('я'), ('king'), ('say'), ('together'), ('log'), ('machine'), ('Г'), ('месяца'), ('original'), ('несколько'), ('встречи'), ('score'), ('всех'), ('question'), ('Уже'), ('своими'), ('point'), ('hand'), ('animal'), ('конечно'), ('практически'), ('Ю'), ('многие'), ('взять'), ('самой'), ('иметь'), ('cold'), ('which'), ('из'), ('любая'), ('пока'), ('Ассошиэйтед'), ('far'), ('есть'), ('Нет'), ('также'), ('всего'), ('suffix'), ('только'), ('flow'), ('own'), ('одновременно'), ('одном'), ('самое'), ('sound'), ('also'), ('egg'), ('у'), ('должна'), ('Дело'), ('путь'), ('rope'), ('equate'), ('мировой'), ('east'), ('быть'), ('жизнь'), ('своим'), ('pull'), ('continent'), ('possible'), ('but'), ('too'), ('Л'), ('сборной'), ('small'), ('потому'), ('теперь'), ('утверждает'), ('over'), ('сотрудников'), ('divide'), ('kept'), ('is'), ('found'), ('coat'), ('color'), ('сами'), ('dear'), ('больше'), ('все'), ('Есть'), ('политики'), ('событий'), ('station'), ('своего'), ('им'), ('anger'), ('art'), ('стало'), ('одного'), ('местных'), ('женщины'), ('главе'), ('Она'), ('которую'), ('length'), ('Сергей'), ('многих'), ('особенно'), ('game'), ('х'), ('metal'), ('этот'), ('наша'), ('were'), ('law'), ('pay'), ('После'), ('каких'), ('под'), ('производства'), ('вас'), ('like'), ('собой'), ('turn'), ('got'), ('Ведь'), ('past'), ('collect'), ('iron'), ('в'), ('было'), ('сих'), ('camp'), ('говорится'), ('cost'), ('другой'), ('своему'), ('seat'), ('ask'), ('даже'), ('receive'), ('качестве'), ('нем'), ('подобная'), ('gave'), ('thick'), ('миллиарда'), ('fear'), ('несмотря'), ('especially'), ('include'), ('Кстати'), ('run'), ('cut'), ('пост'), ('plant'), ('low'), ('his'), ('мире'), ('ссылка'), ('времена'), ('under'), ('answer'), ('течение'), ('слова'), ('Е'), ('through'), ('oil'), ('while'), ('Правда'), ('please'), ('которому'), ('руб'), ('rise'), ('move'), ('held'), ('clear'), ('take'), ('видимо'), ('our'), ('triangle'), ('нынешнего'), ('сентября'), ('например'), ('резко'), ('января'), ('вопросы'), ('шесть'), ('долго'), ('вся'), ('farm'), ('join'), ('дел'), ('lake'), ('minute'), ('себя'), ('й'), ('rnd'), ('пришлось'), ('brother'), ('состоянии'), ('любой'), ('we'), ('hasn'), ('notice'), ('face'), ('что'), ('to'), ('group'), ('права'), ('говорил'), ('gentle'), ('будто'), ('motion'), ('включая'), ('school'), ('тех'), ('home'), ('depend'), ('ease'), ('себе'), ('radio'), ('large'), ('На'), ('Кто'), ('unit'), ('consonant'), ('тысячи'), ('try'), ('sense'), ('ocean'), ('an'), ('made'), ('bed'), ('земли'), ('page'), ('neck'), ('говорить'), ('работать'), ('fell'), ('aren'), ('людям'), ('центре'), ('soon'), ('тем'), ('rock'), ('read'), ('Можно'), ('случае'), ('каждый'), ('системы'), ('средства'), ('field'), ('всё'), ('once'), ('дал'), ('производство'), ('enemy'), ('а'), ('grand'), ('jump'), ('end'), ('paint'), ('miss'), ('such'), ('shape'), ('такая'), ('nation'), ('столь'), ('reach'), ('window'), ('degree'), ('оказалась'), ('ответ'), ('are'), ('деятельности'), ('часто'), ('оно'), ('ходе'), ('деятельность'), ('long'), ('great'), ('current'), ('edge'), ('касается'), ('градусов'), ('particular'), ('hunt'), ('guess'), ('много'), ('example'), ('yard'), ('than'), ('determine'), ('отличие'), ('force'), ('таких'), ('june'), ('just'), ('measure'), ('present'), ('catch'), ('нее'), ('these'), ('Андрей'), ('решения'), ('floor'), ('my'), ('fun'), ('heavy'), ('took'), ('see'), ('north'), ('марта'), ('позиции'), ('didn'), ('е'), ('снова'), ('pose'), ('expect'), ('внимание'), ('symbol'), ('history'), ('night'), ('fit'), ('эти'), ('letter'), ('люди'), ('движения'), ('ей'), ('таки'), ('территории'), ('метра'), ('follow'), ('последние'), ('several'), ('piece'), ('когда'), ('rest'), ('вдруг'), ('time'), ('round'), ('Конечно'), ('Их'), ('woman'), ('Нью'), ('weather'), ('большинство'), ('степени'), ('дела'), ('десять'), ('said'), ('afraid'), ('draw'), ('common'), ('either'), ('назад'), ('там'), ('paragraph'), ('son'), ('human'), ('lead'), ('bin'), ('chair'), ('Там'), ('chord'), ('по'), ('квартиры'), ('copy'), ('явно'), ('record'), ('practice'), ('might'), ('ни'), ('order'), ('вряд'), ('sing'), ('locate'), ('зрения'), ('parent'), ('correct'), ('своих'), ('тот'), ('операции'), ('сказал'), ('невозможно'), ('Известия'), ('teeth'), ('feel'), ('Поэтому'), ('general'), ('ряд'), ('минут'), ('whose'), ('century'), ('after'), ('специалистов'), ('phrase'), ('nine'), ('cell'), ('mile'), ('То'), ('quiet'), ('five'), ('heart'), ('cry'), ('back'), ('water'), ('as'), ('clock'), ('результате'), ('очередь'), ('примерно'), ('между'), ('represent'), ('has'), ('string'), ('всей'), ('Хотя'), ('премьер'), ('До'), ('края'), ('list'), ('тому'), ('out'), ('Грозном'), ('second'), ('комиссии'), ('reason'), ('ему'), ('центр'), ('element'), ('куда'), ('Но'), ('skill'), ('tell'), ('вполне'), ('seem'), ('came'), ('repeat'), ('love'), ('wave'), ('leave'), ('leg'), ('october'), ('может'), ('section'), ('protect'), ('сотрудники'), ('size'), ('kind'), ('fall'), ('далеко'), ('группы'), ('проблем'), ('вокруг'), ('виде'), ('конце'), ('августа'), ('sure'), ('work'), ('instrument'), ('самым'), ('side'), ('pretty'), ('subtract'), ('Виктор'), ('поскольку'), ('действий'), ('можно'), ('месяцев'), ('действительно'), ('street'), ('стала'), ('town'), ('Впрочем'), ('Один'), ('сама'), ('sell'), ('whole'), ('некоторого'), ('cloud'), ('тогда'), ('went'), ('письмо'), ('информацию'), ('new'), ('flower'), ('sentence'), ('enough'), ('raise'), ('войск'), ('whether'), ('I'), ('continue'), ('modern'), ('существует'), ('three'), ('send'), ('clothe'), ('band'), ('бывшего'), ('первая'), ('Эта'), ('смерти'), ('short'), ('develop'), ('gold'), ('april'), ('use'), ('частности'), ('been'), ('sugar'), ('week'), ('apple'), ('которых'), ('noun'), ('mix'), ('стате'), ('until'), ('was'), ('chance'), ('некоторых'), ('nose'), ('лиц'), ('Может'), ('instant'), ('которое'), ('two'), ('if'), ('him'), ('тонн'), ('wide'), ('является'), ('temperature'), ('проблемы'), ('пяти'), ('each'), ('count'), ('finger'), ('carry'), ('name'), ('раза'), ('Почему'), ('сообща'), ('wish'), ('doesn'), ('your'), ('door'), ('tube'), ('друг'), ('quot'), ('Они'), ('start'), ('box'), ('learn'), ('основном'), ('такой'), ('известно'), ('Между'), ('bone'), ('большой'), ('чаще'), ('Да'), ('вторая'), ('го'), ('самые'), ('часов'), ('чем'), ('решил'), ('distant'), ('it'), ('со'), ('ситуацию'), ('Б'), ('правило'), ('уровень'), ('voice'), ('differ'), ('charge'), ('поводу'), ('четырех'), ('самом'), ('require'), ('electric'), ('сразу'), ('ясно'), ('порядке'), ('фирм'), ('органы'), ('таким'), ('special'), ('однако'), ('march'), ('ride'), ('произошло'), ('href'), ('wouldn'), ('блог'), ('weight'), ('почему'), ('safe'), ('По'), ('head'), ('star'), ('sister'), ('describe'), ('full'), ('burn'), ('father'), ('ice'), ('smile'), ('наконец'), ('тут'), ('half'), ('lot'), ('money'), ('close'), ('воды'), ('us'), ('прошла'), ('boat'), ('чуть'), ('кажется'), ('раз'), ('mean'), ('brought'), ('shop'), ('began'), ('thing'), ('block'), ('eight'), ('нет'), ('АО'), ('stick'), ('этом'), ('другом'), ('forward'), ('меньше'), ('grow'), ('нашей'), ('bird'), ('отношения'), ('double'), ('mark'), ('listen'), ('beat'), ('bought'), ('brown'), ('какие'), ('нового'), ('сумму'), ('участников'), ('rail'), ('one'), ('проблема'), ('Что'), ('июня'), ('имеет'), ('division'), ('did'), ('range'), ('drop'), ('find'), ('ten'), ('Н'), ('никто'), ('имя'), ('города'), ('from'), ('месяц'), ('planet'), ('потом'), ('root'), ('method'), ('действия'), ('она'), ('prepare'), ('her'), ('днях'), ('положение'), ('вместо'), ('effect'), ('any'), ('сам'), ('party'), ('находится'), ('идет'), ('stay'), ('области'), ('всем'), ('perhaps'), ('самых'), ('live'), ('decimal'), ('Для'), ('more'), ('year'), ('material'), ('совсем'), ('search'), ('cross'), ('island'), ('момент'), ('до'), ('sudden'), ('speech'), ('другие'), ('затем'), ('pair'), ('let'), ('this'), ('before'), ('менее'), ('success'), ('lay'), ('очередной'), ('song'), ('получить'), ('among'), ('система'), ('be'), ('был'), ('class'), ('мой'), ('team'), ('major'), ('september'), ('очень'), ('most'), ('во'), ('скажем'), ('place'), ('room'), ('look'), ('high'), ('saw'), ('хоть'), ('above'), ('help'), ('другим'), ('здесь'), ('других'), ('полтора'), ('picture'), ('будут'), ('или'), ('сделал'), ('desert'), ('had'), ('first'), ('stop'), ('Известий'), ('thin'), ('рода'), ('play'), ('стороны'), ('snow'), ('происходит'), ('Мне'), ('начала'), ('ситуации'), ('shouldn'), ('noise');INSERT INTO stopword_stems_short (stopword_stem) VALUES ('при'), ('мог'), ('hat'), ('million'), ('как'), ('деятельн'), ('пришл'), ('stead'), ('thousand'), ('what'), ('light'), ('perhap'), ('проект'), ('captain'), ('gray'), ('happen'), ('again'), ('легк'), ('of'), ('wall'), ('будет'), ('взят'), ('rule'), ('serv'), ('corn'), ('still'), ('wind'), ('cover'), ('winter'), ('поч'), ('will'), ('much'), ('skin'), ('срок'), ('part'), ('board'), ('теб'), ('can'), ('wild'), ('where'), ('magnet'), ('land'), ('юр'), ('отношен'), ('wait'), ('doctor'), ('favor'), ('left'), ('rain'), ('bit'), ('fact'), ('недел'), ('письм'), ('дом'), ('впроч'), ('knew'), ('crop'), ('уда'), ('me'), ('кто'), ('имеют'), ('by'), ('moon'), ('thank'), ('inch'), ('type'), ('могл'), ('fair'), ('мне'), ('pleas'), ('alway'), ('cool'), ('фот'), ('problem'), ('share'), ('cow'), ('check'), ('народ'), ('полтор'), ('death'), ('complet'), ('note'), ('отлич'), ('there'), ('eye'), ('market'), ('fight'), ('должн'), ('stretch'), ('warm'), ('strang'), ('перед'), ('gone'), ('наход'), ('matter'), ('ran'), ('race'), ('south'), ('внов'), ('strong'), ('quart'), ('свет'), ('их'), ('lift'), ('top'), ('novemb'), ('след'), ('т'), ('dress'), ('front'), ('meet'), ('seven'), ('кром'), ('certain'), ('и'), ('charg'), ('реч'), ('good'), ('скаж'), ('occur'), ('он'), ('vowel'), ('master'), ('west'), ('fish'), ('конференц'), ('then'), ('ear'), ('vari'), ('hear'), ('завод'), ('octob'), ('truck'), ('segment'), ('roll'), ('state'), ('bear'), ('atom'), ('pitch'), ('few'), ('тасс'), ('представител'), ('sand'), ('creas'), ('told'), ('show'), ('win'), ('swim'), ('rub'), ('очеред'), ('ring'), ('пут'), ('steam'), ('bell'), ('трех'), ('york'), ('heard'), ('suit'), ('найт'), ('wheel'), ('flat'), ('информац'), ('wash'), ('direct'), ('even'), ('finish'), ('вопрос'), ('famous'), ('amp'), ('posit'), ('should'), ('mountain'), ('слов'), ('pretti'), ('divis'), ('plane'), ('позиц'), ('he'), ('sail'), ('fresh'), ('blood'), ('них'), ('gather'), ('качеств'), ('sat'), ('рейтер'), ('сдела'), ('постоя'), ('корреспондент'), ('come'), ('stone'), ('necessari'), ('rose'), ('январ'), ('bar'), ('least'), ('liquid'), ('river'), ('less'), ('некотор'), ('наибол'), ('keep'), ('fine'), ('better'), ('от'), ('б'), ('deep'), ('parti'), ('cgi'), ('interest'), ('chick'), ('факт'), ('sun'), ('poor'), ('final'), ('жизн'), ('and'), ('вовс'), ('сторон'), ('chanc'), ('год'), ('requir'), ('tall'), ('six'), ('о'), ('dri'), ('личн'), ('spend'), ('помощ'), ('men'), ('watch'), ('практическ'), ('миллион'), ('сво'), ('think'), ('paper'), ('хорош'), ('октябр'), ('last'), ('danger'), ('build'), ('notic'), ('food'), ('г'), ('often'), ('несмотр'), ('villag'), ('next'), ('off'), ('thus'), ('поскольк'), ('созда'), ('similar'), ('театр'), ('cloth'), ('bright'), ('фонд'), ('дальш'), ('toward'), ('работ'), ('summer'), ('собствен'), ('бы'), ('contain'), ('чащ'), ('push'), ('word'), ('hold'), ('лидер'), ('нич'), ('arrang'), ('главн'), ('felt'), ('same'), ('hit'), ('прежн'), ('deal'), ('free'), ('person'), ('natur'), ('rich'), ('shell'), ('деся'), ('crowd'), ('make'), ('cri'), ('нача'), ('onli'), ('почт'), ('big'), ('august'), ('allow'), ('degre'), ('hour'), ('сейчас'), ('да'), ('that'), ('milk'), ('green'), ('существ'), ('copi'), ('tool'), ('excit'), ('sent'), ('двух'), ('оказа'), ('yellow'), ('line'), ('grew'), ('зна'), ('комисс'), ('документ'), ('частност'), ('mount'), ('materi'), ('dollar'), ('shout'), ('probabl'), ('же'), ('veri'), ('some'), ('with'), ('те'), ('result'), ('here'), ('eat'), ('born'), ('но'), ('на'), ('cat'), ('выш'), ('student'), ('производств'), ('борис'), ('довольн'), ('teach'), ('set'), ('real'), ('комментар'), ('wire'), ('сумм'), ('simpl'), ('spot'), ('job'), ('ты'), ('spread'), ('приня'), ('декабр'), ('glass'), ('circl'), ('against'), ('всег'), ('жит'), ('yet'), ('то'), ('мал'), ('need'), ('грозн'), ('white'), ('earth'), ('or'), ('oper'), ('wonder'), ('could'), ('music'), ('два'), ('сред'), ('количеств'), ('ваш'), ('compar'), ('broke'), ('januari'), ('port'), ('process'), ('surpris'), ('специалист'), ('young'), ('center'), ('voic'), ('никак'), ('insect'), ('bring'), ('laugh'), ('begin'), ('есл'), ('придет'), ('connect'), ('sight'), ('link'), ('feed'), ('between'), ('посл'), ('раньш'), ('space'), ('можн'), ('book'), ('глав'), ('difficult'), ('три'), ('sleep'), ('stori'), ('якоб'), ('знает'), ('you'), ('both'), ('put'), ('print'), ('пресс'), ('verb'), ('pound'), ('power'), ('discuss'), ('сообщ'), ('команд'), ('period'), ('claim'), ('тольк'), ('old'), ('нам'), ('к'), ('though'), ('всю'), ('girl'), ('all'), ('хот'), ('livejourn'), ('speed'), ('либ'), ('за'), ('pass'), ('игр'), ('branch'), ('locat'), ('heavi'), ('июл'), ('наш'), ('политик'), ('ситуац'), ('thought'), ('bodi'), ('would'), ('spell'), ('offer'), ('no'), ('kill'), ('д'), ('мы'), ('septemb'), ('earli'), ('нас'), ('прост'), ('нескольк'), ('женщин'), ('работа'), ('red'), ('sentenc'), ('лет'), ('salt'), ('час'), ('valley'), ('вид'), ('total'), ('мо'), ('cent'), ('mine'), ('mind'), ('support'), ('women'), ('object'), ('www'), ('add'), ('minut'), ('заяв'), ('invent'), ('doe'), ('стат'), ('достаточн'), ('тог'), ('numer'), ('am'), ('get'), ('степен'), ('труд'), ('control'), ('huge'), ('bat'), ('don'), ('car'), ('go'), ('pattern'), ('миров'), ('believ'), ('product'), ('пот'), ('surfac'), ('долж'), ('tree'), ('know'), ('industri'), ('third'), ('adriv'), ('приход'), ('знают'), ('boy'), ('day'), ('встреч'), ('перв'), ('break'), ('govern'), ('wrote'), ('вмест'), ('especi'), ('black'), ('behind'), ('must'), ('wood'), ('tri'), ('так'), ('design'), ('bad'), ('html'), ('cours'), ('опя'), ('charact'), ('style'), ('особен'), ('зде'), ('path'), ('bread'), ('bottom'), ('caus'), ('hole'), ('hot'), ('speak'), ('everi'), ('self'), ('власт'), ('produc'), ('пок'), ('естествен'), ('сраз'), ('мест'), ('drink'), ('dad'), ('счет'), ('whi'), ('иллюстрац'), ('enter'), ('дает'), ('развит'), ('rather'), ('other'), ('пор'), ('suppli'), ('popul'), ('ever'), ('gun'), ('age'), ('term'), ('plain'), ('уровн'), ('hurri'), ('call'), ('except'), ('loud'), ('quit'), ('ког'), ('hous'), ('nois'), ('quotient'), ('blog'), ('smell'), ('ani'), ('comment'), ('могут'), ('substanc'), ('сто'), ('прокуратур'), ('want'), ('лучш'), ('plural'), ('busi'), ('вот'), ('скор'), ('late'), ('steel'), ('key'), ('save'), ('view'), ('foot'), ('средств'), ('abov'), ('repres'), ('middl'), ('plan'), ('lost'), ('выбор'), ('glad'), ('скольк'), ('tone'), ('ship'), ('sit'), ('open'), ('appear'), ('нынешн'), ('разн'), ('scienc'), ('touch'), ('noon'), ('usual'), ('tire'), ('деньг'), ('written'), ('gas'), ('area'), ('ли'), ('forest'), ('hope'), ('через'), ('die'), ('член'), ('littl'), ('have'), ('cook'), ('весьм'), ('даж'), ('взгляд'), ('sheet'), ('organ'), ('нов'), ('right'), ('talk'), ('dog'), ('кажд'), ('серге'), ('сказа'), ('числ'), ('led'), ('тысяч'), ('post'), ('soft'), ('прям'), ('предприят'), ('tail'), ('имен'), ('write'), ('долг'), ('studi'), ('stream'), ('том'), ('doubl'), ('обычн'), ('card'), ('человек'), ('мног'), ('consid'), ('four'), ('they'), ('lone'), ('м'), ('жител'), ('provid'), ('итог'), ('war'), ('cotton'), ('fill'), ('интерв'), ('fire'), ('две'), ('действ'), ('сборн'), ('i'), ('select'), ('fli'), ('нью'), ('градус'), ('store'), ('trip'), ('track'), ('well'), ('wear'), ('июн'), ('meat'), ('нибуд'), ('пробл'), ('итар'), ('ассошиэйтед'), ('поэт'), ('hundr'), ('порядк'), ('who'), ('travel'), ('row'), ('sharp'), ('ball'), ('caught'), ('прежд'), ('region'), ('grass'), ('случа'), ('bank'), ('level'), ('train'), ('abl'), ('season'), ('friend'), ('receiv'), ('do'), ('дни'), ('состоян'), ('contin'), ('shoulder'), ('garden'), ('ран'), ('oh'), ('течен'), ('феврал'), ('stood'), ('hair'), ('продукц'), ('зам'), ('feet'), ('suggest'), ('tie'), ('sea'), ('интерес'), ('один'), ('enemi'), ('меньш'), ('ход'), ('babi'), ('апрел'), ('the'), ('hill'), ('done'), ('одн'), ('вам'), ('далек'), ('spring'), ('dream'), ('комитет'), ('so'), ('capit'), ('wife'), ('for'), ('meant'), ('pick'), ('duck'), ('руководител'), ('clean'), ('виктор'), ('near'), ('main'), ('похож'), ('станет'), ('noth'), ('правд'), ('idea'), ('corner'), ('basic'), ('суббот'), ('world'), ('never'), ('с'), ('straight'), ('drive'), ('blue'), ('дат'), ('at'), ('fig'), ('piec'), ('silent'), ('equal'), ('joy'), ('зат'), ('trade'), ('mother'), ('город'), ('групп'), ('broad'), ('road'), ('air'), ('multipli'), ('sid'), ('shine'), ('tini'), ('form'), ('shore'), ('buy'), ('fat'), ('slave'), ('для'), ('give'), ('life'), ('sens'), ('над'), ('soldier'), ('subject'), ('them'), ('ма'), ('вперв'), ('moment'), ('arriv'), ('систем'), ('реш'), ('tabl'), ('system'), ('month'), ('true'), ('fraction'), ('seed'), ('she'), ('nor'), ('press'), ('juli'), ('lie'), ('равн'), ('воскресен'), ('act'), ('when'), ('throw'), ('chief'), ('exact'), ('ground'), ('man'), ('закон'), ('eas'), ('коп'), ('туд'), ('way'), ('neighbor'), ('a'), ('резк'), ('coast'), ('площад'), ('http'), ('wrong'), ('in'), ('вест'), ('stand'), ('may'), ('сил'), ('себ'), ('оп'), ('начальник'), ('прот'), ('dark'), ('слишк'), ('care'), ('isn'), ('дня'), ('не'), ('forc'), ('creat'), ('describ'), ('sky'), ('имет'), ('период'), ('twenti'), ('известн'), ('edg'), ('рук'), ('spoke'), ('fruit'), ('heat'), ('singl'), ('quick'), ('fast'), ('одновремен'), ('slow'), ('yes'), ('врод'), ('акц'), ('separ'), ('soil'), ('exercis'), ('languag'), ('част'), ('август'), ('on'), ('map'), ('основн'), ('shall'), ('gentl'), ('об'), ('sign'), ('межд'), ('base'), ('arm'), ('carri'), ('большинств'), ('match'), ('хочет'), ('стал'), ('род'), ('chang'), ('walk'), ('valu'), ('poem'), ('temperatur'), ('вы'), ('про'), ('hard'), ('number'), ('visit'), ('case'), ('exampl'), ('тогд'), ('сут'), ('climb'), ('proper'), ('mouth'), ('смерт'), ('стольк'), ('процесс'), ('ago'), ('истор'), ('земл'), ('silver'), ('нег'), ('now'), ('shoe'), ('уж'), ('test'), ('ве'), ('slip'), ('blow'), ('morn'), ('mani'), ('step'), ('mass'), ('down'), ('about'), ('column'), ('получ'), ('how'), ('произошл'), ('event'), ('территор'), ('continu'), ('без'), ('those'), ('prove'), ('their'), ('scale'), ('best'), ('ним'), ('chart'), ('wing'), ('сегодн'), ('снов'), ('up'), ('oxygen'), ('onc'), ('где'), ('dead'), ('я'), ('king'), ('say'), ('decim'), ('log'), ('такж'), ('рол'), ('ещ'), ('score'), ('energi'), ('всех'), ('condit'), ('question'), ('point'), ('hand'), ('каса'), ('cold'), ('which'), ('окол'), ('из'), ('far'), ('measur'), ('suffix'), ('flow'), ('own'), ('анатол'), ('egg'), ('also'), ('sound'), ('зрен'), ('у'), ('rope'), ('east'), ('pull'), ('but'), ('too'), ('small'), ('electr'), ('over'), ('kept'), ('оста'), ('found'), ('is'), ('люб'), ('coat'), ('color'), ('dear'), ('район'), ('все'), ('station'), ('art'), ('anger'), ('им'), ('говор'), ('length'), ('sinc'), ('кра'), ('game'), ('х'), ('metal'), ('were'), ('этот'), ('law'), ('pay'), ('под'), ('like'), ('вас'), ('нужн'), ('turn'), ('got'), ('ком'), ('движен'), ('collect'), ('past'), ('iron'), ('мер'), ('в'), ('camp'), ('сих'), ('поня'), ('когд'), ('cost'), ('дне'), ('ladi'), ('seat'), ('ask'), ('куд'), ('прав'), ('gave'), ('нем'), ('thick'), ('решен'), ('befor'), ('fear'), ('руководств'), ('cut'), ('run'), ('трудн'), ('март'), ('plant'), ('пост'), ('his'), ('low'), ('област'), ('agre'), ('соб'), ('triangl'), ('under'), ('answer'), ('видим'), ('oil'), ('through'), ('while'), ('вниман'), ('руб'), ('held'), ('move'), ('rise'), ('syllabl'), ('clear'), ('п'), ('take'), ('our'), ('например'), ('новост'), ('danc'), ('вся'), ('farm'), ('join'), ('утвержда'), ('lake'), ('дел'), ('й'), ('rnd'), ('brother'), ('hasn'), ('we'), ('face'), ('group'), ('to'), ('что'), ('possibl'), ('motion'), ('school'), ('home'), ('тех'), ('быстр'), ('нын'), ('depend'), ('radio'), ('unit'), ('инач'), ('solv'), ('an'), ('ocean'), ('дан'), ('made'), ('bed'), ('engin'), ('page'), ('neck'), ('aren'), ('fell'), ('выясн'), ('орга'), ('soon'), ('coloni'), ('read'), ('rock'), ('тем'), ('field'), ('всё'), ('результат'), ('дал'), ('grand'), ('а'), ('decemb'), ('origin'), ('jump'), ('end'), ('кажет'), ('paint'), ('miss'), ('such'), ('shape'), ('nation'), ('reach'), ('window'), ('are'), ('ответ'), ('ден'), ('countri'), ('beauti'), ('current'), ('great'), ('long'), ('сентябр'), ('includ'), ('чтоб'), ('guess'), ('hunt'), ('particular'), ('начал'), ('yard'), ('than'), ('solut'), ('just'), ('june'), ('век'), ('present'), ('catch'), ('вед'), ('these'), ('floor'), ('my'), ('fun'), ('see'), ('took'), ('тепер'), ('north'), ('offic'), ('didn'), ('е'), ('суд'), ('expect'), ('pose'), ('symbol'), ('четыр'), ('нема'), ('fit'), ('night'), ('всегд'), ('никогд'), ('letter'), ('settl'), ('happi'), ('dure'), ('втор'), ('follow'), ('rest'), ('time'), ('вдруг'), ('участник'), ('round'), ('woman'), ('weather'), ('дела'), ('said'), ('draw'), ('afraid'), ('андр'), ('точн'), ('either'), ('common'), ('заявлен'), ('там'), ('назад'), ('pictur'), ('очередн'), ('paragraph'), ('lead'), ('human'), ('son'), ('chair'), ('bin'), ('ег'), ('chord'), ('по'), ('might'), ('record'), ('order'), ('ни'), ('вряд'), ('sing'), ('пят'), ('correct'), ('parent'), ('крупн'), ('figur'), ('тот'), ('однак'), ('шест'), ('feel'), ('teeth'), ('вод'), ('general'), ('квартир'), ('ряд'), ('whose'), ('минут'), ('peopl'), ('недавн'), ('after'), ('guid'), ('cell'), ('nine'), ('phrase'), ('mile'), ('quiet'), ('heart'), ('five'), ('back'), ('услов'), ('observ'), ('water'), ('conson'), ('образ'), ('as'), ('clock'), ('счита'), ('readi'), ('метр'), ('has'), ('string'), ('уровен'), ('dictionari'), ('премьер'), ('list'), ('out'), ('second'), ('reason'), ('возможн'), ('центр'), ('element'), ('skill'), ('practic'), ('tell'), ('came'), ('seem'), ('melodi'), ('love'), ('repeat'), ('wave'), ('тон'), ('leg'), ('может'), ('protect'), ('section'), ('size'), ('миллиард'), ('kind'), ('fall'), ('виц'), ('времен'), ('choos'), ('проблем'), ('вокруг'), ('конечн'), ('citi'), ('явля'), ('sure'), ('эт'), ('famili'), ('instrument'), ('work'), ('чут'), ('side'), ('подобн'), ('subtract'), ('divid'), ('заместител'), ('street'), ('prepar'), ('town'), ('цел'), ('sell'), ('примерн'), ('whole'), ('cloud'), ('нельз'), ('went'), ('быт'), ('flower'), ('new'), ('сем'), ('лиш'), ('enough'), ('повод'), ('войск'), ('необходим'), ('whether'), ('связ'), ('modern'), ('three'), ('februari'), ('send'), ('band'), ('никола'), ('develop'), ('short'), ('gold'), ('use'), ('april'), ('been'), ('полност'), ('sugar'), ('week'), ('пример'), ('noun'), ('properti'), ('sever'), ('mix'), ('until'), ('was'), ('nose'), ('ссылк'), ('алекс'), ('лиц'), ('котор'), ('включ'), ('equat'), ('давн'), ('председател'), ('instant'), ('two'), ('if'), ('ноябр'), ('compani'), ('him'), ('wide'), ('прошл'), ('finger'), ('count'), ('each'), ('директор'), ('name'), ('едв'), ('doesn'), ('wish'), ('door'), ('your'), ('tube'), ('quot'), ('друг'), ('точк'), ('learn'), ('box'), ('start'), ('troubl'), ('bone'), ('larg'), ('squar'), ('александр'), ('километр'), ('последн'), ('го'), ('decid'), ('чем'), ('знач'), ('станов'), ('ест'), ('experi'), ('it'), ('distant'), ('leav'), ('со'), ('никт'), ('differ'), ('компан'), ('бывш'), ('четырех'), ('els'), ('происход'), ('hors'), ('врем'), ('фирм'), ('special'), ('ride'), ('march'), ('совершен'), ('wouldn'), ('href'), ('очен'), ('weight'), ('блог'), ('safe'), ('rais'), ('вполн'), ('head'), ('machin'), ('sister'), ('star'), ('full'), ('мен'), ('burn'), ('father'), ('ice'), ('н'), ('opposit'), ('indic'), ('столиц'), ('smile'), ('half'), ('тут'), ('наконец'), ('lot'), ('конц'), ('money'), ('close'), ('ну'), ('us'), ('boat'), ('чег'), ('раз'), ('положен'), ('ем'), ('mean'), ('anim'), ('brought'), ('began'), ('shop'), ('бол'), ('стол'), ('будт'), ('block'), ('thing'), ('прич'), ('eight'), ('ю'), ('нет'), ('массов'), ('stick'), ('forward'), ('grow'), ('bird'), ('mark'), ('провест'), ('appl'), ('listen'), ('rememb'), ('brown'), ('bought'), ('beat'), ('совс'), ('repli'), ('ил'), ('rail'), ('one'), ('местн'), ('имеет'), ('centuri'), ('did'), ('drop'), ('find'), ('ten'), ('л'), ('from'), ('planet'), ('месяц'), ('method'), ('root'), ('люд'), ('her'), ('determin'), ('днях'), ('мир'), ('effect'), ('извест'), ('сам'), ('stay'), ('идет'), ('всем'), ('live'), ('more'), ('year'), ('search'), ('island'), ('cross'), ('явн'), ('sudden'), ('момент'), ('до'), ('вообщ'), ('speech'), ('отдел'), ('серг'), ('тож'), ('let'), ('pair'), ('сотрудник'), ('летн'), ('this'), ('success'), ('lay'), ('song'), ('molecul'), ('операц'), ('togeth'), ('among'), ('кстат'), ('цен'), ('be'), ('class'), ('был'), ('major'), ('team'), ('most'), ('imagin'), ('во'), ('place'), ('room'), ('look'), ('high'), ('saw'), ('действительн'), ('миха'), ('help'), ('событ'), ('участ'), ('had'), ('desert'), ('будут'), ('невозможн'), ('first'), ('stop'), ('ясн'), ('thin'), ('владимир'), ('rang'), ('парт'), ('play'), ('snow'), ('histori'), ('больш'), ('процент'), ('shouldn');
            -- PostgreSQL sends notices about implicit keys that are being created,
            -- and the test suite takes them for warnings.
            SET client_min_messages=WARNING;

            -- "Full" stopwords
            DROP TABLE IF EXISTS stopwords_long;
            CREATE TABLE stopwords_long (
                stopwords_id SERIAL PRIMARY KEY,
                stopword VARCHAR(256) NOT NULL
            ) WITH (OIDS=FALSE);
            CREATE UNIQUE INDEX stopwords_long_stopword ON stopwords_long(stopword);

            -- Stopword stems
            DROP TABLE IF EXISTS stopword_stems_long;
            CREATE TABLE stopword_stems_long (
                stopword_stems_id SERIAL PRIMARY KEY,
                stopword_stem VARCHAR(256) NOT NULL
            ) WITH (OIDS=FALSE);
            CREATE UNIQUE INDEX stopword_stems_long_stopword_stem ON stopword_stems_long(stopword_stem);

            -- Reset the message level back to "notice".
            SET client_min_messages=NOTICE;

INSERT INTO stopwords_long (stopword) VALUES ('issue'), ('мог'), ('supplied'), ('dropped'), ('expenditures'), ('distinguished'), ('calm'), ('taken'), ('nearest'), ('yelled'), ('load'), ('what'), ('married'), ('accurately'), ('rigid'), ('gray'), ('experts'), ('medicine'), ('conclusions'), ('twenty'), ('недавно'), ('shown'), ('declared'), ('него'), ('trust'), ('corn'), ('jan'), ('electronic'), ('contribute'), ('interview'), ('bay'), ('steadily'), ('going'), ('businesses'), ('artistic'), ('новой'), ('condemned'), ('can'), ('exercise'), ('wild'), ('wait'), ('contributions'), ('seeing'), ('favor'), ('rarely'), ('dates'), ('быстро'), ('merchant'), ('fluid'), ('bench'), ('arc'), ('address'), ('helps'), ('crop'), ('me'), ('кто'), ('становится'), ('by'), ('которой'), ('favorite'), ('неделю'), ('fair'), ('tragic'), ('surfaces'), ('interesting'), ('project'), ('industrial'), ('cool'), ('estimate'), ('share'), ('surrender'), ('death'), ('farther'), ('magazine'), ('председателя'), ('characterized'), ('доме'), ('proof'), ('мере'), ('indirect'), ('verbal'), ('деле'), ('giving'), ('everyone'), ('loaded'), ('lies'), ('commodities'), ('перед'), ('rate'), ('gone'), ('tables'), ('matter'), ('invited'), ('owned'), ('ran'), ('trouble'), ('importance'), ('crown'), ('их'), ('density'), ('reprint'), ('sensitivity'), ('people'), ('lift'), ('imposed'), ('identify'), ('divine'), ('guest'), ('treated'), ('conditions'), ('source'), ('protection'), ('массовой'), ('processes'), ('local'), ('failed'), ('sink'), ('и'), ('outcome'), ('он'), ('striking'), ('really'), ('ее'), ('vowel'), ('fish'), ('powder'), ('allowing'), ('ear'), ('reader'), ('выборах'), ('item'), ('hear'), ('truck'), ('сообщили'), ('express'), ('комментариев'), ('sovereignty'), ('suspicion'), ('whom'), ('show'), ('reducing'), ('win'), ('drill'), ('sufficient'), ('Об'), ('planetary'), ('трех'), ('lack'), ('трудно'), ('sixties'), ('wheel'), ('petitioner'), ('wash'), ('even'), ('finish'), ('crease'), ('parade'), ('breath'), ('immediately'), ('нибудь'), ('acceptance'), ('fresh'), ('figured'), ('involve'), ('return'), ('gather'), ('patrol'), ('viewed'), ('скорее'), ('handling'), ('serious'), ('почта'), ('drunk'), ('stone'), ('Теперь'), ('получил'), ('rose'), ('rocks'), ('precious'), ('keep'), ('better'), ('yours'), ('explicit'), ('фонда'), ('stockholders'), ('cgi'), ('supply'), ('факт'), ('em'), ('final'), ('and'), ('пять'), ('о'), ('leaders'), ('Д'), ('panel'), ('surprise'), ('spend'), ('excess'), ('la'), ('already'), ('knowledge'), ('saying'), ('danger'), ('г'), ('concepts'), ('Однако'), ('являетесь'), ('grounds'), ('exchange'), ('работает'), ('eg'), ('square'), ('heavily'), ('veteran'), ('attractive'), ('triumph'), ('drugs'), ('latter'), ('approximately'), ('flash'), ('meanings'), ('pile'), ('champion'), ('первый'), ('бы'), ('evening'), ('devices'), ('building'), ('sees'), ('virtue'), ('position'), ('rent'), ('holding'), ('deal'), ('У'), ('personal'), ('disposal'), ('первого'), ('owner'), ('primarily'), ('сделаем'), ('obligations'), ('continues'), ('участие'), ('happy'), ('руководство'), ('financing'), ('table'), ('recognize'), ('milk'), ('green'), ('compromise'), ('nest'), ('после'), ('наших'), ('ruling'), ('chairman'), ('furnish'), ('yellow'), ('historian'), ('serving'), ('среди'), ('exposure'), ('trading'), ('vast'), ('partner'), ('находившегося'), ('delay'), ('bearing'), ('substantial'), ('reflection'), ('web'), ('seconds'), ('burden'), ('partly'), ('votes'), ('set'), ('real'), ('country'), ('obvious'), ('architect'), ('wire'), ('explains'), ('ты'), ('job'), ('agent'), ('secrets'), ('met'), ('то'), ('числе'), ('tooth'), ('white'), ('or'), ('missile'), ('wonder'), ('expression'), ('could'), ('organic'), ('какой'), ('atoms'), ('ваш'), ('rates'), ('missed'), ('foods'), ('port'), ('logical'), ('первую'), ('referred'), ('learning'), ('Александра'), ('research'), ('entertainment'), ('considering'), ('eliminated'), ('survey'), ('bring'), ('parties'), ('sight'), ('religion'), ('прокуратуры'), ('gentleman'), ('arrived'), ('application'), ('protected'), ('vote'), ('lid'), ('laws'), ('либо'), ('perfect'), ('driven'), ('три'), ('cities'), ('sleep'), ('procedures'), ('birth'), ('you'), ('illusion'), ('appreciate'), ('both'), ('flew'), ('overcome'), ('eventually'), ('offered'), ('decisions'), ('shut'), ('male'), ('honored'), ('prior'), ('concrete'), ('деньги'), ('Фото'), ('отношении'), ('mainly'), ('wines'), ('speed'), ('programs'), ('drinking'), ('должно'), ('uneasy'), ('regular'), ('located'), ('pass'), ('edt'), ('manager'), ('eating'), ('creation'), ('habits'), ('wet'), ('relief'), ('would'), ('signals'), ('no'), ('нас'), ('anxious'), ('probabilities'), ('valley'), ('excitement'), ('процента'), ('passengers'), ('object'), ('sticks'), ('invent'), ('existence'), ('doing'), ('вовсе'), ('get'), ('huge'), ('adopted'), ('считает'), ('этих'), ('deliberately'), ('go'), ('register'), ('brilliant'), ('recommendation'), ('boats'), ('новый'), ('universe'), ('ourselves'), ('justified'), ('Известиям'), ('tree'), ('third'), ('governments'), ('monday'), ('profound'), ('годы'), ('boy'), ('folks'), ('govern'), ('estate'), ('route'), ('disease'), ('силу'), ('mate'), ('accused'), ('behind'), ('так'), ('shock'), ('planning'), ('bad'), ('occasion'), ('something'), ('К'), ('streets'), ('edges'), ('afford'), ('academic'), ('bottom'), ('pulling'), ('approach'), ('hot'), ('self'), ('elsewhere'), ('eighteenth'), ('absence'), ('belong'), ('счет'), ('threat'), ('character'), ('restaurant'), ('prevention'), ('grateful'), ('enter'), ('bills'), ('дает'), ('foreign'), ('reporters'), ('rather'), ('stuff'), ('closely'), ('немало'), ('age'), ('plain'), ('sexual'), ('dancers'), ('cure'), ('expanded'), ('recommended'), ('специалисты'), ('volume'), ('difficulties'), ('luncheon'), ('quotient'), ('higher'), ('blog'), ('smell'), ('draft'), ('adding'), ('tests'), ('mental'), ('symbolic'), ('landscape'), ('results'), ('want'), ('cholesterol'), ('late'), ('valid'), ('key'), ('save'), ('printed'), ('matching'), ('foot'), ('experiences'), ('stored'), ('prime'), ('дальше'), ('plan'), ('rector'), ('dynamic'), ('appear'), ('magnificent'), ('replaced'), ('worker'), ('charter'), ('ИТАР'), ('usual'), ('gas'), ('ли'), ('area'), ('hope'), ('equation'), ('прежнему'), ('die'), ('bath'), ('knife'), ('becoming'), ('husband'), ('cook'), ('establishment'), ('sheet'), ('transformed'), ('exist'), ('preliminary'), ('gets'), ('novels'), ('помощь'), ('right'), ('capable'), ('today'), ('construction'), ('necessary'), ('собственности'), ('charming'), ('natural'), ('handled'), ('опыт'), ('pot'), ('tail'), ('extent'), ('marriage'), ('ours'), ('суда'), ('том'), ('released'), ('bond'), ('человек'), ('card'), ('thursday'), ('sick'), ('measures'), ('four'), ('ними'), ('bonds'), ('помощью'), ('пятая'), ('cotton'), ('opportunities'), ('publicly'), ('verse'), ('fire'), ('attend'), ('dawn'), ('условиях'), ('recommendations'), ('meat'), ('hungry'), ('affected'), ('rolled'), ('experience'), ('legislative'), ('individual'), ('narrative'), ('who'), ('entire'), ('artists'), ('этого'), ('represented'), ('котором'), ('tools'), ('previously'), ('loans'), ('plastic'), ('wine'), ('simple'), ('purchased'), ('season'), ('officials'), ('luck'), ('нескольких'), ('witnesses'), ('furniture'), ('главное'), ('desired'), ('beach'), ('blame'), ('продукции'), ('listened'), ('бывший'), ('Так'), ('hair'), ('зам'), ('tie'), ('sea'), ('increases'), ('routine'), ('graduate'), ('один'), ('своей'), ('worn'), ('continuously'), ('participation'), ('Юрий'), ('sharing'), ('hill'), ('jobs'), ('failure'), ('dream'), ('xml'), ('случай'), ('factors'), ('commonly'), ('chances'), ('inevitably'), ('заявил'), ('institutions'), ('expected'), ('near'), ('shoot'), ('leading'), ('indication'), ('yesterday'), ('advance'), ('такого'), ('never'), ('с'), ('silent'), ('player'), ('diameter'), ('expenses'), ('action'), ('assembled'), ('shine'), ('кстате'), ('many'), ('fat'), ('atmosphere'), ('coffee'), ('над'), ('talking'), ('swimming'), ('bare'), ('место'), ('assessors'), ('последнее'), ('surprised'), ('operated'), ('wearing'), ('church'), ('lips'), ('activities'), ('long-term'), ('author'), ('considerably'), ('каждая'), ('productive'), ('fraction'), ('she'), ('widespread'), ('turning'), ('affairs'), ('utility'), ('act'), ('plastics'), ('planned'), ('inventory'), ('unconscious'), ('throw'), ('exact'), ('cheek'), ('fiber'), ('provide'), ('watching'), ('supporting'), ('семьи'), ('way'), ('recovery'), ('neighbor'), ('естественно'), ('lacking'), ('shelter'), ('меня'), ('wheels'), ('comments'), ('observers'), ('wrong'), ('in'), ('sitting'), ('electricity'), ('receives'), ('thrown'), ('alienation'), ('dark'), ('universities'), ('implications'), ('achievements'), ('colonel'), ('understanding'), ('remaining'), ('не'), ('representative'), ('seized'), ('identified'), ('рук'), ('investment'), ('damn'), ('quick'), ('fast'), ('главный'), ('shows'), ('dare'), ('poet'), ('losses'), ('места'), ('patient'), ('presented'), ('possibility'), ('concerning'), ('match'), ('description'), ('spiritual'), ('обычно'), ('shopping'), ('riding'), ('апрель'), ('series'), ('climb'), ('composition'), ('лица'), ('variety'), ('wedding'), ('syllable'), ('account'), ('purchase'), ('running'), ('nervous'), ('alone'), ('little'), ('switch'), ('pressures'), ('combination'), ('уж'), ('точнее'), ('tended'), ('mst'), ('ie'), ('swept'), ('refused'), ('суббота'), ('questions'), ('cents'), ('those'), ('relation'), ('away'), ('creating'), ('begun'), ('persuaded'), ('heights'), ('декабря'), ('beyond'), ('rules'), ('я'), ('bodies'), ('say'), ('qualities'), ('месяца'), ('seldom'), ('original'), ('несколько'), ('increase'), ('score'), ('всех'), ('picked'), ('outdoor'), ('самой'), ('иметь'), ('absolute'), ('dirty'), ('brick'), ('relations'), ('stiff'), ('providing'), ('fortune'), ('suggested'), ('mysterious'), ('destroyed'), ('самое'), ('buying'), ('мировой'), ('delightful'), ('быть'), ('published'), ('aids'), ('своим'), ('literary'), ('possible'), ('months'), ('earnings'), ('потому'), ('widely'), ('сотрудников'), ('barn'), ('later'), ('kept'), ('prevented'), ('dear'), ('bold'), ('одного'), ('sampling'), ('proud'), ('Она'), ('members'), ('которую'), ('length'), ('metal'), ('этот'), ('were'), ('poured'), ('law'), ('containing'), ('collective'), ('После'), ('understand'), ('производства'), ('turn'), ('specimen'), ('past'), ('iron'), ('в'), ('cost'), ('chicken'), ('refund'), ('passed'), ('biological'), ('aug'), ('introduced'), ('gave'), ('anxiety'), ('миллиарда'), ('engaged'), ('conversation'), ('letters'), ('under'), ('features'), ('contrast'), ('preferred'), ('слова'), ('Е'), ('Правда'), ('harder'), ('которому'), ('lacked'), ('gathering'), ('feb'), ('inches'), ('sequence'), ('move'), ('officers'), ('видимо'), ('our'), ('peas'), ('lo'), ('distinct'), ('резко'), ('its'), ('earlier'), ('вопросы'), ('шесть'), ('over-all'), ('determined'), ('observations'), ('union'), ('enormous'), ('brother'), ('goes'), ('we'), ('hasn'), ('velocity'), ('notice'), ('group'), ('говорил'), ('personally'), ('motion'), ('включая'), ('buildings'), ('payment'), ('blockquote'), ('angle'), ('radio'), ('Кто'), ('desegregation'), ('managers'), ('accepted'), ('nineteenth'), ('ocean'), ('an'), ('bed'), ('neck'), ('medical'), ('центре'), ('movie'), ('soon'), ('каждый'), ('средства'), ('paying'), ('permit'), ('records'), ('а'), ('origin'), ('jump'), ('end'), ('roads'), ('splendid'), ('theory'), ('respective'), ('miss'), ('sending'), ('revenues'), ('diffusion'), ('pride'), ('urged'), ('reach'), ('purely'), ('dispute'), ('reliable'), ('patience'), ('pilot'), ('great'), ('scarcely'), ('касается'), ('particular'), ('expansion'), ('много'), ('beautiful'), ('without'), ('than'), ('just'), ('pictures'), ('effective'), ('нее'), ('earliest'), ('department'), ('strike'), ('cafe'), ('congressional'), ('позиции'), ('envelope'), ('supervision'), ('wounded'), ('symbol'), ('люди'), ('supplies'), ('smiled'), ('reduction'), ('living'), ('traditional'), ('technology'), ('территории'), ('fears'), ('метра'), ('follow'), ('appointment'), ('piece'), ('effort'), ('continued'), ('elected'), ('rapid'), ('endless'), ('suspected'), ('woman'), ('большинство'), ('zero'), ('neat'), ('concentration'), ('cells'), ('demonstration'), ('назад'), ('image'), ('chiefly'), ('resistance'), ('saturday'), ('char'), ('enthusiastic'), ('attracted'), ('fractions'), ('chair'), ('narrow'), ('proceeded'), ('квартиры'), ('underlying'), ('copy'), ('practice'), ('order'), ('following'), ('restrictions'), ('prize'), ('parent'), ('sorry'), ('friday'), ('definitely'), ('тот'), ('операции'), ('data'), ('ignored'), ('fed'), ('year-old'), ('succession'), ('labour'), ('opposed'), ('минут'), ('after'), ('democracy'), ('специалистов'), ('breathing'), ('То'), ('strongest'), ('enjoyment'), ('back'), ('as'), ('результате'), ('savings'), ('respond'), ('permitted'), ('между'), ('opportunity'), ('discharge'), ('stumbled'), ('grants'), ('employment'), ('chest'), ('interested'), ('wondering'), ('тому'), ('growing'), ('eggs'), ('shadows'), ('Грозном'), ('комиссии'), ('ему'), ('центр'), ('difference'), ('ends'), ('theirs'), ('integration'), ('sheep'), ('came'), ('crossing'), ('span'), ('repeat'), ('customers'), ('wave'), ('theological'), ('recreation'), ('magnetic'), ('conversion'), ('sphere'), ('putting'), ('eternal'), ('variables'), ('protect'), ('eliminate'), ('someone'), ('plans'), ('kind'), ('herself'), ('далеко'), ('takes'), ('проблем'), ('stands'), ('agency'), ('smoke'), ('outlook'), ('assessment'), ('sure'), ('instrument'), ('strongly'), ('grown'), ('comfort'), ('pretty'), ('organizations'), ('Виктор'), ('telling'), ('onto'), ('attacks'), ('maid'), ('whole'), ('went'), ('информацию'), ('new'), ('returning'), ('evaluation'), ('burst'), ('promote'), ('entirely'), ('stations'), ('skilled'), ('войск'), ('penny'), ('composed'), ('vital'), ('send'), ('limitations'), ('states'), ('respectively'), ('needed'), ('develop'), ('частности'), ('innocent'), ('sugar'), ('civilian'), ('prospective'), ('nose'), ('experienced'), ('prospects'), ('fathers'), ('communication'), ('norms'), ('expensive'), ('conclusion'), ('if'), ('characters'), ('him'), ('gentlemen'), ('тонн'), ('wide'), ('examples'), ('проблемы'), ('пяти'), ('finger'), ('cited'), ('Почему'), ('сообща'), ('drawing'), ('regions'), ('your'), ('describes'), ('quot'), ('seated'), ('start'), ('variable'), ('lying'), ('Между'), ('bone'), ('cutting'), ('consequences'), ('sacred'), ('offers'), ('ending'), ('actual'), ('calls'), ('demanded'), ('voice'), ('accordingly'), ('occurrence'), ('fields'), ('differ'), ('resulted'), ('holder'), ('electric'), ('begins'), ('discussions'), ('actually'), ('stores'), ('special'), ('occasional'), ('voices'), ('generally'), ('describe'), ('reflects'), ('father'), ('changed'), ('exceptions'), ('daughter'), ('audience'), ('money'), ('punishment'), ('anyone'), ('gin'), ('pleasant'), ('consistent'), ('чуть'), ('plaster'), ('probability'), ('eight'), ('АО'), ('другом'), ('forward'), ('меньше'), ('нашей'), ('hoped'), ('enforced'), ('beat'), ('acquired'), ('compared'), ('characteristic'), ('cap'), ('nuts'), ('нового'), ('wednesday'), ('Что'), ('positions'), ('welcome'), ('trend'), ('colleagues'), ('substrate'), ('имеет'), ('relationship'), ('did'), ('marks'), ('extensive'), ('ten'), ('disturbed'), ('Н'), ('никто'), ('meets'), ('eager'), ('sake'), ('from'), ('месяц'), ('method'), ('sought'), ('her'), ('announced'), ('any'), ('define'), ('всем'), ('delicate'), ('more'), ('material'), ('subjects'), ('island'), ('cross'), ('до'), ('prisoners'), ('patterns'), ('curious'), ('mathematics'), ('amazing'), ('sweet'), ('groups'), ('this'), ('менее'), ('carbon'), ('ceiling'), ('song'), ('fence'), ('hoping'), ('cst'), ('report'), ('authorities'), ('be'), ('class'), ('мой'), ('utopian'), ('september'), ('detailed'), ('weekend'), ('most'), ('operational'), ('скажем'), ('thousands'), ('writers'), ('offering'), ('roof'), ('look'), ('passenger'), ('parked'), ('demonstrate'), ('hundreds'), ('других'), ('полтора'), ('будут'), ('desert'), ('had'), ('stop'), ('information'), ('rang'), ('venture'), ('начала'), ('equipped'), ('slender'), ('inspection'), ('группа'), ('leadership'), ('storm'), ('hat'), ('delivered'), ('stead'), ('reveals'), ('particle'), ('parking'), ('qualified'), ('measurement'), ('shapes'), ('excessive'), ('forming'), ('проект'), ('anticipated'), ('village'), ('captain'), ('дать'), ('sounds'), ('again'), ('wall'), ('quietly'), ('of'), ('employees'), ('relevant'), ('winter'), ('phase'), ('Пресс'), ('ugly'), ('platform'), ('much'), ('procedure'), ('neither'), ('anticipation'), ('explained'), ('part'), ('where'), ('flight'), ('settle'), ('doctor'), ('Я'), ('left'), ('experiment'), ('insisted'), ('hydrogen'), ('первой'), ('seen'), ('prestige'), ('constitute'), ('questioned'), ('aesthetic'), ('drug'), ('knows'), ('refer'), ('visual'), ('upon'), ('plates'), ('only'), ('stayed'), ('districts'), ('В'), ('resumed'), ('disaster'), ('мне'), ('proposals'), ('means'), ('absolutely'), ('recorded'), ('structural'), ('blind'), ('requirements'), ('thoroughly'), ('socialism'), ('recall'), ('long-range'), ('sometimes'), ('confused'), ('ведь'), ('remainder'), ('лично'), ('делаем'), ('прямо'), ('около'), ('reasonable'), ('первых'), ('firing'), ('игры'), ('producing'), ('уровне'), ('align'), ('strong'), ('voluntary'), ('calendar'), ('целом'), ('представители'), ('balanced'), ('более'), ('forests'), ('empirical'), ('meet'), ('into'), ('seven'), ('advanced'), ('gorton'), ('weekly'), ('good'), ('making'), ('fabrics'), ('intention'), ('dependent'), ('myth'), ('master'), ('provision'), ('west'), ('solved'), ('concern'), ('thickness'), ('farmer'), ('reorganization'), ('screen'), ('fishing'), ('cleared'), ('shares'), ('возможность'), ('возможности'), ('pipe'), ('convinced'), ('От'), ('roll'), ('axis'), ('state'), ('probably'), ('atom'), ('свои'), ('sand'), ('fallout'), ('ranks'), ('registered'), ('swim'), ('rub'), ('rode'), ('defense'), ('bell'), ('delayed'), ('heard'), ('numerous'), ('flat'), ('plenty'), ('adriver'), ('ladder'), ('workshop'), ('власть'), ('joke'), ('senior'), ('mountain'), ('blues'), ('против'), ('attitude'), ('behavior'), ('thyroid'), ('farmers'), ('них'), ('arts'), ('conception'), ('increasing'), ('chairs'), ('городе'), ('come'), ('file'), ('fly'), ('bride'), ('dignity'), ('preparation'), ('degrees'), ('least'), ('less'), ('depending'), ('etc.'), ('tremendous'), ('этому'), ('percentage'), ('analysis'), ('insects'), ('dance'), ('decided'), ('household'), ('introduction'), ('virtually'), ('июля'), ('tall'), ('той'), ('fixed'), ('якобы'), ('declaration'), ('сути'), ('миллион'), ('удалось'), ('received'), ('paper'), ('stuck'), ('defend'), ('Через'), ('last'), ('uniform'), ('identity'), ('notes'), ('fascinating'), ('update'), ('равно'), ('next'), ('bid'), ('devil'), ('almost'), ('связи'), ('сегодня'), ('chapel'), ('instruments'), ('году'), ('contacts'), ('toward'), ('oral'), ('circle'), ('finding'), ('duty'), ('contain'), ('displacement'), ('такое'), ('washed'), ('died'), ('лидер'), ('оказался'), ('fate'), ('frightened'), ('bus'), ('cast'), ('intended'), ('слишком'), ('drivers'), ('hit'), ('attending'), ('merely'), ('company'), ('crowd'), ('make'), ('leather'), ('industry'), ('maintaining'), ('big'), ('churches'), ('themselves'), ('august'), ('burning'), ('flying'), ('worry'), ('mg'), ('сейчас'), ('passing'), ('input'), ('shoulders'), ('choose'), ('tip'), ('hanging'), ('slept'), ('movies'), ('leaving'), ('property'), ('middle'), ('grew'), ('ideological'), ('Таким'), ('displayed'), ('были'), ('younger'), ('individuals'), ('affects'), ('transformation'), ('schedule'), ('sophisticated'), ('launched'), ('adults'), ('secondary'), ('attitudes'), ('some'), ('applied'), ('with'), ('arrangement'), ('eat'), ('liked'), ('committee'), ('function'), ('но'), ('advantages'), ('на'), ('somehow'), ('propaganda'), ('shouting'), ('cat'), ('силы'), ('film'), ('handed'), ('concert'), ('impression'), ('liquor'), ('кого'), ('constant'), ('techniques'), ('improvement'), ('ahead'), ('crew'), ('ones'), ('mines'), ('financial'), ('wake'), ('respect'), ('Александр'), ('glass'), ('grades'), ('against'), ('instructions'), ('конца'), ('regarded'), ('cultural'), ('Это'), ('certainly'), ('kitchen'), ('plays'), ('clothes'), ('music'), ('дома'), ('insure'), ('habit'), ('location'), ('почти'), ('carefully'), ('suffering'), ('playing'), ('occupation'), ('else'), ('ninth'), ('woods'), ('engine'), ('tomorrow'), ('society'), ('label'), ('busy'), ('souls'), ('dedication'), ('lists'), ('wives'), ('benefits'), ('needs'), ('forced'), ('missing'), ('brush'), ('НА'), ('focus'), ('делам'), ('никак'), ('basis'), ('begin'), ('inside'), ('ability'), ('improve'), ('новых'), ('suspect'), ('profit'), ('aspect'), ('Сейчас'), ('такие'), ('likely'), ('времени'), ('kinds'), ('resources'), ('fourteen'), ('знает'), ('employed'), ('barely'), ('responded'), ('peculiar'), ('lengths'), ('весь'), ('Как'), ('discuss'), ('struck'), ('сказать'), ('примеру'), ('selling'), ('undoubtedly'), ('sighed'), ('political'), ('интервью'), ('somebody'), ('positive'), ('steady'), ('necessarily'), ('Вы'), ('settled'), ('garage'), ('adjustment'), ('laughing'), ('levels'), ('variation'), ('enterprise'), ('career'), ('ordered'), ('rapidly'), ('preparing'), ('accurate'), ('guests'), ('com'), ('behalf'), ('drinks'), ('remove'), ('spell'), ('наиболее'), ('display'), ('liberal'), ('женщин'), ('vivid'), ('user'), ('лет'), ('disappeared'), ('pulmonary'), ('escape'), ('hopes'), ('час'), ('salt'), ('ritual'), ('fans'), ('За'), ('intense'), ('shift'), ('cent'), ('иначе'), ('brave'), ('mind'), ('creative'), ('healthy'), ('colors'), ('older'), ('полностью'), ('devoted'), ('bat'), ('saving'), ('exercises'), ('свою'), ('racing'), ('award'), ('своем'), ('hundred'), ('why'), ('product'), ('writes'), ('Он'), ('ideas'), ('destruction'), ('know'), ('consider'), ('legislators'), ('alliance'), ('lands'), ('posts'), ('break'), ('course'), ('commander'), ('людей'), ('upstairs'), ('lower'), ('foam'), ('freight'), ('sounded'), ('которые'), ('anti-trust'), ('ситуация'), ('specific'), ('follows'), ('seemed'), ('physics'), ('design'), ('agencies'), ('accounts'), ('internal'), ('которыми'), ('Более'), ('chlorine'), ('harmony'), ('interests'), ('glanced'), ('worried'), ('civic'), ('package'), ('enemies'), ('pursue'), ('becomes'), ('района'), ('males'), ('события'), ('components'), ('метров'), ('full-time'), ('neighborhood'), ('concept'), ('happiness'), ('et'), ('paintings'), ('kids'), ('occurred'), ('psychological'), ('involved'), ('other'), ('пор'), ('parents'), ('intimate'), ('вроде'), ('significance'), ('worthy'), ('gun'), ('term'), ('founded'), ('boys'), ('except'), ('loud'), ('friendly'), ('principle'), ('monument'), ('initiative'), ('данным'), ('говорит'), ('visiting'), ('runs'), ('masses'), ('markets'), ('another'), ('предприятий'), ('nobody'), ('vein'), ('target'), ('view'), ('committed'), ('итоге'), ('hero'), ('fiscal'), ('request'), ('Потом'), ('formation'), ('ranging'), ('entered'), ('ship'), ('sit'), ('Сегодня'), ('populate'), ('teams'), ('boating'), ('должны'), ('через'), ('questioning'), ('policies'), ('forest'), ('точки'), ('hung'), ('powerful'), ('manner'), ('директора'), ('organ'), ('advertising'), ('honest'), ('besides'), ('salary'), ('wanted'), ('cottage'), ('ruled'), ('soft'), ('abbr'), ('obliged'), ('exclusively'), ('write'), ('culture'), ('movements'), ('curve'), ('liberty'), ('commercial'), ('guide'), ('всему'), ('carries'), ('worse'), ('свое'), ('м'), ('lone'), ('мало'), ('wildly'), ('crazy'), ('dishes'), ('broken'), ('mad'), ('fill'), ('две'), ('reports'), ('choice'), ('adjustments'), ('laid'), ('последних'), ('holes'), ('inadequate'), ('staining'), ('sex'), ('bedroom'), ('warmth'), ('increasingly'), ('well'), ('office'), ('anti-Semitism'), ('поэтому'), ('doctors'), ('critics'), ('recent'), ('news'), ('so-called'), ('worth'), ('potential'), ('newer'), ('concentrated'), ('труда'), ('possibilities'), ('самого'), ('row'), ('evidently'), ('headquarters'), ('sharp'), ('ball'), ('некоторые'), ('цены'), ('governing'), ('gang'), ('sources'), ('faith'), ('scenes'), ('none'), ('accomplished'), ('вести'), ('followed'), ('tangent'), ('ней'), ('sharply'), ('pool'), ('whip'), ('towards'), ('stood'), ('oct'), ('mere'), ('strange'), ('acts'), ('decide'), ('peered'), ('establishing'), ('divided'), ('cellar'), ('approaching'), ('craft'), ('directed'), ('suitable'), ('leaned'), ('so'), ('meant'), ('insurance'), ('killer'), ('оказалось'), ('tragedy'), ('weakness'), ('world'), ('flux'), ('emergency'), ('greatest'), ('straight'), ('prominent'), ('skirt'), ('abandoned'), ('early'), ('Здесь'), ('at'), ('fig'), ('murder'), ('trade'), ('builder'), ('hurry'), ('road'), ('air'), ('ideal'), ('sid'), ('rough'), ('form'), ('baby'), ('traveled'), ('respectable'), ('give'), ('unique'), ('дело'), ('supplement'), ('military'), ('последний'), ('еще'), ('хорошо'), ('smooth'), ('precision'), ('figure'), ('annual'), ('seed'), ('being'), ('executive'), ('constructed'), ('blonde'), ('december'), ('possessed'), ('lie'), ('examined'), ('года'), ('various'), ('costs'), ('chief'), ('attempts'), ('derived'), ('руководитель'), ('man'), ('automatic'), ('жителей'), ('коп'), ('мая'), ('ранее'), ('overwhelming'), ('windows'), ('july'), ('possibly'), ('http'), ('walls'), ('friendship'), ('may'), ('leads'), ('permission'), ('operations'), ('planes'), ('different'), ('displays'), ('hall'), ('morality'), ('functional'), ('начальник'), ('это'), ('depression'), ('terms'), ('installed'), ('attached'), ('trained'), ('bridges'), ('immediate'), ('pleasure'), ('заявление'), ('crucial'), ('novel'), ('sympathetic'), ('serves'), ('друга'), ('relieved'), ('hurried'), ('extraordinary'), ('allowances'), ('communities'), ('история'), ('talents'), ('formulas'), ('dressing'), ('получили'), ('tactics'), ('blocks'), ('lighting'), ('conspiracy'), ('examination'), ('holds'), ('widow'), ('profession'), ('income'), ('hesitated'), ('regard'), ('impulse'), ('Тем'), ('главным'), ('casual'), ('marginal'), ('walk'), ('про'), ('manage'), ('hard'), ('width'), ('illustration'), ('октября'), ('number'), ('battle'), ('drawings'), ('nevertheless'), ('surely'), ('интересы'), ('error'), ('attempted'), ('societies'), ('ownership'), ('organization'), ('remember'), ('процесс'), ('starts'), ('managed'), ('руках'), ('now'), ('жить'), ('universal'), ('population'), ('waited'), ('test'), ('produce'), ('gross'), ('resist'), ('column'), ('proved'), ('how'), ('identical'), ('event'), ('без'), ('their'), ('найти'), ('scale'), ('retained'), ('relating'), ('best'), ('ним'), ('automobiles'), ('therefore'), ('heels'), ('up'), ('lumber'), ('oxygen'), ('having'), ('была'), ('slowly'), ('king'), ('tape'), ('included'), ('interpretation'), ('Г'), ('emission'), ('question'), ('breaking'), ('creatures'), ('Ю'), ('многие'), ('pressure'), ('loan'), ('из'), ('carried'), ('far'), ('winds'), ('также'), ('required'), ('suffix'), ('admit'), ('makes'), ('animals'), ('sound'), ('also'), ('должна'), ('trim'), ('tissue'), ('distribution'), ('related'), ('stranger'), ('but'), ('too'), ('Л'), ('over'), ('reaching'), ('aboard'), ('federal'), ('largely'), ('heritage'), ('is'), ('fallen'), ('coat'), ('seventh'), ('mess'), ('событий'), ('своего'), ('prevent'), ('anger'), ('golden'), ('coach'), ('tendency'), ('attempting'), ('accordance'), ('lieutenant'), ('Сергей'), ('многих'), ('х'), ('phases'), ('tubes'), ('assume'), ('pay'), ('historical'), ('like'), ('got'), ('collect'), ('было'), ('shot'), ('camp'), ('believes'), ('говорится'), ('receive'), ('tension'), ('подобная'), ('toast'), ('fund'), ('subjected'), ('pink'), ('fear'), ('несмотря'), ('baseball'), ('especially'), ('include'), ('unlikely'), ('standing'), ('cut'), ('papers'), ('evidence'), ('his'), ('мире'), ('времена'), ('rush'), ('precisely'), ('profits'), ('easy'), ('realized'), ('coming'), ('basically'), ('stronger'), ('cash'), ('rise'), ('caused'), ('projects'), ('allows'), ('sacrifice'), ('bother'), ('shipping'), ('critic'), ('based'), ('conflict'), ('username'), ('join'), ('lake'), ('себя'), ('й'), ('authentic'), ('assigned'), ('packed'), ('actions'), ('suite'), ('meaning'), ('libraries'), ('что'), ('gentle'), ('будто'), ('rural'), ('likes'), ('тех'), ('depend'), ('device'), ('camera'), ('unit'), ('consonant'), ('fibers'), ('exciting'), ('pain'), ('made'), ('page'), ('browser'), ('говорить'), ('representatives'), ('aren'), ('тем'), ('field'), ('всё'), ('completion'), ('uses'), ('such'), ('greater'), ('shape'), ('такая'), ('столь'), ('played'), ('degree'), ('politicians'), ('equivalent'), ('часто'), ('regularly'), ('dangerous'), ('apply'), ('badly'), ('оно'), ('ходе'), ('деятельность'), ('current'), ('evil'), ('poetry'), ('edge'), ('guess'), ('swift'), ('example'), ('ancient'), ('yard'), ('discussed'), ('отличие'), ('poems'), ('comfortable'), ('saddle'), ('june'), ('exception'), ('voted'), ('vigorous'), ('falling'), ('catch'), ('sponsor'), ('forth'), ('grain'), ('decades'), ('talent'), ('successfully'), ('quarrel'), ('fun'), ('north'), ('марта'), ('снова'), ('existed'), ('member'), ('clerk'), ('waves'), ('candidates'), ('ей'), ('dealt'), ('exhibition'), ('ward'), ('time'), ('round'), ('maintain'), ('engagement'), ('convenience'), ('orderly'), ('sponsored'), ('afraid'), ('dining'), ('mustard'), ('там'), ('shortly'), ('son'), ('cooling'), ('human'), ('bin'), ('classical'), ('personality'), ('Там'), ('по'), ('twice'), ('ни'), ('vacuum'), ('participate'), ('locate'), ('своих'), ('voters'), ('procurement'), ('teeth'), ('complex'), ('angry'), ('midnight'), ('dirt'), ('tossed'), ('nine'), ('cell'), ('closed'), ('cry'), ('phone'), ('bridge'), ('apparent'), ('journey'), ('showed'), ('ranch'), ('filled'), ('international'), ('largest'), ('примерно'), ('apparatus'), ('represent'), ('dying'), ('has'), ('housing'), ('string'), ('reaction'), ('turned'), ('secretary'), ('Хотя'), ('dominant'), ('imitation'), ('До'), ('reason'), ('conditioned'), ('element'), ('куда'), ('Но'), ('thereafter'), ('suddenly'), ('apart'), ('pages'), ('achieve'), ('bottle'), ('entitled'), ('cuts'), ('stretched'), ('poets'), ('production'), ('demanding'), ('intentions'), ('виде'), ('конце'), ('августа'), ('alert'), ('interviews'), ('days'), ('subtract'), ('assist'), ('месяцев'), ('действительно'), ('стала'), ('useful'), ('mud'), ('keeps'), ('тогда'), ('письмо'), ('flower'), ('sentence'), ('rid'), ('desperate'), ('throat'), ('clarity'), ('scholars'), ('contributed'), ('continue'), ('guys'), ('grant'), ('sufficiently'), ('consequence'), ('clothe'), ('shooting'), ('concerts'), ('band'), ('бывшего'), ('library'), ('words'), ('смерти'), ('trends'), ('use'), ('theme'), ('filling'), ('week'), ('apple'), ('noun'), ('despite'), ('commerce'), ('стате'), ('until'), ('charm'), ('лиц'), ('goals'), ('citizen'), ('halign'), ('clothing'), ('junior'), ('achievement'), ('confronted'), ('approaches'), ('temperature'), ('overseas'), ('minutes'), ('est'), ('doesn'), ('arise'), ('panels'), ('confidence'), ('meals'), ('porch'), ('box'), ('hired'), ('appeal'), ('чаще'), ('dried'), ('powers'), ('forces'), ('views'), ('го'), ('самые'), ('conference'), ('mentioned'), ('решил'), ('distant'), ('со'), ('aim'), ('sympathy'), ('banks'), ('charge'), ('events'), ('suspended'), ('поводу'), ('bill'), ('thrust'), ('сразу'), ('heading'), ('rare'), ('grabbed'), ('switches'), ('ясно'), ('порядке'), ('фирм'), ('rises'), ('threatened'), ('таким'), ('essential'), ('march'), ('произошло'), ('typical'), ('href'), ('anniversary'), ('почему'), ('safe'), ('По'), ('star'), ('fellow'), ('replace'), ('merchants'), ('establish'), ('personnel'), ('ice'), ('clouds'), ('columns'), ('тут'), ('lot'), ('observed'), ('pointed'), ('stages'), ('fool'), ('growth'), ('воды'), ('languages'), ('notion'), ('established'), ('mean'), ('searching'), ('message'), ('belly'), ('began'), ('via'), ('textile'), ('нет'), ('spent'), ('stick'), ('responsibility'), ('suggestion'), ('enthusiasm'), ('allied'), ('mutual'), ('scope'), ('magic'), ('какие'), ('harm'), ('negotiations'), ('perform'), ('styles'), ('binomial'), ('suburban'), ('сумму'), ('участников'), ('nodded'), ('rail'), ('gift'), ('issued'), ('involves'), ('softly'), ('curiosity'), ('onset'), ('efficiency'), ('planets'), ('bet'), ('conscience'), ('nearby'), ('taste'), ('inc'), ('range'), ('retirement'), ('returned'), ('имя'), ('medium'), ('planet'), ('потом'), ('grinned'), ('root'), ('действия'), ('particularly'), ('положение'), ('effect'), ('moved'), ('сам'), ('находится'), ('stay'), ('perhaps'), ('самых'), ('burns'), ('decimal'), ('piano'), ('cdt'), ('search'), ('момент'), ('sudden'), ('apartment'), ('затем'), ('perspective'), ('jul'), ('trying'), ('lay'), ('gain'), ('gives'), ('entrance'), ('был'), ('abstract'), ('placing'), ('major'), ('issues'), ('wholly'), ('очень'), ('place'), ('primary'), ('instruction'), ('forget'), ('absent'), ('хоть'), ('above'), ('help'), ('другим'), ('здесь'), ('competition'), ('combined'), ('thin'), ('consciousness'), ('play'), ('snow'), ('winning'), ('particles'), ('Мне'), ('belongs'), ('noise'), ('startled'), ('manufacturers'), ('cope'), ('performances'), ('thinks'), ('recommend'), ('знаю'), ('learned'), ('email'), ('aid'), ('million'), ('modest'), ('как'), ('serve'), ('obviously'), ('mighty'), ('materials'), ('molecule'), ('tied'), ('practical'), ('matters'), ('charges'), ('previous'), ('consistently'), ('regional'), ('remarks'), ('reduce'), ('dancing'), ('imagine'), ('НЕ'), ('insight'), ('access'), ('incredible'), ('board'), ('figures'), ('land'), ('regiment'), ('похоже'), ('одну'), ('elaborate'), ('lights'), ('bit'), ('senator'), ('представителей'), ('activity'), ('lots'), ('birds'), ('дом'), ('placed'), ('presence'), ('urban'), ('knew'), ('понять'), ('setting'), ('имеют'), ('shouted'), ('goal'), ('thank'), ('publicity'), ('type'), ('authority'), ('outstanding'), ('worked'), ('ladies'), ('lonely'), ('если'), ('flesh'), ('ended'), ('check'), ('cow'), ('philosophical'), ('beauty'), ('context'), ('definite'), ('communism'), ('situation'), ('naked'), ('snakes'), ('nature'), ('note'), ('supported'), ('свой'), ('there'), ('eye'), ('keeping'), ('patent'), ('jungle'), ('market'), ('fight'), ('despair'), ('stretch'), ('лучше'), ('faced'), ('dictionary'), ('race'), ('south'), ('video'), ('formerly'), ('Причем'), ('distinctive'), ('quart'), ('astronomy'), ('partially'), ('provides'), ('afternoon'), ('top'), ('beard'), ('главного'), ('front'), ('measuring'), ('certain'), ('barrel'), ('asking'), ('occur'), ('readily'), ('professional'), ('pursuant'), ('совершенно'), ('del'), ('meeting'), ('destiny'), ('руководителей'), ('varying'), ('directly'), ('amount'), ('едва'), ('things'), ('excuse'), ('wildlife'), ('которым'), ('marked'), ('police'), ('отдела'), ('столько'), ('occurs'), ('seeds'), ('confirmed'), ('few'), ('authors'), ('government'), ('told'), ('rejected'), ('companion'), ('york'), ('assistant'), ('occasionally'), ('colored'), ('price'), ('responses'), ('killing'), ('reactionary'), ('вопрос'), ('contact'), ('bombs'), ('famous'), ('Иллюстрация'), ('should'), ('promised'), ('plane'), ('he'), ('sail'), ('остается'), ('artist'), ('calculated'), ('Вот'), ('оказались'), ('intervals'), ('selected'), ('gardens'), ('seek'), ('necessity'), ('applying'), ('mention'), ('Эти'), ('bar'), ('liquid'), ('river'), ('fine'), ('heads'), ('разных'), ('composer'), ('эта'), ('products'), ('fighting'), ('dancer'), ('firms'), ('valign'), ('pace'), ('jet'), ('taught'), ('interest'), ('chick'), ('reaches'), ('frequently'), ('poor'), ('hide'), ('injured'), ('answered'), ('говоря'), ('условия'), ('utterly'), ('men'), ('resulting'), ('watch'), ('waiting'), ('clinical'), ('doors'), ('lucky'), ('think'), ('properly'), ('именно'), ('painter'), ('build'), ('settlement'), ('index'), ('dealer'), ('awareness'), ('yourself'), ('warfare'), ('число'), ('proposed'), ('off'), ('horse'), ('passion'), ('known'), ('era'), ('С'), ('наши'), ('differences'), ('word'), ('additional'), ('pm'), ('hell'), ('ham'), ('assumption'), ('director'), ('придется'), ('city'), ('musicians'), ('maintenance'), ('person'), ('aimed'), ('correspondence'), ('shell'), ('towns'), ('jazz'), ('kingdom'), ('другое'), ('nothing'), ('просто'), ('ambiguous'), ('hated'), ('objectives'), ('slide'), ('that'), ('fiction'), ('perception'), ('двух'), ('knee'), ('line'), ('тоже'), ('dollar'), ('shout'), ('fled'), ('neighboring'), ('part-time'), ('helpful'), ('комитета'), ('result'), ('wonderful'), ('impressed'), ('constitutional'), ('тебе'), ('dec'), ('registration'), ('helpless'), ('shorts'), ('quarters'), ('text'), ('findings'), ('stated'), ('house'), ('считать'), ('pointing'), ('detail'), ('plus'), ('automatically'), ('кроме'), ('giant'), ('investigations'), ('houses'), ('need'), ('earth'), ('does'), ('musician'), ('outside'), ('per'), ('performed'), ('fewer'), ('process'), ('whereas'), ('everything'), ('hr'), ('computed'), ('belief'), ('young'), ('center'), ('lunch'), ('slipped'), ('trials'), ('сторону'), ('ныне'), ('laugh'), ('physical'), ('arrange'), ('working'), ('knowing'), ('cleaning'), ('sensitive'), ('tale'), ('difficult'), ('indicated'), ('wiped'), ('melody'), ('mm'), ('policeman'), ('documents'), ('statistics'), ('выяснилось'), ('print'), ('program'), ('threw'), ('пресс'), ('reform'), ('remarked'), ('business'), ('pound'), ('power'), ('lighted'), ('code'), ('filing'), ('reception'), ('telephone'), ('although'), ('period'), ('substance'), ('claim'), ('pertinent'), ('important'), ('tears'), ('old'), ('presents'), ('rendered'), ('к'), ('spectacular'), ('comparison'), ('players'), ('wondered'), ('bore'), ('girl'), ('all'), ('этим'), ('periods'), ('апреля'), ('за'), ('plants'), ('atomic'), ('traditions'), ('attain'), ('humanity'), ('units'), ('aunt'), ('д'), ('speaking'), ('systems'), ('работа'), ('notable'), ('red'), ('admission'), ('practically'), ('total'), ('twenty-five'), ('contains'), ('grip'), ('development'), ('mine'), ('support'), ('commissioner'), ('add'), ('Ни'), ('factor'), ('forgive'), ('trucks'), ('control'), ('including'), ('don'), ('provisions'), ('car'), ('unless'), ('created'), ('bureau'), ('кому'), ('фирмы'), ('мене'), ('february'), ('complete'), ('itself'), ('portion'), ('content'), ('happens'), ('preceding'), ('заместитель'), ('миллиона'), ('знают'), ('которая'), ('flowers'), ('orchestra'), ('mostly'), ('authorized'), ('gains'), ('hours'), ('fingers'), ('pathology'), ('applications'), ('дней'), ('wrote'), ('black'), ('agree'), ('negative'), ('religious'), ('historic'), ('wood'), ('hate'), ('solely'), ('budget'), ('делать'), ('anyway'), ('html'), ('colorful'), ('lightly'), ('below'), ('create'), ('during'), ('sentiment'), ('continuity'), ('bread'), ('altered'), ('frozen'), ('centers'), ('encountered'), ('schools'), ('probable'), ('greatly'), ('multiple'), ('deeper'), ('cases'), ('speak'), ('grade'), ('pounds'), ('Алексей'), ('temporary'), ('chosen'), ('mystery'), ('equally'), ('methods'), ('contracts'), ('drink'), ('darkness'), ('recently'), ('moves'), ('sad'), ('depth'), ('Его'), ('warned'), ('которого'), ('resolution'), ('lady'), ('painted'), ('эту'), ('whispered'), ('writing'), ('faint'), ('call'), ('classes'), ('excite'), ('environment'), ('могут'), ('comment'), ('filed'), ('rising'), ('symbols'), ('distributed'), ('capital'), ('items'), ('сколько'), ('plural'), ('считают'), ('вот'), ('waters'), ('entries'), ('steel'), ('suits'), ('средств'), ('distinction'), ('relative'), ('contract'), ('pst'), ('courts'), ('details'), ('open'), ('significant'), ('expressing'), ('extended'), ('magnitude'), ('forms'), ('mobile'), ('neutral'), ('argument'), ('have'), ('contained'), ('skywave'), ('height'), ('pressed'), ('encounter'), ('singing'), ('spirits'), ('talk'), ('dog'), ('bod'), ('designed'), ('bundle'), ('pupil'), ('тысяч'), ('desperately'), ('post'), ('easily'), ('shared'), ('biggest'), ('subtle'), ('comes'), ('legislation'), ('ears'), ('paused'), ('arrive'), ('polynomial'), ('opposite'), ('pack'), ('прошлого'), ('connection'), ('they'), ('listening'), ('definition'), ('factories'), ('fairly'), ('образом'), ('wished'), ('arrival'), ('climbed'), ('honey'), ('remarkable'), ('sales'), ('troops'), ('meaningful'), ('rational'), ('whatever'), ('removal'), ('horses'), ('successes'), ('weak'), ('caught'), ('Михаил'), ('according'), ('grass'), ('region'), ('нашего'), ('arranged'), ('monthly'), ('cycle'), ('провести'), ('ships'), ('allotment'), ('oh'), ('joint'), ('replied'), ('helping'), ('showing'), ('feet'), ('language'), ('suggest'), ('bag'), ('staff'), ('colonial'), ('release'), ('satisfied'), ('cooking'), ('promotion'), ('directions'), ('давно'), ('carrying'), ('manufacturer'), ('меры'), ('amounts'), ('одним'), ('snake'), ('recording'), ('начальника'), ('assured'), ('anybody'), ('пути'), ('radiation'), ('право'), ('for'), ('submitted'), ('конференции'), ('pick'), ('clean'), ('consisting'), ('main'), ('questionnaire'), ('morning'), ('nerves'), ('lesson'), ('upward'), ('classification'), ('reminded'), ('conferences'), ('basic'), ('акций'), ('ноября'), ('blue'), ('drive'), ('interior'), ('alternative'), ('constantly'), ('mail'), ('advice'), ('substantially'), ('testimony'), ('saved'), ('effects'), ('suggestions'), ('receiving'), ('город'), ('excellent'), ('protein'), ('roots'), ('Именно'), ('newly'), ('somewhere'), ('каким'), ('date'), ('meal'), ('concerned'), ('opening'), ('buy'), ('autumn'), ('reasonably'), ('conventional'), ('marble'), ('life'), ('extend'), ('tested'), ('subject'), ('wit'), ('basement'), ('marketing'), ('happening'), ('moment'), ('odd'), ('permanent'), ('лишь'), ('Чтобы'), ('energy'), ('system'), ('mirror'), ('month'), ('brings'), ('lb.'), ('maturity'), ('dir'), ('uncertain'), ('closing'), ('nowhere'), ('desirable'), ('every'), ('количество'), ('Если'), ('isolated'), ('a'), ('model'), ('appears'), ('national'), ('они'), ('ma'), ('reserve'), ('policy'), ('terrible'), ('stand'), ('pushed'), ('addition'), ('lifted'), ('neighbors'), ('fist'), ('eyes'), ('risk'), ('aroused'), ('care'), ('addressed'), ('isn'), ('livejournal'), ('cattle'), ('hypothalamic'), ('charoff'), ('explain'), ('sky'), ('период'), ('beginning'), ('нему'), ('pressing'), ('desires'), ('spoke'), ('каждого'), ('drama'), ('heat'), ('permits'), ('который'), ('numeral'), ('rank'), ('highly'), ('rifles'), ('slow'), ('similarly'), ('soil'), ('map'), ('on'), ('inner'), ('measured'), ('strictly'), ('benefit'), ('dreamed'), ('об'), ('beside'), ('affect'), ('чего'), ('survive'), ('standards'), ('injury'), ('dull'), ('passages'), ('errors'), ('visit'), ('сообщил'), ('case'), ('ages'), ('regime'), ('proper'), ('могли'), ('mouth'), ('Ну'), ('places'), ('slight'), ('frequencies'), ('ago'), ('Борис'), ('observation'), ('organized'), ('silver'), ('mistake'), ('shoe'), ('районе'), ('effectively'), ('attract'), ('surface'), ('facing'), ('slip'), ('lean'), ('blow'), ('его'), ('mass'), ('about'), ('down'), ('crack'), ('lively'), ('roles'), ('articles'), ('defined'), ('новые'), ('stressed'), ('prove'), ('Тогда'), ('кстати'), ('chart'), ('rhythm'), ('reputation'), ('Среди'), ('где'), ('dead'), ('log'), ('together'), ('girls'), ('maybe'), ('Уже'), ('addresses'), ('continuous'), ('animal'), ('конечно'), ('formed'), ('unusual'), ('changing'), ('primitive'), ('cold'), ('normal'), ('пока'), ('Ассошиэйтед'), ('circles'), ('technical'), ('Нет'), ('trace'), ('всего'), ('extra'), ('own'), ('speeches'), ('touched'), ('одном'), ('у'), ('contemporary'), ('equate'), ('rope'), ('goods'), ('east'), ('yards'), ('continent'), ('improved'), ('security'), ('сборной'), ('statements'), ('утверждает'), ('games'), ('cheap'), ('wages'), ('сами'), ('advised'), ('dilemma'), ('stared'), ('все'), ('representing'), ('operation'), ('Есть'), ('naval'), ('transportation'), ('политики'), ('crawled'), ('station'), ('art'), ('wound'), ('местных'), ('departments'), ('главе'), ('truly'), ('наша'), ('feelings'), ('varied'), ('lived'), ('yield'), ('под'), ('собой'), ('innocence'), ('includes'), ('citizens'), ('understood'), ('returns'), ('своему'), ('active'), ('resolved'), ('seat'), ('happened'), ('shelters'), ('gear'), ('thick'), ('impact'), ('shame'), ('thoughts'), ('evident'), ('examine'), ('diplomatic'), ('achieved'), ('manufacturing'), ('run'), ('пост'), ('smart'), ('raising'), ('ссылка'), ('answer'), ('letting'), ('getting'), ('oil'), ('please'), ('everybody'), ('distance'), ('slim'), ('pistol'), ('deck'), ('triangle'), ('нынешнего'), ('января'), ('civilization'), ('destructive'), ('currently'), ('satisfactory'), ('вся'), ('farm'), ('opened'), ('rnd'), ('conceived'), ('signs'), ('aside'), ('speaker'), ('defeat'), ('added'), ('collection'), ('frame'), ('face'), ('remains'), ('to'), ('права'), ('decent'), ('home'), ('revealed'), ('hotels'), ('ease'), ('movement'), ('tsunami'), ('provided'), ('couple'), ('large'), ('plug'), ('На'), ('variations'), ('removed'), ('relatively'), ('sense'), ('counties'), ('земли'), ('lawyers'), ('literally'), ('hands'), ('sidewalk'), ('людям'), ('attempt'), ('physically'), ('laughter'), ('lawyer'), ('rock'), ('Можно'), ('случае'), ('built'), ('производство'), ('grand'), ('legend'), ('luxury'), ('chemical'), ('puts'), ('acquire'), ('worries'), ('memory'), ('treatment'), ('strain'), ('gathered'), ('thorough'), ('accuracy'), ('nation'), ('separated'), ('damage'), ('types'), ('disk'), ('bones'), ('accepting'), ('opposition'), ('judgments'), ('are'), ('abroad'), ('long'), ('градусов'), ('hunt'), ('credit'), ('determine'), ('specialists'), ('force'), ('trembling'), ('hen'), ('experiments'), ('vs'), ('measure'), ('become'), ('initial'), ('phenomenon'), ('snapped'), ('Андрей'), ('my'), ('took'), ('diet'), ('category'), ('central'), ('expect'), ('burned'), ('saline'), ('presentation'), ('history'), ('elements'), ('fit'), ('эти'), ('entering'), ('letter'), ('seems'), ('consideration'), ('awake'), ('движения'), ('inclined'), ('careful'), ('peoples'), ('several'), ('rest'), ('tournament'), ('Конечно'), ('temperatures'), ('operator'), ('generations'), ('Нью'), ('pleased'), ('arrangements'), ('степени'), ('assistance'), ('said'), ('sovereign'), ('swing'), ('generation'), ('aware'), ('chose'), ('driver'), ('lead'), ('leaves'), ('comparable'), ('discipline'), ('plate'), ('wishes'), ('feature'), ('fitted'), ('явно'), ('might'), ('record'), ('sing'), ('sixty'), ('emphasize'), ('tend'), ('сказал'), ('невозможно'), ('Известия'), ('feel'), ('stable'), ('unhappy'), ('favorable'), ('mechanism'), ('cousin'), ('treat'), ('whose'), ('corresponding'), ('livestock'), ('council'), ('thinking'), ('discussion'), ('guards'), ('mile'), ('channels'), ('heart'), ('romantic'), ('legs'), ('water'), ('border'), ('openly'), ('started'), ('talked'), ('moderate'), ('beings'), ('shear'), ('всей'), ('whisky'), ('премьер'), ('края'), ('encourage'), ('engineering'), ('second'), ('mechanical'), ('scheme'), ('bound'), ('skill'), ('uncle'), ('nov'), ('minds'), ('hearts'), ('heaven'), ('leg'), ('october'), ('может'), ('сотрудники'), ('suitcase'), ('impressions'), ('furthermore'), ('reported'), ('fall'), ('tagged'), ('группы'), ('lobby'), ('mature'), ('foams'), ('work'), ('generous'), ('самым'), ('stories'), ('можно'), ('downtown'), ('naturally'), ('lock'), ('landing'), ('Впрочем'), ('Один'), ('sell'), ('некоторого'), ('readers'), ('miles'), ('conducted'), ('images'), ('service'), ('ways'), ('emerged'), ('whether'), ('forever'), ('tones'), ('guidance'), ('three'), ('Эта'), ('coating'), ('april'), ('reference'), ('electron'), ('feeling'), ('specifically'), ('loyalty'), ('hearing'), ('mix'), ('was'), ('некоторых'), ('mathematical'), ('wisdom'), ('thanks'), ('которое'), ('enjoyed'), ('two'), ('silence'), ('arbitrary'), ('grave'), ('является'), ('count'), ('each'), ('deny'), ('parks'), ('succeeded'), ('wish'), ('controlling'), ('Они'), ('engineers'), ('promise'), ('role'), ('court'), ('большой'), ('technique'), ('combat'), ('backed'), ('часов'), ('pencil'), ('unfortunate'), ('attention'), ('it'), ('progress'), ('minor'), ('ситуацию'), ('structures'), ('plot'), ('mixed'), ('четырех'), ('самом'), ('motives'), ('органы'), ('greeted'), ('однако'), ('wouldn'), ('weight'), ('countries'), ('suggests'), ('full'), ('identification'), ('stock'), ('tough'), ('reality'), ('whereby'), ('fees'), ('pieces'), ('finished'), ('smile'), ('half'), ('bars'), ('excited'), ('fifth'), ('efficient'), ('realistic'), ('keys'), ('close'), ('recognized'), ('limit'), ('прошла'), ('available'), ('boat'), ('кажется'), ('раз'), ('doubt'), ('drawn'), ('panic'), ('approved'), ('customer'), ('block'), ('hidden'), ('however'), ('servants'), ('testing'), ('accompanied'), ('этом'), ('municipal'), ('grow'), ('bird'), ('отношения'), ('double'), ('session'), ('patients'), ('realism'), ('sum'), ('passes'), ('shots'), ('curt'), ('output'), ('muscle'), ('one'), ('valuable'), ('hardly'), ('minimum'), ('mission'), ('brief'), ('find'), ('rooms'), ('employee'), ('estimated'), ('prepare'), ('днях'), ('kid'), ('вместо'), ('decision'), ('идет'), ('allowed'), ('site'), ('unions'), ('Для'), ('year'), ('institution'), ('speech'), ('другие'), ('net'), ('let'), ('races'), ('laboratory'), ('assignment'), ('очередной'), ('among'), ('система'), ('considered'), ('muscles'), ('comedy'), ('threatening'), ('во'), ('soap'), ('worst'), ('witness'), ('approval'), ('golf'), ('Известий'), ('imagined'), ('стороны'), ('sep'), ('ситуации'), ('electronics'), ('shouldn'), ('при'), ('conscious'), ('proportion'), ('january'), ('trees'), ('jumped'), ('thousand'), ('breakfast'), ('competitive'), ('nights'), ('possession'), ('reasons'), ('завода'), ('private'), ('eighth'), ('light'), ('tonight'), ('века'), ('listed'), ('happen'), ('title'), ('poverty'), ('будет'), ('rule'), ('objective'), ('still'), ('wind'), ('direction'), ('cover'), ('knocked'), ('will'), ('developments'), ('command'), ('срок'), ('covering'), ('skin'), ('firm'), ('magnet'), ('главы'), ('average'), ('warning'), ('convictions'), ('arrest'), ('practices'), ('rain'), ('network'), ('surplus'), ('theories'), ('future'), ('новостей'), ('cause'), ('quite'), ('sample'), ('Когда'), ('ecumenical'), ('very'), ('emphasis'), ('que'), ('inch'), ('usually'), ('sewage'), ('status'), ('части'), ('nice'), ('этой'), ('problem'), ('часть'), ('того'), ('sitter'), ('warrant'), ('avoid'), ('produced'), ('А'), ('tight'), ('unexpected'), ('signed'), ('component'), ('dry'), ('became'), ('stairs'), ('решили'), ('работе'), ('payments'), ('sweat'), ('нужно'), ('popular'), ('numbers'), ('percent'), ('warm'), ('exactly'), ('judges'), ('ft.'), ('theater'), ('strip'), ('thereby'), ('feels'), ('traffic'), ('stars'), ('moral'), ('свет'), ('handle'), ('одной'), ('т'), ('П'), ('equipment'), ('dress'), ('alike'), ('doubtful'), ('чтобы'), ('второй'), ('indeed'), ('dedicated'), ('bringing'), ('demand'), ('ratio'), ('blanket'), ('hunting'), ('deeply'), ('самый'), ('stopped'), ('Кроме'), ('retired'), ('then'), ('dominated'), ('человека'), ('storage'), ('coverage'), ('fifteen'), ('segment'), ('начале'), ('fantastic'), ('bear'), ('governmental'), ('pitch'), ('converted'), ('партия'), ('ring'), ('steam'), ('satisfaction'), ('milligrams'), ('руки'), ('reserved'), ('suit'), ('хотя'), ('direct'), ('interference'), ('bomb'), ('amp'), ('вместе'), ('tired'), ('утверждают'), ('Во'), ('значит'), ('connected'), ('billion'), ('quantity'), ('никогда'), ('blood'), ('involving'), ('sat'), ('weeks'), ('facilities'), ('команды'), ('bases'), ('civil'), ('dimensions'), ('cars'), ('formula'), ('thermal'), ('от'), ('losing'), ('deep'), ('horizon'), ('due'), ('argued'), ('уже'), ('guided'), ('collected'), ('sun'), ('increased'), ('toes'), ('frequent'), ('год'), ('offices'), ('six'), ('frames'), ('approached'), ('moreover'), ('quality'), ('extreme'), ('suited'), ('food'), ('often'), ('remembered'), ('vacation'), ('intensity'), ('reflect'), ('raw'), ('replacement'), ('vision'), ('Еще'), ('decline'), ('thus'), ('daily'), ('similar'), ('cloth'), ('guns'), ('всегда'), ('bright'), ('difficulty'), ('summer'), ('waste'), ('push'), ('changes'), ('hold'), ('asleep'), ('areas'), ('precise'), ('described'), ('felt'), ('relationships'), ('indicate'), ('same'), ('reporter'), ('believed'), ('named'), ('criticism'), ('rich'), ('expects'), ('branches'), ('situations'), ('factory'), ('operate'), ('prison'), ('license'), ('explanation'), ('glory'), ('allow'), ('merit'), ('temporarily'), ('hour'), ('да'), ('larger'), ('loose'), ('others'), ('развития'), ('scholarship'), ('tool'), ('весьма'), ('sent'), ('president'), ('должен'), ('politics'), ('transition'), ('occupied'), ('nude'), ('mount'), ('предприятия'), ('impressive'), ('рядом'), ('же'), ('четыре'), ('grows'), ('те'), ('fault'), ('here'), ('orders'), ('born'), ('motor'), ('shade'), ('говорят'), ('guilty'), ('complained'), ('aspects'), ('mothers'), ('документы'), ('boss'), ('raised'), ('spot'), ('spread'), ('expressed'), ('Рейтер'), ('partisan'), ('given'), ('yet'), ('friends'), ('juniors'), ('два'), ('denied'), ('стать'), ('duties'), ('broke'), ('protest'), ('encouraged'), ('chain'), ('shining'), ('роль'), ('глава'), ('separate'), ('official'), ('solve'), ('principal'), ('процентов'), ('ad'), ('insect'), ('article'), ('день'), ('connect'), ('link'), ('feed'), ('between'), ('convenient'), ('complement'), ('sailing'), ('Сергея'), ('lives'), ('reply'), ('residential'), ('sessions'), ('book'), ('parts'), ('determining'), ('hollywood'), ('truth'), ('Владимира'), ('parallel'), ('judgment'), ('passage'), ('put'), ('dealers'), ('работу'), ('pdt'), ('verb'), ('listeners'), ('controls'), ('won'), ('arrested'), ('slid'), ('fail'), ('fort'), ('acceptable'), ('bronchial'), ('willing'), ('нам'), ('выше'), ('female'), ('expert'), ('dinner'), ('though'), ('heroic'), ('incident'), ('всю'), ('attack'), ('gesture'), ('operating'), ('enable'), ('километров'), ('крупных'), ('secret'), ('branch'), ('urge'), ('наш'), ('visited'), ('площади'), ('motive'), ('thought'), ('trial'), ('mixture'), ('offer'), ('kill'), ('мы'), ('могла'), ('continuing'), ('dramatic'), ('столице'), ('transferred'), ('urgent'), ('tuesday'), ('assure'), ('jail'), ('presumably'), ('publication'), ('www'), ('women'), ('adequate'), ('looked'), ('недели'), ('beer'), ('controlled'), ('опять'), ('gay'), ('am'), ('mood'), ('public'), ('youngsters'), ('pattern'), ('fully'), ('довольно'), ('делу'), ('essentially'), ('entry'), ('taking'), ('время'), ('beliefs'), ('racial'), ('day'), ('tractor'), ('determination'), ('problems'), ('cooperative'), ('agents'), ('lowered'), ('engineer'), ('suppose'), ('ничего'), ('magazines'), ('reflected'), ('must'), ('Из'), ('eleven'), ('body'), ('anyhow'), ('characteristics'), ('imagination'), ('легко'), ('illness'), ('sections'), ('washing'), ('able'), ('faces'), ('работавшую'), ('style'), ('companies'), ('path'), ('using'), ('впервые'), ('justify'), ('hole'), ('single'), ('observe'), ('signal'), ('drew'), ('pocket'), ('advantage'), ('since'), ('multiply'), ('Все'), ('reactions'), ('critical'), ('residents'), ('television'), ('contrary'), ('dive'), ('bent'), ('stresses'), ('сделать'), ('ethics'), ('Пока'), ('pulled'), ('shoes'), ('swung'), ('ever'), ('sale'), ('normally'), ('ТАСС'), ('admitted'), ('членов'), ('fourth'), ('namely'), ('consumer'), ('radar'), ('Этот'), ('appeared'), ('sets'), ('inspired'), ('upper'), ('backward'), ('wooden'), ('При'), ('народа'), ('assumptions'), ('encouraging'), ('dogs'), ('сто'), ('compare'), ('literature'), ('clearly'), ('scheduled'), ('himself'), ('Многие'), ('always'), ('lost'), ('glad'), ('tone'), ('следует'), ('watched'), ('boards'), ('properties'), ('machines'), ('county'), ('noon'), ('touch'), ('tire'), ('written'), ('limited'), ('unable'), ('Даже'), ('bullets'), ('alive'), ('completed'), ('взгляд'), ('easier'), ('directors'), ('часа'), ('species'), ('suffered'), ('принять'), ('actor'), ('within'), ('obtained'), ('crash'), ('первые'), ('одно'), ('led'), ('points'), ('Николай'), ('wants'), ('tongue'), ('М'), ('concluded'), ('covers'), ('jun'), ('exclusive'), ('obtain'), ('apparently'), ('somewhat'), ('dressed'), ('stream'), ('painful'), ('постоянно'), ('посколько'), ('justice'), ('myself'), ('ready'), ('spare'), ('центра'), ('приходится'), ('grains'), ('painting'), ('processing'), ('select'), ('store'), ('dreams'), ('response'), ('track'), ('trip'), ('имени'), ('domestic'), ('компания'), ('wear'), ('trips'), ('because'), ('прошлом'), ('Анатолий'), ('depends'), ('condition'), ('rights'), ('туда'), ('стали'), ('meetings'), ('skills'), ('pale'), ('dollars'), ('tiny'), ('machinery'), ('travel'), ('воскресение'), ('legal'), ('возможно'), ('prefer'), ('walking'), ('altogether'), ('вновь'), ('attended'), ('bank'), ('decade'), ('level'), ('covered'), ('tour'), ('vehicle'), ('train'), ('automobile'), ('friend'), ('словам'), ('do'), ('дни'), ('первым'), ('invariably'), ('garden'), ('shoulder'), ('perfectly'), ('создать'), ('smaller'), ('pioneer'), ('says'), ('asked'), ('spite'), ('occurring'), ('faculty'), ('recalled'), ('Только'), ('театра'), ('knees'), ('месте'), ('the'), ('речь'), ('done'), ('newspapers'), ('вам'), ('troubled'), ('frequency'), ('spring'), ('struggle'), ('remark'), ('стоит'), ('wife'), ('Не'), ('mar'), ('locking'), ('makers'), ('duck'), ('станет'), ('idea'), ('corner'), ('management'), ('cocktail'), ('vehicles'), ('complicated'), ('фирма'), ('slightly'), ('experimental'), ('empty'), ('joy'), ('equal'), ('команда'), ('достаточно'), ('Без'), ('надо'), ('mother'), ('honor'), ('absorbed'), ('broad'), ('летний'), ('shook'), ('delivery'), ('vary'), ('guy'), ('dust'), ('shore'), ('longer'), ('sixteen'), ('surprising'), ('помощи'), ('survival'), ('для'), ('mankind'), ('indicates'), ('нельзя'), ('originally'), ('them'), ('tribute'), ('optimal'), ('rifle'), ('вообще'), ('used'), ('жизни'), ('expanding'), ('steps'), ('tends'), ('story'), ('datetime'), ('hits'), ('considerable'), ('nor'), ('press'), ('when'), ('scared'), ('responsible'), ('background'), ('looks'), ('февраля'), ('ground'), ('закон'), ('beneath'), ('reached'), ('exists'), ('vocational'), ('historians'), ('argue'), ('coast'), ('beef'), ('wage'), ('remote'), ('challenge'), ('proposal'), ('вице'), ('pond'), ('finance'), ('корреспонденту'), ('furnished'), ('efforts'), ('drying'), ('enforcement'), ('fashion'), ('believe'), ('quickly'), ('melting'), ('otherwise'), ('desire'), ('дня'), ('reveal'), ('festival'), ('noble'), ('moving'), ('hence'), ('conduct'), ('promises'), ('accept'), ('fruit'), ('премьера'), ('rushed'), ('host'), ('served'), ('anywhere'), ('Мы'), ('раньше'), ('yes'), ('solid'), ('debate'), ('mode'), ('secure'), ('continually'), ('shall'), ('further'), ('happily'), ('mounted'), ('sign'), ('finds'), ('base'), ('colony'), ('relatives'), ('lang'), ('change'), ('хочет'), ('revolution'), ('стал'), ('И'), ('laughed'), ('необходимо'), ('ought'), ('november'), ('poem'), ('вы'), ('developing'), ('одна'), ('newspaper'), ('summary'), ('thirty'), ('никаких'), ('influence'), ('called'), ('realize'), ('responsibilities'), ('causes'), ('associate'), ('consisted'), ('sold'), ('insist'), ('step'), ('stress'), ('brushed'), ('прежде'), ('charged'), ('О'), ('communications'), ('considerations'), ('wing'), ('administration'), ('tradition'), ('правда'), ('objects'), ('promising'), ('unknown'), ('familiar'), ('machine'), ('musical'), ('names'), ('roughly'), ('adjusted'), ('centuries'), ('встречи'), ('crowded'), ('capacity'), ('своими'), ('point'), ('hand'), ('assumed'), ('minority'), ('практически'), ('performance'), ('взять'), ('gained'), ('strategic'), ('which'), ('любая'), ('loop'), ('есть'), ('realization'), ('только'), ('flow'), ('trap'), ('одновременно'), ('egg'), ('wagon'), ('Дело'), ('путь'), ('жизнь'), ('functions'), ('specified'), ('pull'), ('shaking'), ('small'), ('теперь'), ('divide'), ('found'), ('briefly'), ('conviction'), ('limits'), ('color'), ('struggling'), ('больше'), ('association'), ('lungs'), ('locked'), ('visible'), ('им'), ('стало'), ('женщины'), ('instead'), ('click'), ('sort'), ('sauce'), ('особенно'), ('game'), ('drank'), ('exposed'), ('reading'), ('staring'), ('accomplish'), ('bigger'), ('каких'), ('вас'), ('former'), ('Ведь'), ('сих'), ('vice'), ('repeated'), ('studio'), ('expectations'), ('другой'), ('ask'), ('даже'), ('качестве'), ('нем'), ('dozen'), ('training'), ('Кстати'), ('plant'), ('low'), ('nearly'), ('classic'), ('pure'), ('extension'), ('fifty'), ('contest'), ('течение'), ('across'), ('through'), ('while'), ('poetic'), ('tons'), ('theoretical'), ('inevitable'), ('herd'), ('refrigerator'), ('railroad'), ('руб'), ('funds'), ('held'), ('tangible'), ('mold'), ('gyro'), ('divorce'), ('clear'), ('oxidation'), ('torn'), ('take'), ('сентября'), ('например'), ('долго'), ('regulations'), ('developed'), ('дел'), ('seeking'), ('cigarette'), ('minute'), ('purposes'), ('impossible'), ('occasions'), ('пришлось'), ('claimed'), ('bullet'), ('linear'), ('состоянии'), ('любой'), ('books'), ('forum'), ('volunteers'), ('bgcolor'), ('formal'), ('transfer'), ('school'), ('maintained'), ('себе'), ('finally'), ('suffer'), ('тысячи'), ('try'), ('officer'), ('stems'), ('lose'), ('spoken'), ('circumstances'), ('amendment'), ('wings'), ('работать'), ('fell'), ('pause'), ('turns'), ('surrounded'), ('capabilities'), ('read'), ('stake'), ('stepped'), ('системы'), ('once'), ('unity'), ('дал'), ('killed'), ('respects'), ('enemy'), ('courage'), ('allies'), ('paint'), ('wore'), ('sunday'), ('window'), ('оказалась'), ('strategy'), ('films'), ('purpose'), ('ответ'), ('деятельности'), ('owners'), ('scattered'), ('inherent'), ('prospect'), ('instances'), ('stroke'), ('middle-class'), ('successful'), ('таких'), ('present'), ('apr'), ('republic'), ('minimal'), ('fog'), ('these'), ('решения'), ('floor'), ('intervention'), ('heavy'), ('see'), ('headed'), ('statement'), ('didn'), ('е'), ('peace'), ('preserve'), ('pose'), ('внимание'), ('night'), ('wherever'), ('drove'), ('joined'), ('hatred'), ('таки'), ('voting'), ('последние'), ('когда'), ('stem'), ('вдруг'), ('Их'), ('weather'), ('дела'), ('exhibit'), ('десять'), ('draw'), ('version'), ('common'), ('either'), ('health'), ('throughout'), ('paragraph'), ('driving'), ('review'), ('chord'), ('tried'), ('supposed'), ('вряд'), ('tells'), ('tag'), ('governor'), ('зрения'), ('walked'), ('correct'), ('enjoy'), ('gradually'), ('conductor'), ('rehabilitation'), ('substances'), ('Поэтому'), ('sang'), ('interpreted'), ('artery'), ('general'), ('maximum'), ('ряд'), ('noticed'), ('tent'), ('century'), ('merger'), ('agreed'), ('phrase'), ('quiet'), ('flexible'), ('five'), ('task'), ('confusion'), ('bitter'), ('traders'), ('auto'), ('ultimate'), ('clock'), ('concerns'), ('closer'), ('очередь'), ('quoted'), ('club'), ('gently'), ('prepared'), ('list'), ('adult'), ('out'), ('promptly'), ('accident'), ('compete'), ('tell'), ('вполне'), ('seem'), ('marshall'), ('glance'), ('leave'), ('stage'), ('massive'), ('core'), ('supper'), ('section'), ('size'), ('desk'), ('appointed'), ('estimates'), ('editor'), ('extremely'), ('вокруг'), ('dances'), ('categories'), ('spending'), ('side'), ('поскольку'), ('действий'), ('fired'), ('street'), ('town'), ('shirt'), ('font'), ('сама'), ('cloud'), ('membership'), ('tasks'), ('expense'), ('acting'), ('enough'), ('social'), ('raise'), ('affair'), ('designs'), ('helped'), ('balance'), ('modern'), ('completely'), ('существует'), ('songs'), ('electrical'), ('lines'), ('homes'), ('первая'), ('safety'), ('short'), ('gold'), ('been'), ('requires'), ('unlike'), ('troubles'), ('looking'), ('controversy'), ('которых'), ('doctrine'), ('genuine'), ('firmly'), ('paid'), ('chance'), ('eve'), ('announcement'), ('Может'), ('instant'), ('millions'), ('majority'), ('carry'), ('name'), ('spirit'), ('раза'), ('instance'), ('simply'), ('door'), ('tube'), ('друг'), ('prices'), ('learn'), ('основном'), ('такой'), ('известно'), ('guilt'), ('Да'), ('вторая'), ('detergent'), ('attacked'), ('extending'), ('чем'), ('edition'), ('investigation'), ('dealing'), ('certainty'), ('mdt'), ('existing'), ('revolutionary'), ('Б'), ('правило'), ('уровень'), ('appreciation'), ('require'), ('sides'), ('philosophy'), ('strikes'), ('attorney'), ('substitute'), ('ethical'), ('glasses'), ('visitors'), ('requirement'), ('ride'), ('блог'), ('spots'), ('head'), ('sister'), ('claims'), ('anything'), ('sin'), ('burn'), ('starting'), ('delight'), ('наконец'), ('latest'), ('consists'), ('noted'), ('works'), ('stomach'), ('cream'), ('volumes'), ('us'), ('genius'), ('hang'), ('highest'), ('anode'), ('residence'), ('crossed'), ('peaceful'), ('brought'), ('granted'), ('shop'), ('thing'), ('rear'), ('around'), ('phenomena'), ('avoided'), ('along'), ('binding'), ('cannot'), ('not'), ('butter'), ('mark'), ('leaped'), ('listen'), ('years'), ('loss'), ('bought'), ('brown'), ('folk'), ('principles'), ('improvements'), ('проблема'), ('editorial'), ('effectiveness'), ('marriages'), ('remain'), ('июня'), ('circular'), ('jacket'), ('division'), ('quarter'), ('drop'), ('football'), ('underground'), ('invention'), ('stupid'), ('informed'), ('города'), ('selection'), ('она'), ('severe'), ('services'), ('reduced'), ('repair'), ('party'), ('tags'), ('области'), ('demands'), ('remained'), ('live'), ('counter'), ('times'), ('sergeant'), ('совсем'), ('standard'), ('workers'), ('courses'), ('soul'), ('community'), ('pair'), ('pupils'), ('answers'), ('before'), ('success'), ('represents'), ('fought'), ('получить'), ('persons'), ('checked'), ('team'), ('room'), ('appearance'), ('high'), ('saw'), ('availability'), ('demonstrated'), ('destroy'), ('picture'), ('или'), ('сделал'), ('exploration'), ('first'), ('рода'), ('seriously'), ('scene'), ('происходит'), ('candidate'), ('structure'), ('totally');INSERT INTO stopword_stems_long (stopword_stem) VALUES ('cope'), ('recommend'), ('email'), ('aid'), ('мог'), ('modest'), ('million'), ('как'), ('calm'), ('taken'), ('nearest'), ('sole'), ('vigor'), ('load'), ('what'), ('religi'), ('prompt'), ('rigid'), ('compos'), ('gray'), ('saddl'), ('wherev'), ('atmospher'), ('shown'), ('custom'), ('trust'), ('serv'), ('corn'), ('arteri'), ('previous'), ('jan'), ('occupi'), ('interview'), ('bay'), ('insight'), ('access'), ('confer'), ('board'), ('facil'), ('теб'), ('can'), ('wild'), ('land'), ('юр'), ('regiment'), ('отношен'), ('wait'), ('favor'), ('bit'), ('merchant'), ('недел'), ('дом'), ('fluid'), ('bench'), ('arc'), ('address'), ('urban'), ('впроч'), ('knew'), ('crop'), ('sympathet'), ('me'), ('кто'), ('encount'), ('имеют'), ('by'), ('goal'), ('thank'), ('type'), ('могл'), ('whatev'), ('fair'), ('tragic'), ('injur'), ('project'), ('assessor'), ('cool'), ('flesh'), ('secur'), ('фот'), ('marbl'), ('cow'), ('check'), ('share'), ('народ'), ('context'), ('death'), ('farther'), ('communism'), ('complet'), ('dine'), ('note'), ('proof'), ('there'), ('indirect'), ('reliabl'), ('amend'), ('verbal'), ('eye'), ('patent'), ('crazi'), ('market'), ('temporari'), ('fight'), ('despair'), ('stretch'), ('должн'), ('перед'), ('guard'), ('rate'), ('gone'), ('наход'), ('matter'), ('race'), ('ran'), ('south'), ('внов'), ('recreat'), ('video'), ('quart'), ('crown'), ('их'), ('remaind'), ('reprint'), ('lift'), ('top'), ('afternoon'), ('precis'), ('novemb'), ('след'), ('sharpli'), ('guest'), ('beard'), ('front'), ('stair'), ('local'), ('certain'), ('sink'), ('revolutionari'), ('и'), ('barrel'), ('occur'), ('он'), ('pursuant'), ('toss'), ('del'), ('vowel'), ('employ'), ('fish'), ('powder'), ('amount'), ('конференц'), ('ear'), ('entir'), ('reader'), ('vari'), ('accompani'), ('завод'), ('aesthet'), ('hear'), ('item'), ('octob'), ('truck'), ('express'), ('regist'), ('satisfi'), ('few'), ('suspicion'), ('тасс'), ('whom'), ('government'), ('told'), ('show'), ('win'), ('очеред'), ('drill'), ('пут'), ('companion'), ('трех'), ('york'), ('lack'), ('veloc'), ('price'), ('divorc'), ('wheel'), ('информац'), ('wash'), ('even'), ('вопрос'), ('finish'), ('contact'), ('part-tim'), ('famous'), ('posit'), ('breath'), ('penni'), ('medicin'), ('should'), ('experienc'), ('слов'), ('ourselv'), ('pretti'), ('divis'), ('plane'), ('позиц'), ('he'), ('sail'), ('fresh'), ('condemn'), ('return'), ('tendenc'), ('gather'), ('artist'), ('качеств'), ('patrol'), ('necessarili'), ('attitud'), ('purchas'), ('gestur'), ('seek'), ('serious'), ('urg'), ('рейтер'), ('сдела'), ('drunk'), ('постоя'), ('корреспондент'), ('mention'), ('stone'), ('automat'), ('rose'), ('январ'), ('river'), ('liquid'), ('bar'), ('fine'), ('precious'), ('keep'), ('better'), ('б'), ('worri'), ('explicit'), ('dancer'), ('pace'), ('valign'), ('taught'), ('jet'), ('cgi'), ('interest'), ('chick'), ('факт'), ('em'), ('poor'), ('final'), ('hide'), ('жизн'), ('and'), ('вовс'), ('chanc'), ('о'), ('dri'), ('личн'), ('panel'), ('spend'), ('excess'), ('men'), ('la'), ('watch'), ('сво'), ('think'), ('histor'), ('landscap'), ('cycl'), ('pour'), ('хорош'), ('marshal'), ('painter'), ('октябр'), ('danger'), ('settlement'), ('inform'), ('build'), ('commerc'), ('index'), ('г'), ('emerg'), ('dealer'), ('несмотр'), ('academ'), ('sixti'), ('yourself'), ('eg'), ('off'), ('updat'), ('tradit'), ('veteran'), ('mainten'), ('triumph'), ('созда'), ('secondari'), ('persuad'), ('театр'), ('passion'), ('latter'), ('known'), ('garag'), ('era'), ('flash'), ('introduc'), ('дальш'), ('newspap'), ('pleasur'), ('работ'), ('pile'), ('champion'), ('собствен'), ('бы'), ('чащ'), ('word'), ('displac'), ('achiev'), ('pm'), ('нич'), ('hell'), ('inevit'), ('stare'), ('главн'), ('reorgan'), ('disput'), ('struggl'), ('ham'), ('rent'), ('director'), ('financi'), ('прежн'), ('norm'), ('deal'), ('nearbi'), ('elimin'), ('person'), ('shell'), ('sympathi'), ('punish'), ('silenc'), ('clariti'), ('owner'), ('kingdom'), ('jazz'), ('cri'), ('vacat'), ('нача'), ('magnitud'), ('onli'), ('that'), ('slide'), ('fiction'), ('milk'), ('green'), ('существ'), ('nest'), ('activ'), ('graduat'), ('двух'), ('chairman'), ('furnish'), ('line'), ('knee'), ('someth'), ('yellow'), ('emphasi'), ('зна'), ('historian'), ('комисс'), ('enorm'), ('dollar'), ('theori'), ('shout'), ('fled'), ('probabl'), ('somebodi'), ('veri'), ('result'), ('logic'), ('partner'), ('vast'), ('healthi'), ('delay'), ('dec'), ('helpless'), ('web'), ('factori'), ('burden'), ('выш'), ('text'), ('борис'), ('cooper'), ('real'), ('set'), ('typic'), ('obvious'), ('candid'), ('architect'), ('wire'), ('rehabilit'), ('simpl'), ('job'), ('ты'), ('plus'), ('necess'), ('detail'), ('agent'), ('giant'), ('circl'), ('met'), ('leader'), ('всег'), ('stumbl'), ('то'), ('need'), ('tooth'), ('earth'), ('white'), ('oper'), ('or'), ('potenti'), ('could'), ('wonder'), ('musician'), ('количеств'), ('ваш'), ('compar'), ('januari'), ('per'), ('port'), ('fewer'), ('process'), ('hr'), ('belief'), ('relat'), ('ceil'), ('ambigu'), ('research'), ('young'), ('distanc'), ('lunch'), ('center'), ('visitor'), ('voic'), ('survey'), ('bring'), ('laugh'), ('придет'), ('impuls'), ('sight'), ('religion'), ('gentleman'), ('vote'), ('lid'), ('perfect'), ('можн'), ('tale'), ('глав'), ('margin'), ('driven'), ('difficult'), ('три'), ('sleep'), ('birth'), ('policeman'), ('mm'), ('you'), ('intens'), ('both'), ('print'), ('threw'), ('program'), ('flew'), ('пресс'), ('reform'), ('pound'), ('power'), ('becam'), ('code'), ('diseas'), ('команд'), ('сообщ'), ('period'), ('although'), ('shut'), ('male'), ('claim'), ('old'), ('entri'), ('inspect'), ('earn'), ('nerv'), ('transit'), ('spectacular'), ('prior'), ('к'), ('comparison'), ('becom'), ('individu'), ('girl'), ('bore'), ('all'), ('хот'), ('livejourn'), ('speed'), ('либ'), ('categori'), ('attach'), ('за'), ('regular'), ('pass'), ('attain'), ('edt'), ('compet'), ('announc'), ('locat'), ('alik'), ('июл'), ('creation'), ('averag'), ('signific'), ('bodi'), ('youngster'), ('wet'), ('relief'), ('satisfactori'), ('would'), ('aunt'), ('no'), ('д'), ('storag'), ('earli'), ('нас'), ('anxious'), ('работа'), ('red'), ('steadi'), ('sentenc'), ('valley'), ('total'), ('grip'), ('voluntari'), ('mine'), ('support'), ('object'), ('add'), ('submit'), ('invent'), ('despit'), ('достаточн'), ('тог'), ('factor'), ('get'), ('control'), ('huge'), ('uncl'), ('definit'), ('don'), ('plenti'), ('car'), ('lobbi'), ('unless'), ('go'), ('brilliant'), ('bureau'), ('believ'), ('terribl'), ('portion'), ('itself'), ('долж'), ('surfac'), ('dish'), ('industri'), ('tree'), ('content'), ('adriv'), ('third'), ('monday'), ('знают'), ('profound'), ('orchestra'), ('boy'), ('перв'), ('senat'), ('govern'), ('stain'), ('wrote'), ('вмест'), ('black'), ('mate'), ('behind'), ('transport'), ('wood'), ('fee'), ('hate'), ('так'), ('shock'), ('budget'), ('anyway'), ('bad'), ('html'), ('genuin'), ('occasion'), ('increas'), ('initi'), ('below'), ('distribut'), ('recogn'), ('опя'), ('sentiment'), ('purpos'), ('afford'), ('особен'), ('bread'), ('зде'), ('bottom'), ('frozen'), ('expand'), ('approach'), ('deeper'), ('hot'), ('deni'), ('speak'), ('grade'), ('self'), ('domin'), ('produc'), ('eighteenth'), ('chosen'), ('belong'), ('сраз'), ('мест'), ('drink'), ('empir'), ('decis'), ('regul'), ('consequ'), ('счет'), ('threat'), ('character'), ('sad'), ('depth'), ('whi'), ('mobil'), ('enter'), ('развит'), ('дает'), ('foreign'), ('rather'), ('tast'), ('stuff'), ('exclus'), ('popul'), ('district'), ('basi'), ('age'), ('faint'), ('sewag'), ('resid'), ('colleagu'), ('plain'), ('sexual'), ('cure'), ('call'), ('hous'), ('luncheon'), ('nois'), ('quotient'), ('higher'), ('blog'), ('datetim'), ('smell'), ('draft'), ('могут'), ('comment'), ('isol'), ('petition'), ('mental'), ('substanc'), ('capabl'), ('прокуратур'), ('want'), ('plural'), ('busi'), ('cholesterol'), ('вот'), ('скор'), ('relev'), ('late'), ('steel'), ('valid'), ('key'), ('save'), ('средств'), ('foot'), ('prime'), ('plan'), ('particip'), ('rector'), ('contract'), ('выбор'), ('pst'), ('скольк'), ('simpli'), ('assumpt'), ('full-tim'), ('nobl'), ('avail'), ('open'), ('appear'), ('нынешн'), ('flexibl'), ('разн'), ('frequenc'), ('worker'), ('charter'), ('usual'), ('intervent'), ('howev'), ('compromis'), ('passag'), ('sourc'), ('gas'), ('ли'), ('area'), ('hope'), ('neutral'), ('die'), ('bath'), ('argument'), ('член'), ('knife'), ('loos'), ('have'), ('littl'), ('husband'), ('cook'), ('ecumen'), ('handl'), ('sheet'), ('exist'), ('height'), ('scholar'), ('right'), ('appli'), ('talk'), ('today'), ('dog'), ('bod'), ('кажд'), ('серге'), ('сказа'), ('intim'), ('pupil'), ('тысяч'), ('post'), ('предприят'), ('disappear'), ('прям'), ('approv'), ('besid'), ('biggest'), ('pot'), ('tail'), ('extent'), ('fix'), ('том'), ('doubl'), ('bond'), ('card'), ('человек'), ('мног'), ('legisl'), ('sick'), ('thursday'), ('pack'), ('four'), ('tremend'), ('they'), ('counti'), ('provid'), ('adopt'), ('итог'), ('cotton'), ('fire'), ('resolut'), ('действ'), ('attend'), ('fli'), ('dawn'), ('нью'), ('градус'), ('welcom'), ('theoret'), ('preliminari'), ('meat'), ('machineri'), ('нибуд'), ('пробл'), ('lip'), ('agenc'), ('honey'), ('absorb'), ('speci'), ('поэт'), ('occas'), ('wast'), ('порядк'), ('who'), ('clinic'), ('caught'), ('weak'), ('прежд'), ('grass'), ('insur'), ('region'), ('plastic'), ('wine'), ('preced'), ('season'), ('therebi'), ('diplomat'), ('luck'), ('beach'), ('состоян'), ('blame'), ('oh'), ('течен'), ('joint'), ('феврал'), ('massiv'), ('hair'), ('продукц'), ('зам'), ('feet'), ('suggest'), ('staff'), ('bag'), ('sea'), ('tie'), ('интерес'), ('один'), ('enemi'), ('ход'), ('worthi'), ('worn'), ('permiss'), ('апрел'), ('diffus'), ('hill'), ('hatr'), ('snake'), ('hypothalam'), ('convinc'), ('revenu'), ('duti'), ('далек'), ('theolog'), ('awar'), ('комитет'), ('dream'), ('xml'), ('capit'), ('themselv'), ('for'), ('empti'), ('руководител'), ('pick'), ('clean'), ('похож'), ('near'), ('main'), ('bridg'), ('shoot'), ('twenty-f'), ('upward'), ('lesson'), ('yesterday'), ('awak'), ('basic'), ('суббот'), ('vehicl'), ('never'), ('с'), ('matur'), ('interior'), ('drive'), ('blue'), ('tear'), ('mail'), ('distinguish'), ('piec'), ('silent'), ('player'), ('lung'), ('город'), ('групп'), ('protein'), ('action'), ('multipli'), ('memori'), ('shine'), ('meal'), ('date'), ('deepli'), ('moreov'), ('buy'), ('autumn'), ('fat'), ('approxim'), ('technic'), ('battl'), ('life'), ('extend'), ('над'), ('bare'), ('telephon'), ('subject'), ('absolut'), ('ма'), ('wit'), ('basement'), ('вперв'), ('moment'), ('odd'), ('arriv'), ('explan'), ('tabl'), ('system'), ('church'), ('mirror'), ('month'), ('lb.'), ('long-term'), ('author'), ('fraction'), ('uncertain'), ('dir'), ('magnific'), ('she'), ('widespread'), ('juli'), ('act'), ('throw'), ('valuabl'), ('exact'), ('virtual'), ('cheek'), ('fiber'), ('advantag'), ('angl'), ('defin'), ('туд'), ('way'), ('a'), ('neighbor'), ('model'), ('shelter'), ('realli'), ('площад'), ('environ'), ('salari'), ('ma'), ('wrong'), ('in'), ('everyth'), ('dispos'), ('вест'), ('stand'), ('occurr'), ('blockquot'), ('thrown'), ('себ'), ('оп'), ('fist'), ('dark'), ('risk'), ('слишк'), ('care'), ('isn'), ('colonel'), ('greet'), ('не'), ('safeti'), ('charoff'), ('explain'), ('sky'), ('период'), ('известн'), ('spoke'), ('рук'), ('drama'), ('heat'), ('librari'), ('harmoni'), ('singl'), ('titl'), ('damn'), ('rank'), ('quick'), ('fast'), ('slow'), ('vocat'), ('акц'), ('врод'), ('soil'), ('dare'), ('succeed'), ('languag'), ('poet'), ('on'), ('map'), ('август'), ('основн'), ('patient'), ('inner'), ('gentl'), ('pursu'), ('benefit'), ('об'), ('межд'), ('expenditur'), ('большинств'), ('match'), ('affect'), ('escap'), ('quantiti'), ('dull'), ('temperatur'), ('questionnair'), ('visit'), ('oversea'), ('case'), ('wildlif'), ('сут'), ('climb'), ('proper'), ('mouth'), ('смерт'), ('slight'), ('variat'), ('account'), ('unhappi'), ('philosoph'), ('festiv'), ('damag'), ('ago'), ('стольк'), ('земл'), ('nervous'), ('silver'), ('incid'), ('switch'), ('shoe'), ('attract'), ('уж'), ('ве'), ('slip'), ('lean'), ('blow'), ('jungl'), ('anyon'), ('futur'), ('outstand'), ('mass'), ('down'), ('about'), ('mst'), ('crack'), ('ie'), ('получ'), ('swept'), ('concentr'), ('incom'), ('территор'), ('prove'), ('those'), ('volunt'), ('hire'), ('entertain'), ('restaur'), ('away'), ('begun'), ('chart'), ('rhythm'), ('снов'), ('beyond'), ('где'), ('threaten'), ('dead'), ('я'), ('hesit'), ('say'), ('log'), ('enterpris'), ('narrat'), ('такж'), ('releas'), ('seldom'), ('sacr'), ('scatter'), ('score'), ('energi'), ('всех'), ('laboratori'), ('format'), ('certainti'), ('outdoor'), ('normal'), ('cold'), ('liberti'), ('каса'), ('mistak'), ('resum'), ('brick'), ('окол'), ('stiff'), ('trace'), ('extra'), ('own'), ('concret'), ('substrat'), ('у'), ('discharg'), ('rope'), ('east'), ('scarc'), ('peac'), ('somewher'), ('util'), ('upstair'), ('electr'), ('cheap'), ('barn'), ('later'), ('poetri'), ('creativ'), ('kept'), ('biolog'), ('equival'), ('emiss'), ('район'), ('dear'), ('dilemma'), ('все'), ('naval'), ('station'), ('art'), ('bold'), ('wound'), ('proud'), ('length'), ('ignor'), ('mathemat'), ('кра'), ('suitabl'), ('committe'), ('grin'), ('metal'), ('этот'), ('were'), ('procedur'), ('excus'), ('law'), ('understand'), ('yield'), ('под'), ('turn'), ('ком'), ('nake'), ('движен'), ('trembl'), ('specimen'), ('past'), ('iron'), ('ultim'), ('в'), ('когд'), ('understood'), ('поня'), ('cost'), ('chicken'), ('refund'), ('seat'), ('uniqu'), ('aug'), ('over-al'), ('gave'), ('gear'), ('thick'), ('impact'), ('shame'), ('elsewher'), ('руководств'), ('invit'), ('run'), ('applic'), ('smart'), ('пост'), ('област'), ('agre'), ('соб'), ('triangl'), ('radiat'), ('notabl'), ('under'), ('answer'), ('contrast'), ('видим'), ('oil'), ('harder'), ('вниман'), ('cattl'), ('feb'), ('presum'), ('move'), ('appoint'), ('slim'), ('pistol'), ('deck'), ('our'), ('contrari'), ('absenc'), ('lo'), ('distinct'), ('новост'), ('danc'), ('earlier'), ('textil'), ('вся'), ('farm'), ('surround'), ('femal'), ('утвержда'), ('pertin'), ('rnd'), ('union'), ('liber'), ('brother'), ('otherwis'), ('speaker'), ('administr'), ('defeat'), ('pulmonari'), ('channel'), ('frame'), ('appreci'), ('we'), ('hasn'), ('face'), ('ideolog'), ('briefli'), ('to'), ('group'), ('unexpect'), ('motion'), ('home'), ('decent'), ('grab'), ('быстр'), ('payment'), ('tsunami'), ('movement'), ('radio'), ('plug'), ('proceed'), ('nineteenth'), ('дан'), ('ocean'), ('an'), ('binomi'), ('bed'), ('bottl'), ('neck'), ('sidewalk'), ('выясн'), ('attempt'), ('laughter'), ('lawyer'), ('coloni'), ('soon'), ('rock'), ('built'), ('permit'), ('wipe'), ('legend'), ('grand'), ('origin'), ('а'), ('romant'), ('jump'), ('end'), ('кажет'), ('treatment'), ('splendid'), ('strain'), ('excel'), ('miss'), ('pride'), ('thorough'), ('nation'), ('reach'), ('disk'), ('are'), ('abroad'), ('unlik'), ('beauti'), ('long'), ('pilot'), ('great'), ('чтоб'), ('hunt'), ('particular'), ('credit'), ('without'), ('than'), ('mayb'), ('hen'), ('век'), ('long-rang'), ('just'), ('vs'), ('phenomenon'), ('automobil'), ('вед'), ('usernam'), ('earliest'), ('strike'), ('composit'), ('cafe'), ('my'), ('took'), ('improv'), ('diet'), ('central'), ('expect'), ('consum'), ('четыр'), ('symbol'), ('fit'), ('technolog'), ('provis'), ('settl'), ('letter'), ('happi'), ('втор'), ('follow'), ('effort'), ('rest'), ('tournament'), ('участник'), ('rapid'), ('endless'), ('woman'), ('impress'), ('zero'), ('commission'), ('altogeth'), ('said'), ('neat'), ('sovereign'), ('заявлен'), ('назад'), ('swing'), ('conspiraci'), ('saturday'), ('char'), ('chose'), ('driver'), ('lead'), ('chair'), ('narrow'), ('depart'), ('plate'), ('yell'), ('might'), ('record'), ('fifti'), ('order'), ('sing'), ('prize'), ('qualifi'), ('пят'), ('parent'), ('крупн'), ('destini'), ('figur'), ('friday'), ('tend'), ('тот'), ('data'), ('fed'), ('однак'), ('year-old'), ('feel'), ('вод'), ('labour'), ('fan'), ('cousin'), ('treat'), ('livestock'), ('whose'), ('минут'), ('peopl'), ('council'), ('intend'), ('abil'), ('after'), ('injuri'), ('marri'), ('depress'), ('summari'), ('mile'), ('heart'), ('strongest'), ('observ'), ('back'), ('water'), ('border'), ('estim'), ('образ'), ('as'), ('qualiti'), ('счита'), ('declar'), ('respond'), ('readi'), ('метр'), ('rout'), ('shear'), ('mechan'), ('democraci'), ('dictionari'), ('chest'), ('премьер'), ('procur'), ('registr'), ('anniversari'), ('second'), ('basebal'), ('scheme'), ('центр'), ('remot'), ('justifi'), ('bound'), ('reduc'), ('skill'), ('sheep'), ('came'), ('overcom'), ('span'), ('repeat'), ('nov'), ('wave'), ('heaven'), ('leg'), ('sphere'), ('может'), ('protect'), ('effici'), ('amaz'), ('deliveri'), ('presenc'), ('kind'), ('herself'), ('fall'), ('courag'), ('audienc'), ('проблем'), ('конечн'), ('citi'), ('smoke'), ('outlook'), ('явля'), ('inadequ'), ('эт'), ('sure'), ('work'), ('instrument'), ('чут'), ('grown'), ('comfort'), ('generous'), ('entitl'), ('divid'), ('identifi'), ('downtown'), ('заместител'), ('onto'), ('lieuten'), ('lock'), ('capac'), ('document'), ('цел'), ('sell'), ('maid'), ('whole'), ('нельз'), ('construct'), ('suffici'), ('went'), ('сем'), ('new'), ('balanc'), ('realiz'), ('burst'), ('войск'), ('необходим'), ('whether'), ('everyon'), ('vital'), ('deriv'), ('intern'), ('three'), ('februari'), ('possess'), ('send'), ('develop'), ('april'), ('electron'), ('entranc'), ('cite'), ('sugar'), ('civilian'), ('exchang'), ('properti'), ('sever'), ('mix'), ('was'), ('nose'), ('identif'), ('exposur'), ('primari'), ('wisdom'), ('давн'), ('включ'), ('председател'), ('two'), ('refus'), ('if'), ('ноябр'), ('compani'), ('him'), ('grave'), ('gentlemen'), ('wide'), ('прошл'), ('each'), ('count'), ('finger'), ('densiti'), ('preserv'), ('wish'), ('your'), ('articl'), ('wherea'), ('packag'), ('quot'), ('role'), ('start'), ('manufactur'), ('court'), ('bone'), ('assess'), ('engag'), ('larg'), ('squar'), ('adequ'), ('combat'), ('александр'), ('последн'), ('pencil'), ('станов'), ('ест'), ('actual'), ('experi'), ('leav'), ('it'), ('progress'), ('minor'), ('никт'), ('differ'), ('philosophi'), ('plot'), ('digniti'), ('компан'), ('footbal'), ('четырех'), ('belli'), ('easi'), ('slowli'), ('holder'), ('происход'), ('arous'), ('hors'), ('primit'), ('special'), ('wouldn'), ('weight'), ('nod'), ('rais'), ('stock'), ('full'), ('manag'), ('tough'), ('мен'), ('appar'), ('father'), ('perspect'), ('н'), ('столиц'), ('convict'), ('smile'), ('half'), ('daughter'), ('fifth'), ('конц'), ('money'), ('descript'), ('close'), ('limit'), ('gin'), ('boat'), ('pleasant'), ('plaster'), ('doubt'), ('раз'), ('drawn'), ('physic'), ('anim'), ('panic'), ('бол'), ('happili'), ('стол'), ('будт'), ('hidden'), ('block'), ('reject'), ('ю'), ('eight'), ('массов'), ('negoti'), ('interpret'), ('forward'), ('grow'), ('bird'), ('провест'), ('innoc'), ('appl'), ('financ'), ('session'), ('characterist'), ('beat'), ('sum'), ('realism'), ('совс'), ('cap'), ('curt'), ('output'), ('repli'), ('one'), ('wednesday'), ('wive'), ('prestig'), ('trend'), ('minimum'), ('intent'), ('centuri'), ('имеет'), ('mission'), ('did'), ('relationship'), ('edit'), ('brief'), ('find'), ('ten'), ('wholli'), ('involv'), ('eager'), ('from'), ('sake'), ('месяц'), ('method'), ('люд'), ('her'), ('sought'), ('determin'), ('днях'), ('movi'), ('мир'), ('kid'), ('vers'), ('извест'), ('идет'), ('aliv'), ('всем'), ('site'), ('more'), ('year'), ('congression'), ('island'), ('cross'), ('до'), ('speech'), ('net'), ('ugli'), ('curious'), ('let'), ('sweet'), ('летн'), ('this'), ('carbon'), ('challeng'), ('shadow'), ('song'), ('molecul'), ('операц'), ('togeth'), ('among'), ('cst'), ('кстат'), ('report'), ('be'), ('reserv'), ('illustr'), ('class'), ('utopian'), ('commod'), ('weekend'), ('most'), ('soap'), ('во'), ('promin'), ('sensit'), ('fantast'), ('roof'), ('remind'), ('look'), ('worst'), ('действительн'), ('миха'), ('событ'), ('участ'), ('had'), ('desert'), ('будут'), ('integr'), ('golf'), ('ясн'), ('stop'), ('daili'), ('rang'), ('advic'), ('больш'), ('sep'), ('slender'), ('shouldn'), ('perman'), ('leadership'), ('aris'), ('при'), ('conscious'), ('storm'), ('hat'), ('пришл'), ('stead'), ('деятельн'), ('thousand'), ('breakfast'), ('henc'), ('eighth'), ('desegreg'), ('light'), ('tonight'), ('perhap'), ('проект'), ('captain'), ('encourag'), ('happen'), ('again'), ('легк'), ('seri'), ('wall'), ('of'), ('будет'), ('heel'), ('взят'), ('rule'), ('expans'), ('still'), ('nowher'), ('wind'), ('cover'), ('reliev'), ('winter'), ('will'), ('поч'), ('phase'), ('platform'), ('much'), ('servant'), ('neither'), ('command'), ('skin'), ('срок'), ('institut'), ('firm'), ('part'), ('envelop'), ('magnet'), ('where'), ('flight'), ('glanc'), ('doctor'), ('arrest'), ('rain'), ('left'), ('experiment'), ('network'), ('surplus'), ('письм'), ('hydrogen'), ('seen'), ('furthermor'), ('drug'), ('refer'), ('visual'), ('upon'), ('уда'), ('controversi'), ('militari'), ('furnitur'), ('ill'), ('que'), ('sovereignti'), ('inch'), ('status'), ('мне'), ('pleas'), ('alway'), ('nice'), ('problem'), ('полтор'), ('blind'), ('sitter'), ('expos'), ('warrant'), ('avoid'), ('tight'), ('отлич'), ('evid'), ('sweat'), ('popular'), ('percent'), ('heavili'), ('warm'), ('blond'), ('strang'), ('park'), ('theater'), ('ft.'), ('strip'), ('satisfact'), ('traffic'), ('align'), ('moral'), ('strong'), ('свет'), ('knowledg'), ('disturb'), ('calendar'), ('т'), ('desper'), ('dress'), ('meet'), ('into'), ('seven'), ('кром'), ('gorton'), ('fascin'), ('реч'), ('good'), ('charg'), ('скаж'), ('demand'), ('ratio'), ('myth'), ('master'), ('blanket'), ('west'), ('emphas'), ('cultur'), ('concern'), ('farmer'), ('suspend'), ('then'), ('screen'), ('fifteen'), ('dramat'), ('spiritu'), ('pipe'), ('segment'), ('roll'), ('state'), ('bear'), ('atom'), ('pitch'), ('представител'), ('sand'), ('fallout'), ('creas'), ('swim'), ('rub'), ('rode'), ('ring'), ('steam'), ('offici'), ('comput'), ('bell'), ('chemic'), ('heard'), ('suit'), ('flat'), ('найт'), ('direct'), ('ladder'), ('bomb'), ('conscienc'), ('workshop'), ('amp'), ('joke'), ('schedul'), ('senior'), ('mountain'), ('billion'), ('behavior'), ('thyroid'), ('blood'), ('них'), ('conclud'), ('sat'), ('civil'), ('come'), ('file'), ('bride'), ('necessari'), ('least'), ('thermal'), ('less'), ('formula'), ('от'), ('наибол'), ('commerci'), ('некотор'), ('generat'), ('anod'), ('etc.'), ('deep'), ('due'), ('horizon'), ('parti'), ('substanti'), ('sun'), ('fenc'), ('household'), ('stockhold'), ('сторон'), ('frequent'), ('год'), ('six'), ('accus'), ('requir'), ('tall'), ('marriag'), ('помощ'), ('практическ'), ('anybodi'), ('миллион'), ('paper'), ('stuck'), ('defend'), ('last'), ('notic'), ('food'), ('supervis'), ('uniform'), ('often'), ('reflect'), ('mysteri'), ('raw'), ('vision'), ('villag'), ('next'), ('bid'), ('devil'), ('almost'), ('investig'), ('instal'), ('thus'), ('поскольк'), ('grate'), ('becaus'), ('similar'), ('chapel'), ('argu'), ('cloth'), ('bright'), ('фонд'), ('toward'), ('oral'), ('summer'), ('muscl'), ('contain'), ('push'), ('hold'), ('лидер'), ('asleep'), ('fate'), ('percept'), ('refriger'), ('bus'), ('cast'), ('arrang'), ('felt'), ('surviv'), ('same'), ('hit'), ('natur'), ('rich'), ('substitut'), ('деся'), ('convert'), ('crowd'), ('make'), ('imit'), ('extrem'), ('prison'), ('leather'), ('poverti'), ('почт'), ('big'), ('august'), ('allow'), ('merit'), ('mg'), ('hour'), ('degre'), ('сейчас'), ('да'), ('input'), ('larger'), ('tip'), ('slept'), ('scholarship'), ('tool'), ('copi'), ('excit'), ('sent'), ('оказа'), ('messag'), ('grew'), ('conveni'), ('документ'), ('nude'), ('частност'), ('mount'), ('younger'), ('materi'), ('ident'), ('judg'), ('же'), ('dedic'), ('fabric'), ('some'), ('те'), ('with'), ('fault'), ('crawl'), ('estat'), ('here'), ('eat'), ('replac'), ('acquir'), ('salin'), ('function'), ('shade'), ('motor'), ('born'), ('wed'), ('но'), ('на'), ('somehow'), ('resolv'), ('propaganda'), ('cat'), ('passeng'), ('производств'), ('film'), ('concert'), ('довольн'), ('комментар'), ('liquor'), ('boss'), ('seiz'), ('constant'), ('spot'), ('сумм'), ('spread'), ('ahead'), ('crew'), ('приня'), ('reactionari'), ('декабр'), ('respect'), ('wake'), ('advertis'), ('partisan'), ('glass'), ('given'), ('against'), ('жит'), ('yet'), ('мал'), ('грозн'), ('kitchen'), ('chlorin'), ('два'), ('music'), ('conceiv'), ('сред'), ('habit'), ('missil'), ('analysi'), ('broke'), ('variabl'), ('bind'), ('ninth'), ('protest'), ('someon'), ('chain'), ('subtl'), ('politician'), ('tomorrow'), ('label'), ('surpris'), ('rifl'), ('специалист'), ('brush'), ('focus'), ('ad'), ('никак'), ('republ'), ('insect'), ('есл'), ('begin'), ('doctrin'), ('connect'), ('link'), ('feed'), ('oxid'), ('between'), ('посл'), ('suspect'), ('раньш'), ('defens'), ('profit'), ('aspect'), ('complement'), ('minim'), ('book'), ('peer'), ('truth'), ('hollywood'), ('examin'), ('stori'), ('якоб'), ('fourteen'), ('знает'), ('parallel'), ('judgment'), ('put'), ('structur'), ('verb'), ('pdt'), ('peculiar'), ('slid'), ('won'), ('discuss'), ('struck'), ('fail'), ('fort'), ('тольк'), ('bronchial'), ('нам'), ('expert'), ('though'), ('dinner'), ('circumst'), ('heroic'), ('mixtur'), ('compon'), ('всю'), ('attack'), ('specif'), ('situat'), ('игр'), ('career'), ('secret'), ('branch'), ('enthusiast'), ('principl'), ('axi'), ('heavi'), ('наш'), ('editori'), ('политик'), ('com'), ('behalf'), ('thought'), ('ситуац'), ('trial'), ('offer'), ('spell'), ('proport'), ('kill'), ('competit'), ('display'), ('мы'), ('прост'), ('septemb'), ('нескольк'), ('женщин'), ('vivid'), ('user'), ('лет'), ('inde'), ('час'), ('salt'), ('expens'), ('inher'), ('urgent'), ('ritual'), ('вид'), ('tuesday'), ('outcom'), ('jail'), ('cent'), ('мо'), ('shift'), ('brave'), ('mind'), ('women'), ('www'), ('temporarili'), ('minut'), ('doe'), ('заяв'), ('municip'), ('стат'), ('beer'), ('numer'), ('am'), ('gay'), ('older'), ('mood'), ('public'), ('hungri'), ('степен'), ('труд'), ('bat'), ('award'), ('import'), ('pattern'), ('миров'), ('product'), ('пот'), ('know'), ('sigh'), ('приход'), ('consider'), ('racial'), ('tractor'), ('evalu'), ('day'), ('встреч'), ('break'), ('frighten'), ('curios'), ('accord'), ('especi'), ('lower'), ('foam'), ('freight'), ('medic'), ('anti-trust'), ('must'), ('tri'), ('advis'), ('eleven'), ('design'), ('anyhow'), ('mighti'), ('instruct'), ('astronomi'), ('cours'), ('charact'), ('style'), ('path'), ('civic'), ('caus'), ('hole'), ('signal'), ('drew'), ('pocket'), ('everi'), ('routin'), ('власт'), ('planetari'), ('пок'), ('естествен'), ('concept'), ('neighborhood'), ('et'), ('dive'), ('bent'), ('иллюстрац'), ('other'), ('fortun'), ('пор'), ('sophist'), ('suppli'), ('swung'), ('ever'), ('sale'), ('domest'), ('gun'), ('term'), ('уровн'), ('fourth'), ('surrend'), ('except'), ('hurri'), ('radar'), ('loud'), ('quit'), ('immedi'), ('upper'), ('backward'), ('ког'), ('wooden'), ('uneasi'), ('monument'), ('ani'), ('equip'), ('сто'), ('suppos'), ('лучш'), ('particl'), ('psycholog'), ('vein'), ('target'), ('himself'), ('view'), ('abov'), ('repres'), ('middl'), ('hero'), ('fiscal'), ('lost'), ('request'), ('tangibl'), ('glad'), ('tone'), ('ship'), ('sit'), ('calcul'), ('tribut'), ('noon'), ('touch'), ('tire'), ('деньг'), ('written'), ('anywher'), ('everybodi'), ('forest'), ('через'), ('hung'), ('complic'), ('warn'), ('весьм'), ('manner'), ('даж'), ('retir'), ('transform'), ('easier'), ('взгляд'), ('asid'), ('launch'), ('organ'), ('нов'), ('honest'), ('actor'), ('instanc'), ('dirti'), ('within'), ('toe'), ('crash'), ('числ'), ('led'), ('soft'), ('deliv'), ('disast'), ('abbr'), ('jun'), ('forev'), ('имен'), ('obtain'), ('write'), ('долг'), ('somewhat'), ('stream'), ('обычн'), ('startl'), ('elect'), ('consid'), ('myself'), ('assum'), ('spare'), ('failur'), ('м'), ('lone'), ('жител'), ('partial'), ('broken'), ('mad'), ('sauc'), ('fill'), ('интерв'), ('две'), ('justic'), ('recal'), ('сборн'), ('select'), ('store'), ('volum'), ('laid'), ('trip'), ('track'), ('sex'), ('bedroom'), ('warmth'), ('well'), ('wear'), ('июн'), ('recent'), ('news'), ('implic'), ('итар'), ('worth'), ('ассошиэйтед'), ('newer'), ('hundr'), ('pale'), ('occup'), ('lucki'), ('travel'), ('row'), ('legal'), ('sharp'), ('ball'), ('allianc'), ('convent'), ('prefer'), ('stabl'), ('tongu'), ('patholog'), ('случа'), ('gang'), ('bank'), ('level'), ('tour'), ('faith'), ('train'), ('abl'), ('friend'), ('none'), ('receiv'), ('do'), ('undoubt'), ('дни'), ('contin'), ('garden'), ('shoulder'), ('tangent'), ('ран'), ('altern'), ('smaller'), ('pool'), ('whip'), ('stood'), ('pioneer'), ('spite'), ('oct'), ('mere'), ('strategi'), ('меньш'), ('babi'), ('the'), ('done'), ('ton'), ('одн'), ('вам'), ('deterg'), ('cellar'), ('spring'), ('craft'), ('so'), ('newli'), ('remark'), ('wife'), ('mar'), ('meant'), ('duck'), ('killer'), ('виктор'), ('станет'), ('noth'), ('правд'), ('so-cal'), ('idea'), ('corner'), ('cocktail'), ('testimoni'), ('world'), ('flux'), ('impos'), ('greatest'), ('confirm'), ('дат'), ('straight'), ('skirt'), ('at'), ('fig'), ('joy'), ('licens'), ('equal'), ('enforc'), ('murder'), ('outsid'), ('зат'), ('mother'), ('trade'), ('honor'), ('builder'), ('broad'), ('road'), ('air'), ('ideal'), ('shook'), ('sid'), ('tini'), ('rough'), ('form'), ('shore'), ('dust'), ('guy'), ('longer'), ('sixteen'), ('polici'), ('для'), ('give'), ('render'), ('sens'), ('propos'), ('mankind'), ('supplement'), ('alli'), ('them'), ('abandon'), ('voter'), ('smooth'), ('систем'), ('реш'), ('annual'), ('scare'), ('seed'), ('nor'), ('press'), ('associ'), ('lie'), ('extraordinari'), ('воскресен'), ('равн'), ('when'), ('various'), ('chief'), ('background'), ('ground'), ('man'), ('beneath'), ('закон'), ('eas'), ('коп'), ('moder'), ('coast'), ('резк'), ('beef'), ('wage'), ('http'), ('elabor'), ('friendship'), ('pond'), ('dynam'), ('may'), ('сил'), ('hall'), ('fashion'), ('начальник'), ('прот'), ('opportun'), ('heritag'), ('alon'), ('coupl'), ('дня'), ('realist'), ('wors'), ('creat'), ('reveal'), ('forc'), ('describ'), ('crucial'), ('novel'), ('conduct'), ('имет'), ('accept'), ('twenti'), ('fruit'), ('edg'), ('host'), ('одновремен'), ('yes'), ('solid'), ('mode'), ('separ'), ('pressur'), ('exercis'), ('част'), ('shall'), ('profession'), ('widow'), ('further'), ('sign'), ('base'), ('lang'), ('regard'), ('carri'), ('steadili'), ('хочет'), ('casual'), ('стал'), ('род'), ('chang'), ('ought'), ('walk'), ('comedi'), ('poem'), ('вы'), ('про'), ('hard'), ('width'), ('knock'), ('number'), ('debat'), ('exampl'), ('nevertheless'), ('тогд'), ('error'), ('ownership'), ('ration'), ('trader'), ('процесс'), ('истор'), ('нег'), ('now'), ('thereaft'), ('sold'), ('insist'), ('test'), ('optim'), ('gross'), ('visibl'), ('morn'), ('skywav'), ('step'), ('mani'), ('princip'), ('resist'), ('column'), ('stress'), ('how'), ('event'), ('произошл'), ('continu'), ('без'), ('their'), ('oblig'), ('scale'), ('best'), ('confid'), ('ним'), ('wing'), ('сегодн'), ('up'), ('lumber'), ('oxygen'), ('onc'), ('multipl'), ('writer'), ('forgiv'), ('unknown'), ('king'), ('inventori'), ('tape'), ('decim'), ('familiar'), ('рол'), ('whiski'), ('ещ'), ('tissu'), ('question'), ('condit'), ('point'), ('hand'), ('anoth'), ('goe'), ('loan'), ('which'), ('из'), ('far'), ('loop'), ('recoveri'), ('pea'), ('measur'), ('suffix'), ('admit'), ('trap'), ('flow'), ('addit'), ('constitut'), ('анатол'), ('egg'), ('sound'), ('also'), ('зрен'), ('wagon'), ('polic'), ('trim'), ('attent'), ('pull'), ('adjust'), ('stranger'), ('but'), ('too'), ('anyth'), ('small'), ('over'), ('aboard'), ('оста'), ('found'), ('is'), ('люб'), ('fallen'), ('coat'), ('color'), ('seventh'), ('mess'), ('им'), ('prevent'), ('anger'), ('golden'), ('coach'), ('instead'), ('говор'), ('sort'), ('click'), ('sinc'), ('drank'), ('game'), ('х'), ('tactic'), ('accomplish'), ('pay'), ('bigger'), ('correspond'), ('cigarett'), ('вас'), ('нужн'), ('like'), ('unconsci'), ('got'), ('former'), ('coffe'), ('polynomi'), ('collect'), ('мер'), ('vice'), ('сих'), ('shot'), ('camp'), ('assur'), ('дне'), ('ladi'), ('studio'), ('strateg'), ('negat'), ('ask'), ('куд'), ('прав'), ('choic'), ('tension'), ('dozen'), ('declin'), ('нем'), ('toast'), ('решен'), ('guidanc'), ('fund'), ('befor'), ('pink'), ('fear'), ('polit'), ('cut'), ('essenti'), ('трудн'), ('plant'), ('март'), ('low'), ('admiss'), ('his'), ('classic'), ('dimens'), ('pure'), ('contest'), ('rush'), ('divin'), ('across'), ('interv'), ('through'), ('deliber'), ('poetic'), ('while'), ('resourc'), ('herd'), ('stronger'), ('railroad'), ('influenc'), ('cash'), ('руб'), ('held'), ('syllabl'), ('rise'), ('mold'), ('torn'), ('gyro'), ('п'), ('clear'), ('take'), ('communiti'), ('unfortun'), ('bother'), ('ventur'), ('sacrific'), ('например'), ('critic'), ('conflict'), ('privat'), ('join'), ('дел'), ('lake'), ('й'), ('bullet'), ('linear'), ('meaning'), ('forum'), ('truli'), ('что'), ('bgcolor'), ('possibl'), ('formal'), ('transfer'), ('school'), ('rural'), ('тех'), ('inclin'), ('нын'), ('depend'), ('camera'), ('contemporari'), ('unusu'), ('suffer'), ('unit'), ('nut'), ('инач'), ('lose'), ('loyalti'), ('solv'), ('spoken'), ('patienc'), ('diamet'), ('accur'), ('pain'), ('made'), ('engin'), ('page'), ('browser'), ('fell'), ('aren'), ('орга'), ('stake'), ('read'), ('literari'), ('тем'), ('field'), ('delic'), ('всё'), ('результат'), ('дал'), ('residenti'), ('decemb'), ('paint'), ('such'), ('greater'), ('suitcas'), ('snap'), ('shape'), ('wore'), ('contribut'), ('sunday'), ('reput'), ('secretari'), ('window'), ('ответ'), ('faculti'), ('accid'), ('ден'), ('tragedi'), ('countri'), ('imposs'), ('сентябр'), ('includ'), ('current'), ('evil'), ('featur'), ('prospect'), ('guess'), ('assembl'), ('swift'), ('stroke'), ('начал'), ('ancient'), ('middle-class'), ('headquart'), ('yard'), ('uniti'), ('invari'), ('oppos'), ('june'), ('convers'), ('present'), ('techniqu'), ('apr'), ('catch'), ('sponsor'), ('these'), ('fog'), ('forth'), ('grain'), ('floor'), ('talent'), ('quarrel'), ('fun'), ('promis'), ('see'), ('тепер'), ('statist'), ('offic'), ('north'), ('statement'), ('didn'), ('е'), ('liter'), ('суд'), ('pose'), ('нема'), ('всегд'), ('night'), ('никогд'), ('member'), ('clerk'), ('drove'), ('troop'), ('incred'), ('dure'), ('respons'), ('dealt'), ('stem'), ('вдруг'), ('ward'), ('time'), ('maintain'), ('round'), ('presid'), ('paus'), ('weather'), ('magazin'), ('дела'), ('exhibit'), ('андр'), ('draw'), ('точн'), ('afraid'), ('version'), ('either'), ('common'), ('mustard'), ('health'), ('там'), ('pictur'), ('throughout'), ('очередн'), ('paragraph'), ('coverag'), ('classif'), ('son'), ('human'), ('bin'), ('review'), ('ег'), ('promot'), ('chord'), ('по'), ('twice'), ('revolut'), ('primarili'), ('wherebi'), ('ни'), ('vacuum'), ('вряд'), ('tag'), ('governor'), ('correct'), ('easili'), ('enjoy'), ('varieti'), ('favorit'), ('шест'), ('conductor'), ('teeth'), ('sang'), ('квартир'), ('general'), ('maximum'), ('ряд'), ('complex'), ('tent'), ('restrict'), ('недавн'), ('midnight'), ('merger'), ('imag'), ('dirt'), ('guid'), ('phrase'), ('cell'), ('nine'), ('interfer'), ('devic'), ('quiet'), ('five'), ('услов'), ('task'), ('utter'), ('employe'), ('phone'), ('bitter'), ('servic'), ('conson'), ('auto'), ('journey'), ('clock'), ('closer'), ('ranch'), ('televis'), ('remov'), ('largest'), ('apparatus'), ('has'), ('club'), ('string'), ('reaction'), ('уровен'), ('chiefli'), ('creatur'), ('adult'), ('list'), ('out'), ('unabl'), ('reason'), ('возможн'), ('arbitrari'), ('element'), ('practic'), ('tell'), ('melodi'), ('seem'), ('decad'), ('apart'), ('тон'), ('core'), ('devot'), ('stage'), ('supper'), ('warfar'), ('section'), ('specialist'), ('consist'), ('desk'), ('size'), ('миллиард'), ('curv'), ('insid'), ('editor'), ('виц'), ('choos'), ('времен'), ('вокруг'), ('invest'), ('alert'), ('complain'), ('parad'), ('communic'), ('hotel'), ('gradual'), ('demonstr'), ('publish'), ('side'), ('подобн'), ('subtract'), ('confront'), ('assist'), ('street'), ('prepar'), ('shirt'), ('town'), ('font'), ('cottag'), ('примерн'), ('mud'), ('cloud'), ('alter'), ('быт'), ('membership'), ('flower'), ('milligram'), ('лиш'), ('enough'), ('social'), ('execut'), ('rid'), ('affair'), ('conclus'), ('throat'), ('повод'), ('ethic'), ('связ'), ('thirti'), ('modern'), ('luxuri'), ('grant'), ('никола'), ('glori'), ('band'), ('recept'), ('short'), ('gold'), ('use'), ('been'), ('полност'), ('theme'), ('bundl'), ('retain'), ('guilti'), ('week'), ('пример'), ('noun'), ('readili'), ('etern'), ('paid'), ('melt'), ('charm'), ('until'), ('eve'), ('ссылк'), ('алекс'), ('лиц'), ('котор'), ('univers'), ('citizen'), ('halign'), ('equat'), ('introduct'), ('instant'), ('junior'), ('maker'), ('disciplin'), ('therefor'), ('директор'), ('name'), ('едв'), ('spirit'), ('commit'), ('sampl'), ('est'), ('doesn'), ('door'), ('tube'), ('assign'), ('друг'), ('точк'), ('porch'), ('learn'), ('box'), ('troubl'), ('guilt'), ('fulli'), ('appeal'), ('enabl'), ('километр'), ('decid'), ('authent'), ('го'), ('чем'), ('знач'), ('alien'), ('mdt'), ('profess'), ('distant'), ('со'), ('aim'), ('explor'), ('бывш'), ('bill'), ('eventu'), ('els'), ('destruct'), ('illus'), ('attorney'), ('thrust'), ('rare'), ('врем'), ('фирм'), ('совершен'), ('ride'), ('march'), ('href'), ('блог'), ('очен'), ('combin'), ('вполн'), ('safe'), ('machin'), ('head'), ('sister'), ('star'), ('fellow'), ('sin'), ('overwhelm'), ('burn'), ('delight'), ('establish'), ('personnel'), ('sequenc'), ('ice'), ('opposit'), ('indic'), ('desir'), ('наконец'), ('тут'), ('issu'), ('lot'), ('latest'), ('stomach'), ('inspir'), ('virtu'), ('accuraci'), ('fool'), ('nobodi'), ('cream'), ('ну'), ('growth'), ('us'), ('genius'), ('notion'), ('hang'), ('highest'), ('чег'), ('положен'), ('ем'), ('mean'), ('brought'), ('feder'), ('shop'), ('began'), ('via'), ('thing'), ('прич'), ('rear'), ('whisper'), ('confus'), ('нет'), ('spent'), ('around'), ('phenomena'), ('stick'), ('cannot'), ('along'), ('not'), ('angri'), ('butter'), ('mark'), ('literatur'), ('enthusiasm'), ('listen'), ('rememb'), ('brown'), ('bought'), ('loss'), ('mutual'), ('scope'), ('magic'), ('harm'), ('perform'), ('sometim'), ('suburban'), ('folk'), ('ил'), ('strict'), ('rail'), ('regim'), ('sorri'), ('местн'), ('gift'), ('shake'), ('remain'), ('onset'), ('circular'), ('extens'), ('societi'), ('jacket'), ('inc'), ('bet'), ('quarter'), ('drop'), ('anticip'), ('underground'), ('allot'), ('stupid'), ('motiv'), ('л'), ('medium'), ('planet'), ('root'), ('effect'), ('repair'), ('specifi'), ('сам'), ('stay'), ('live'), ('counter'), ('sergeant'), ('cdt'), ('piano'), ('standard'), ('search'), ('явн'), ('вообщ'), ('момент'), ('sudden'), ('отдел'), ('soul'), ('серг'), ('тож'), ('pair'), ('сотрудник'), ('advanc'), ('jul'), ('success'), ('leap'), ('lay'), ('fought'), ('gain'), ('anti-semit'), ('цен'), ('anxieti'), ('abstract'), ('был'), ('major'), ('team'), ('realiti'), ('alreadi'), ('imagin'), ('place'), ('room'), ('forget'), ('absent'), ('high'), ('saw'), ('reduct'), ('help'), ('destroy'), ('невозможн'), ('first'), ('владимир'), ('thin'), ('парт'), ('scene'), ('play'), ('snow'), ('histori'), ('percentag'), ('процент'), ('difficulti');
        CREATE OR REPLACE FUNCTION is_stop_stem(size TEXT, stem TEXT)
            RETURNS BOOLEAN AS $$
        DECLARE
            result BOOLEAN;
        BEGIN

            -- Tiny
            IF size = 'tiny' THEN
                SELECT 't' INTO result FROM stopword_stems_tiny WHERE stopword_stem = stem;
                IF NOT FOUND THEN
                    result := 'f';
                END IF;

            -- Short
            ELSIF size = 'short' THEN
                SELECT 't' INTO result FROM stopword_stems_short WHERE stopword_stem = stem;
                IF NOT FOUND THEN
                    result := 'f';
                END IF;

            -- Long
            ELSIF size = 'long' THEN
                SELECT 't' INTO result FROM stopword_stems_long WHERE stopword_stem = stem;
                IF NOT FOUND THEN
                    result := 'f';
                END IF;

            -- unknown size
            ELSE
                RAISE EXCEPTION 'Unknown stopword stem size: "%" (expected "tiny", "short" or "long")', size;
                result := 'f';
            END IF;

            RETURN result;
        END;
        $$ LANGUAGE plpgsql;



CREATE TYPE download_file_status AS ENUM ( 'tbd', 'missing', 'na', 'present', 'inline', 'redownloaded', 'error_redownloading' );

ALTER TABLE downloads ADD COLUMN file_status download_file_status not null default 'tbd';

ALTER TABLE downloads ADD COLUMN relative_file_path text not null default 'tbd';


ALTER TABLE downloads ADD COLUMN old_download_time timestamp without time zone;
ALTER TABLE downloads ADD COLUMN old_state download_state;
UPDATE downloads set old_download_time = download_time, old_state = state;

CREATE UNIQUE INDEX downloads_file_status on downloads(file_status, downloads_id);
CREATE UNIQUE INDEX downloads_relative_path on downloads( relative_file_path, downloads_id);

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

UPDATE downloads set relative_file_path = get_relative_file_path(path) where relative_file_path = 'tbd';CREATE OR REPLACE FUNCTION download_relative_file_path_trigger() RETURNS trigger AS 
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
	  ELSE
               -- RAISE NOTICE 'NO path change % = %', OLD.path, NEW.path;
          END IF;
      ELSIF TG_OP = 'INSERT' then
	  NEW.relative_file_path = get_relative_file_path(NEW.path);
      END IF;

      RETURN NEW;
   END;
$$ 
LANGUAGE 'plpgsql';

DROP TRIGGER IF EXISTS download_relative_file_path_trigger on downloads CASCADE;
CREATE TRIGGER download_relative_file_path_trigger BEFORE INSERT OR UPDATE ON downloads FOR EACH ROW EXECUTE PROCEDURE  download_relative_file_path_trigger() ;
CREATE INDEX relative_file_paths_to_verify on downloads( relative_file_path ) where file_status = 'tbd' and relative_file_path <> 'tbd' and relative_file_path <> 'error';
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
alter table weekly_words alter column weekly_words_id type bigint;
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

--DROP TRIGGER IF EXISTS download_relative_file_path_trigger on downloads CASCADE;
--CREATE TRIGGER download_relative_file_path_trigger BEFORE INSERT OR UPDATE ON downloads FOR EACH ROW EXECUTE PROCEDURE  download_relative_file_path_trigger() ;

-- Add column to allow more active feeds to be downloaded more frequently.
ALTER TABLE feeds ADD COLUMN last_new_story_time timestamp without time zone;
UPDATE feeds SET last_new_story_time = greatest( last_download_time, last_new_story_time );
ALTER TABLE feeds ALTER COLUMN last_download_time TYPE timestamp with time zone;
ALTER TABLE feeds ALTER COLUMN last_new_story_time TYPE timestamp with time zone;

