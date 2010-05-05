/* schema for MediaWords database */

create language plperlu;

create table media (
    media_id		serial		    primary key,
    url     		varchar(1024)	not null,
    name	       	varchar(128)	not null,
    CONSTRAINT media_name_not_empty CHECK (((name)::text <> ''::text))
);

create unique index media_name on media(name);
create unique index media_url on media(url);

create table feeds (
    feeds_id			serial		    primary key,
    media_id			int		        not null references media on delete cascade,
    name                varchar(512)    not null,        
    url	   		        varchar(1024)	not null,
    reparse             boolean         null,
    last_download_time  timestamp       null,
    comments_anchor     varchar(512)    null,
    generator           varchar(512)    null
);

create index feeds_media on feeds(media_id);
create index feeds_name on feeds(name);
create unique index feeds_url on feeds (url, media_id);
create index feeds_reparse on feeds(reparse);
create index feeds_last_download_time on feeds(last_download_time);

create table tag_sets (
	tag_sets_id			serial			primary key,
	name				varchar(512)	not null,
    CONSTRAINT tag_sets_name_not_empty CHECK (((name)::text <> ''::text))
);

create unique index tag_sets_name on tag_sets (name);

create table tags (
	tags_id				serial			primary key,
	tag_sets_id			int				not null references tag_sets,
	tag					varchar(512)	not null,
        CONSTRAINT no_lead_or_trailing_whitspace CHECK ((((((tag_sets_id = 13) OR (tag_sets_id = 9)) OR (tag_sets_id = 8)) OR (tag_sets_id = 6)) OR ((tag)::text = btrim((tag)::text, ' 
	'::text)))),
        CONSTRAINT no_line_feed CHECK (((NOT ((tag)::text ~~ '%%'::text)) AND (NOT ((tag)::text ~~ '%
%'::text)))),
        CONSTRAINT tag_not_empty CHECK (((tag)::text <> ''::text))
);

create unique index tags_tag on tags (tag, tag_sets_id);
create index tags_tag_1 on tags (split_part(tag, ' ', 1));
create index tags_tag_2 on tags (split_part(tag, ' ', 2));
create index tags_tag_3 on tags (split_part(tag, ' ', 3));


create table feeds_tags_map (
	feeds_tags_map_id	serial			primary key,
	feeds_id			int				not null references feeds on delete cascade,
	tags_id				int				not null references tags on delete cascade
);

create unique index feeds_tags_map_feed on feeds_tags_map (feeds_id, tags_id);
create index feeds_tags_map_tag on feeds_tags_map (tags_id);

create table media_tags_map (
	media_tags_map_id	serial			primary key,
	media_id			int				not null references media on delete cascade,
	tags_id				int				not null references tags on delete cascade
);

create unique index media_tags_map_media on media_tags_map (media_id, tags_id);
create index media_tags_map_tag on media_tags_map (tags_id);

create table story_texts (
    story_texts_id      serial          primary key,
    story_text          text            not null
);

create table stories (
    stories_id	                serial		    primary key,
    media_id		            int		        not null references media on delete cascade,
    url		                    varchar(1024)	not null,
    guid		                varchar(1024)	not null,
    title		                text		    not null,
    description	                text		    null,
    publish_date	            timestamp	    not null,
    collect_date	            timestamp	    not null,
    story_texts_id              int             null references story_texts on delete set null
);

create index stories_media on stories (media_id, guid);
CREATE INDEX stories_media_id ON stories USING btree (media_id);
create unique index stories_guid on stories(guid, media_id);
create index stories_url on stories (url);
create index stories_publish_date on stories (publish_date);
create index stories_collect_date on stories (collect_date);
create unique index stories_story_text on stories (story_texts_id);
create index stories_title on stories(title);
    
create table downloads (
    downloads_id        serial          primary key,
    feeds_id            int             not null references feeds,
    stories_id          int             null references stories on delete cascade,
    parent              int             null,
    url                 varchar(1024)   not null,
    host                varchar(1024)   not null,
    download_time       timestamp       not null,
    type                varchar(32)     not null,
    state               varchar(32)     not null, /* pending, queued, fetching, success, error */
    path                text            null,
    error_message       text            null,
    priority            int             not null,
    sequence            int             not null,
    extracted           boolean         not null default 'f'
);

alter table downloads add constraint downloads_parent_fkey 
    foreign key (parent) references downloads on delete set null;
alter table downloads add constraint downloads_state
    check (state in ('pending', 'queued', 'fetching', 'success', 'error'));
alter table downloads add constraint downloads_path
    check ((state = 'success' and path is not null) or 
           (state != 'success'));
alter table downloads add constraint downloads_story
    check ((type = 'feed' and stories_id is null) or (stories_id is not null));

-- make the query optimizer get enough stats to use the feeds_id index
alter table downloads alter feeds_id set statistics 1000;

create index downloads_parent on downloads (parent);
-- create unique index downloads_host_fetching 
--     on downloads(host, (case when state='fetching' then 1 else null end));
create index downloads_time on downloads (download_time);
create index downloads_state on downloads (state);
create index downloads_sequence on downloads (sequence);
create index downloads_type on downloads (type);
create index downloads_host_state_priority on downloads (host, state, priority);
create index downloads_feed_state on downloads(feeds_id, state);
create index downloads_story on downloads(stories_id);
create index downloads_url on downloads(url);
create index downloads_state_pending on downloads(state) where state = 'pending';
create index downloads_extracted on downloads(extracted, state, type) 
    where extracted = 'f' and state = 'success' and type = 'content';
CREATE INDEX downloads_stories_to_be_extracted on downloads (stories_id) where extracted = false AND state::text = 'success'::text AND type::text = 'content'::text;        

create table feeds_stories_map
 (
    feeds_stories_map_id    serial  primary key,
    feeds_id                int		not null references feeds on delete cascade,
    stories_id	            int		not null references stories on delete cascade
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
    CACHE 1;

CREATE UNIQUE INDEX download_texts_downloads_id_index ON download_texts USING btree (downloads_id);

CREATE INDEX download_texts_textsearch_idx ON download_texts USING gin (to_tsvector('english'::regconfig, download_text));

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

create table story_vectors (
        stories_id              int         not null references stories on delete cascade,
        vector                  tsvector    not null
);

create unique index story_vectors_story on story_vectors (stories_id);
create index story_vectors_vector on story_vectors using gin(vector);

create table story_vectors_dt (
        download_texts_id       int         not null
);

create table story_words (
       story_words_id       serial          primary key,
       stories_id           int             not null references stories on delete cascade,
       term                 text            not null,
       stem                 text            not null,
       stem_count           int             not null
);

create index story_words_story on story_words (stories_id);

create table story_phrases (
       story_phrases_id     serial          primary key,
       stories_id           int             not null references stories on delete cascade,
       term                 text            not null,
       term_count         int             not null
);

create index story_phrases_story on story_phrases (stories_id);
    
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



