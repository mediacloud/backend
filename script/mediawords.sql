/* schema for MediaWords database */

create table media (
    media_id            serial          primary key,
    url                 varchar(1024)   not null,
    name                varchar(128)    not null,
    moderated           boolean         not null,
    feeds_added         boolean         not null,
    moderation_notes    text            null,       
    full_text_rss       boolean         ,
    extract_author      boolean         default(false),
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
create unique index queries_hash on queries ( md5( description ) );
DROP INDEX queries_hash;
ALTER TABLE queries ADD COLUMN query_version query_version_enum DEFAULT enum_last (null::query_version_enum ) NOT NULL;
create unique index queries_hash_version on queries ( md5( description ), query_version );

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
    media_clusters_id           int         references media_clusters,
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
create index stories_title on stories(title, publish_date);

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
CREATE INDEX downloads_state_queued on downloads(state) where state='queued' or state='fetching';

create view downloads_media as select d.*, f.media_id as _media_id from downloads d, feeds f where d.feeds_id = f.feeds_id;

create view downloads_non_media as select d.* from downloads d where d.feeds_id is null;

CREATE INDEX downloads_sites_index on downloads (regexp_replace(host, $q$^(.)*?([^.]+)\.([^.]+)$$q$ ,E'\\2.\\3'));
CREATE INDEX downloads_sites_pending on downloads (regexp_replace(host, $q$^(.)*?([^.]+)\.([^.]+)$$q$ ,E'\\2.\\3')) where state='pending';

/*
CREATE INDEX downloads_sites_downloads_id_pending on downloads (regexp_replace(host, $q$^(.)*?([^.]+)\.([^.]+)$$q$ ,E'\\2.\\3'), downloads_id) where state='pending';
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
    ADD CONSTRAINT download_texts_downloads_id_fkey FOREIGN KEY (downloads_id) REFERENCES downloads(downloads_id);

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
    
create table story_sentence_counts (
       story_sentence_counts_id     bigserial       primary key,
       sentence_md5                 varchar(64)     not null,
       media_id                     int             not null, /* references media */
       publish_week                 timestamp       not null,
       sentence_count               int             not null,
       first_stories_id             int             not null,
       first_sentence_number        int             not null
);

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

create UNIQUE index daily_words_unique on daily_words(publish_day, media_sets_id, dashboard_topics_id, stem);

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
CREATE UNIQUE INDEX total_daily_words_media_sets_id_dashboard_topic_id_publish_day ON total_daily_words (media_sets_id, dashboard_topics_id, publish_day);

 
create table daily_story_count (
       daily_storys_id             serial          primary key,
       media_sets_id               int             not null references media_sets on delete cascade, 
       dashboard_topics_id         int             null references dashboard_topics, 
       publish_day                 date            not null,
       update_time                 timestamp       not null default now(),
       story_count                 int             not null
);

create index daily_story_count_media_sets_id on daily_story_count (media_sets_id);
create index daily_story_count_media_sets_id_publish_day on daily_story_count (media_sets_id, publish_day);
CREATE UNIQUE INDEX daily_story_count_media_sets_id_dashboard_topic_id_publish_day ON daily_story_count (media_sets_id, dashboard_topics_id, publish_day);

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

