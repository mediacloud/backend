--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4404 and 4405.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4404, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4405, import this SQL file:
--
--     psql mediacloud < mediawords-4404-4405.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

DROP SCHEMA stories_tags_map_media_sub_tables CASCADE;

DROP VIEW media_dups_transitive;

DROP VIEW stories_collected_in_past_day;

ALTER TABLE media
	DROP CONSTRAINT media_dup;

ALTER TABLE tags
	DROP CONSTRAINT no_lead_or_trailing_whitspace;

ALTER TABLE media_cluster_runs
	DROP CONSTRAINT media_cluster_runs_state;

ALTER TABLE media_cluster_maps
	DROP CONSTRAINT media_cluster_maps_type;

DROP INDEX queries_signature_version;

DROP INDEX queries_signature;

DROP INDEX stories_guid;

DROP INDEX downloads_sites_index;

DROP INDEX story_sentence_words_day;

DROP INDEX story_sentence_words_media_day;

DROP INDEX daily_words_unique;

DROP INDEX weekly_words_publish_week;

DROP INDEX story_similarities_a_b;

DROP INDEX story_similarities_a_s;

DROP INDEX story_similarities_b_s;

DROP INDEX controversy_links_story;

DROP TABLE sopa_links;

DROP TABLE sopa_stories;

DROP TABLE controversy_merged_media;

CREATE SEQUENCE database_variables_datebase_variables_id_seq
	START WITH 1
	INCREMENT BY 1
	NO MAXVALUE
	NO MINVALUE
	CACHE 1;

CREATE SEQUENCE media_cluster_map_pole_simila_media_cluster_map_pole_simila_seq
	START WITH 1
	INCREMENT BY 1
	NO MAXVALUE
	NO MINVALUE
	CACHE 1;

CREATE SEQUENCE total_top_500_weekly_words_total_top_500_words_id_seq
	START WITH 1
	INCREMENT BY 1
	NO MAXVALUE
	NO MINVALUE
	CACHE 1;

CREATE SEQUENCE total_top_500_weekly_author_words_total_top_500_words_id_seq
	START WITH 1
	INCREMENT BY 1
	NO MAXVALUE
	NO MINVALUE
	CACHE 1;

CREATE SEQUENCE story_similarities_story_similarities_id_seq1
	START WITH 1
	INCREMENT BY 1
	NO MAXVALUE
	NO MINVALUE
	CACHE 1;

CREATE SEQUENCE story_similarities_story_similarities_id_seq2
	START WITH 1
	INCREMENT BY 1
	NO MAXVALUE
	NO MINVALUE
	CACHE 1;

CREATE SEQUENCE story_similarities_100_short_story_similarities_id_seq
	START WITH 1
	INCREMENT BY 1
	NO MAXVALUE
	NO MINVALUE
	CACHE 1;

CREATE SEQUENCE controversy_dates_controversy_dates_id_seq
	START WITH 1
	INCREMENT BY 1
	NO MAXVALUE
	NO MINVALUE
	CACHE 1;

CREATE SEQUENCE controversy_seed_urls_controversy_seed_urls_id_seq
	START WITH 1
	INCREMENT BY 1
	NO MAXVALUE
	NO MINVALUE
	CACHE 1;

CREATE SEQUENCE media_alexa_stats_media_alexa_stats_id_seq
	START WITH 1
	INCREMENT BY 1
	NO MAXVALUE
	NO MINVALUE
	CACHE 1;

CREATE TABLE media_cluster_map_pole_similarities (
	media_cluster_map_pole_similarities_id integer primary key DEFAULT nextval('media_cluster_map_pole_simila_media_cluster_map_pole_simila_seq'::regclass) NOT NULL,
	media_id integer NOT NULL REFERENCES media(media_id),
	queries_id integer NOT NULL REFERENCES queries(queries_id),
	similarity integer NOT NULL,
	media_cluster_maps_id integer NOT NULL REFERENCES media_cluster_maps(media_cluster_maps_id)
);

CREATE TABLE story_similarities_1000_tiny_idf (
	story_similarities_id integer primary key DEFAULT nextval('story_similarities_story_similarities_id_seq2'::regclass) NOT NULL,
	stories_id_a integer,
	publish_day_a date,
	stories_id_b integer,
	publish_day_b date,
	similarity integer,
	"method" character varying(1024)
);

CREATE TABLE story_similarities_100_short (
	story_similarities_id integer PRIMARY KEY DEFAULT nextval('story_similarities_100_short_story_similarities_id_seq'::regclass) NOT NULL,
	stories_id_a integer,
	publish_day_a date,
	stories_id_b integer,
	publish_day_b date,
	similarity integer
);

CREATE TABLE tar_downloads_queue (
	downloads_id integer
);

CREATE TABLE controversy_dates (
	controversy_dates_id integer primary key DEFAULT nextval('controversy_dates_controversy_dates_id_seq'::regclass) NOT NULL,
	controversies_id integer NOT NULL REFERENCES controversies(controversies_id) ON DELETE CASCADE,
	start_date date NOT NULL,
	end_date date NOT NULL
);

CREATE TABLE controversy_seed_urls (
	controversy_seed_urls_id integer primary key DEFAULT nextval('controversy_seed_urls_controversy_seed_urls_id_seq'::regclass) NOT NULL,
	controversies_id integer NOT NULL REFERENCES controversies(controversies_id) ON DELETE CASCADE,
	url text,
	source text,
	stories_id integer REFERENCES stories(stories_id) ON DELETE CASCADE,
	processed boolean DEFAULT false NOT NULL
);

CREATE TABLE controversy_merged_stories_map (
	source_stories_id integer NOT NULL REFERENCES stories(stories_id) ON DELETE CASCADE,
	target_stories_id integer NOT NULL REFERENCES stories(stories_id) ON DELETE CASCADE
);

CREATE TABLE controversy_query_story_searches_imported_stories_map (
	controversies_id integer NOT NULL REFERENCES controversies(controversies_id) ON DELETE CASCADE,
	stories_id integer NOT NULL REFERENCES stories(stories_id) ON DELETE CASCADE
);

CREATE TABLE controversy_unmerged_media (
	media_id integer NOT NULL REFERENCES media(media_id) ON DELETE CASCADE
);

CREATE TABLE adhoc_momentum (
	publish_day date,
	stem character varying(1024),
	num_sentences integer,
	media_set_name character varying(1024),
	media_sets_id integer
);

CREATE TABLE controversy_links_copy (
	controversy_links_id integer,
	controversies_id integer,
	stories_id integer,
	url text,
	redirect_url text,
	ref_stories_id integer,
	link_spidered boolean
);

CREATE TABLE controversy_links_copy_20120920 (
	controversy_links_id integer,
	controversies_id integer,
	stories_id integer,
	url text,
	redirect_url text,
	ref_stories_id integer,
	link_spidered boolean
);

CREATE TABLE controversy_media_codes_20121020 (
	controversies_id integer,
	media_id integer,
	code_type text,
	code text
);

CREATE TABLE controversy_stories_20121018 (
	controversy_stories_id integer,
	controversies_id integer,
	stories_id integer,
	link_mined boolean,
	iteration integer,
	link_weight real,
	redirect_url text
);

CREATE TABLE controversy_links_20121018 (
	controversy_links_id integer,
	controversies_id integer,
	stories_id integer,
	url text,
	redirect_url text,
	ref_stories_id integer,
	link_spidered boolean
);

CREATE TABLE controversy_stories_copy (
	controversy_stories_id integer,
	controversies_id integer,
	stories_id integer,
	link_mined boolean,
	iteration integer,
	link_weight real,
	redirect_url text
);

CREATE TABLE controversy_stories_copy_20120920 (
	controversy_stories_id integer,
	controversies_id integer,
	stories_id integer,
	link_mined boolean,
	iteration integer,
	link_weight real,
	redirect_url text
);

CREATE TABLE controversy_links_distinct (
	controversy_links_id integer,
	controversies_id integer,
	stories_id integer,
	url text,
	redirect_url text,
	ref_stories_id integer,
	link_spidered boolean
);

CREATE TABLE extractor_training_lines_corrupted_download_content (
	extractor_training_lines_id integer,
	line_number integer,
	required boolean,
	downloads_id integer,
	"time" timestamp without time zone,
	submitter character varying(256)
);

CREATE TABLE hr_pilot_study_stories (
	media_id integer,
	stories_id integer,
	title text,
	url character varying(1024)
);

CREATE TABLE india_million (
	stories_id integer,
	publish_date timestamp without time zone,
	title text,
	url character varying(1024),
	media_name character varying(128)
);

CREATE TABLE ma_ms_queue (
	media_sets_id integer
);

CREATE TABLE pilot_story_sims (
	similarity text,
	title_1 text,
	title_2 text,
	url_1 text,
	url_2 text,
	stories_id_1 text,
	stories_id_2 text,
	include boolean
);

CREATE TABLE pilot_story_sims_code (
	similarity text,
	title_1 text,
	title_2 text,
	url_1 text,
	url_2 text,
	stories_id_1 text,
	stories_id_2 text,
	include boolean
);

CREATE TABLE pilot_study_stories (
	media_id integer,
	stories_id integer,
	title text,
	url text
);

CREATE TABLE questionable_downloads_rows (
	downloads_id integer,
	feeds_id integer,
	stories_id integer,
	parent integer,
	url character varying(1024),
	"host" character varying(1024),
	download_time timestamp without time zone,
	type download_type,
	"state" download_state,
	"path" text,
	error_message text,
	priority integer,
	"sequence" integer,
	extracted boolean,
	old_download_time timestamp without time zone,
	old_state download_state
);

CREATE TABLE ssw_dump (
	stories_id integer,
	term character varying(256),
	stem character varying(256),
	stem_count smallint,
	sentence_number smallint,
	media_id integer,
	publish_day date
);

CREATE TABLE stories_description_not_salvaged (
	stories_id integer,
	media_id integer,
	url character varying(1024),
	guid character varying(1024),
	title text,
	description text,
	publish_date timestamp without time zone,
	collect_date timestamp without time zone,
	story_texts_id integer,
	full_text_rss boolean
);

CREATE TABLE total_daily_media_words (
	media_id integer,
	publish_day date,
	stem_count bigint,
	dashboard_topics_id integer
);

CREATE TABLE valid_trayvon_stories (
	stories_id integer
);

CREATE TABLE media_rss_full_text_detection_data (
	media_id integer,
	max_similarity real,
	avg_similarity double precision,
	min_similarity real,
	avg_extracted_length numeric,
	avg_rss_length numeric,
	avg_rss_discription numeric,
	"count" bigint
);

CREATE TABLE media_alexa_stats (
	media_alexa_stats_id integer primary key DEFAULT nextval('media_alexa_stats_media_alexa_stats_id_seq'::regclass) NOT NULL,
	media_id integer REFERENCES media(media_id) ON DELETE CASCADE,
	"day" date,
	reach_per_million double precision,
	page_views_per_million double precision,
	page_views_per_user double precision,
	"rank" integer
);

ALTER TABLE database_variables
	ALTER COLUMN database_variables_id TYPE integer /* TYPE change - table: database_variables original: serial          primary key new: integer */,
	ALTER COLUMN database_variables_id SET DEFAULT nextval('database_variables_datebase_variables_id_seq'::regclass),
	ALTER COLUMN database_variables_id SET NOT NULL;

ALTER TABLE media
	DROP COLUMN main_media_id,
	DROP COLUMN is_dup,
	ADD COLUMN dup_media_id integer         REFERENCES media(media_id) ON DELETE SET,
	ADD COLUMN is_not_dup boolean;

ALTER TABLE media_clusters
	ALTER COLUMN media_clusters_id TYPE serial    primary key /* TYPE change - table: media_clusters original: serial	primary key new: serial    primary key */,
	ALTER COLUMN media_cluster_runs_id TYPE int        not null references media_cluster_runs on delete cascade /* TYPE change - table: media_clusters original: int	    not null references media_cluster_runs on delete cascade new: int        not null references media_cluster_runs on delete cascade */;

ALTER TABLE media_cluster_words
	ALTER COLUMN media_cluster_words_id TYPE serial    primary key /* TYPE change - table: media_cluster_words original: serial	primary key new: serial    primary key */,
	ALTER COLUMN media_clusters_id TYPE int        not null references media_clusters on delete cascade /* TYPE change - table: media_cluster_words original: int	    not null references media_clusters on delete cascade new: int        not null references media_clusters on delete cascade */;

ALTER TABLE media_cluster_links
	ALTER COLUMN media_cluster_runs_id TYPE int        not null     references media_cluster_runs on delete cascade /* TYPE change - table: media_cluster_links original: int	    not null     references media_cluster_runs on delete cascade new: int        not null     references media_cluster_runs on delete cascade */;

ALTER TABLE media_cluster_zscores
	ALTER COLUMN media_cluster_runs_id TYPE int      not null     references media_cluster_runs on delete cascade /* TYPE change - table: media_cluster_zscores original: int 	 not null     references media_cluster_runs on delete cascade new: int      not null     references media_cluster_runs on delete cascade */;

ALTER TABLE stories
	ADD COLUMN story_texts_id integer;

ALTER TABLE ONLY downloads ALTER COLUMN "host" SET STATISTICS 10000;

ALTER TABLE stories_tags_map
	ALTER COLUMN stories_id TYPE int /* TYPE change - table: stories_tags_map original: int     not null references stories on delete cascade new: int */,
	ALTER COLUMN stories_id SET NOT NULL,
	ALTER COLUMN tags_id TYPE int /* TYPE change - table: stories_tags_map original: int     not null references tags on delete cascade new: int */,
	ALTER COLUMN tags_id SET NOT NULL;

ALTER TABLE top_ten_tags_for_media
	ALTER COLUMN media_id TYPE integer NOT NULL REFERENCES media(media_id) ON DELETE CASCADE /* TYPE change - table: top_ten_tags_for_media original: integer new: integer NOT NULL REFERENCES media(media_id) ON DELETE CASCADE */,
	ALTER COLUMN media_id DROP NOT NULL,
	ALTER COLUMN tags_id TYPE integer NOT NULL REFERENCES tags(tags_id) /* TYPE change - table: top_ten_tags_for_media original: integer new: integer NOT NULL REFERENCES tags(tags_id) */,
	ALTER COLUMN tags_id DROP NOT NULL,
	ALTER COLUMN tag_sets_id TYPE integer NOT NULL REFERENCES tag_sets(tag_sets_id) /* TYPE change - table: top_ten_tags_for_media original: integer new: integer NOT NULL REFERENCES tag_sets(tag_sets_id) */,
	ALTER COLUMN tag_sets_id DROP NOT NULL;

ALTER TABLE word_cloud_topics
	ALTER COLUMN source_tags_id TYPE int /* TYPE change - table: word_cloud_topics original: int         not null references tags new: int */,
	ALTER COLUMN source_tags_id SET NOT NULL;

ALTER TABLE total_top_500_weekly_words
	ALTER COLUMN total_top_500_weekly_words_id TYPE int          primary key /* TYPE change - table: total_top_500_weekly_words original: serial          primary key new: int          primary key */,
	ALTER COLUMN total_top_500_weekly_words_id SET DEFAULT nextval('total_top_500_weekly_words_total_top_500_words_id_seq'::regclass),
	ALTER COLUMN media_sets_id TYPE int             not null references media_sets(media_sets_id) on delete cascade /* TYPE change - table: total_top_500_weekly_words original: int             not null references media_sets on delete cascade new: int             not null references media_sets(media_sets_id) on delete cascade */,
	ALTER COLUMN dashboard_topics_id TYPE int             null references dashboard_topics(dashboard_topics_id) on delete cascade /* TYPE change - table: total_top_500_weekly_words original: int             null references dashboard_topics new: int             null references dashboard_topics(dashboard_topics_id) on delete cascade */;

ALTER TABLE total_top_500_weekly_author_words
	ALTER COLUMN total_top_500_weekly_author_words_id TYPE integer          primary key /* TYPE change - table: total_top_500_weekly_author_words original: serial          primary key new: integer          primary key */,
	ALTER COLUMN total_top_500_weekly_author_words_id SET DEFAULT nextval('total_top_500_weekly_author_words_total_top_500_words_id_seq'::regclass);

ALTER TABLE query_story_searches_stories_map
	ALTER COLUMN query_story_searches_id TYPE int REFERENCES query_story_searches(query_story_searches_id) ON DELETE CASCADE /* TYPE change - table: query_story_searches_stories_map original: int new: int REFERENCES query_story_searches(query_story_searches_id) ON DELETE CASCADE */,
	ALTER COLUMN stories_id TYPE int REFERENCES stories(stories_id) ON DELETE CASCADE /* TYPE change - table: query_story_searches_stories_map original: int new: int REFERENCES stories(stories_id) ON DELETE CASCADE */;

ALTER TABLE story_similarities
	ALTER COLUMN story_similarities_id TYPE integer primary key /* TYPE change - table: story_similarities original: serial primary key new: integer primary key */,
	ALTER COLUMN story_similarities_id SET DEFAULT nextval('story_similarities_story_similarities_id_seq1'::regclass);

ALTER TABLE controversy_stories
	ALTER COLUMN controversies_id TYPE int not null references controversies(controversies_id) on delete cascade /* TYPE change - table: controversy_stories original: int not null references controversies on delete cascade new: int not null references controversies(controversies_id) on delete cascade */,
	ALTER COLUMN stories_id TYPE int not null references stories(stories_id) on delete cascade /* TYPE change - table: controversy_stories original: int not null references stories on delete cascade new: int not null references stories(stories_id) on delete cascade */;

ALTER TABLE controversy_links
	ALTER COLUMN controversies_id TYPE int /* TYPE change - table: controversy_links original: int not null references controversies on delete cascade new: int */,
	ALTER COLUMN controversies_id SET NOT NULL,
	ALTER COLUMN stories_id TYPE int /* TYPE change - table: controversy_links original: int not null references stories on delete cascade new: int */,
	ALTER COLUMN stories_id SET NOT NULL;

ALTER SEQUENCE database_variables_datebase_variables_id_seq
	OWNED BY database_variables.database_variables_id;

ALTER SEQUENCE media_cluster_map_pole_simila_media_cluster_map_pole_simila_seq
	OWNED BY media_cluster_map_pole_similarities.media_cluster_map_pole_similarities_id;

ALTER SEQUENCE total_top_500_weekly_words_total_top_500_words_id_seq
	OWNED BY total_top_500_weekly_words.total_top_500_weekly_words_id;

ALTER SEQUENCE total_top_500_weekly_author_words_total_top_500_words_id_seq
	OWNED BY total_top_500_weekly_author_words.total_top_500_weekly_author_words_id;

ALTER SEQUENCE story_similarities_story_similarities_id_seq1
	OWNED BY story_similarities.story_similarities_id;

ALTER SEQUENCE story_similarities_story_similarities_id_seq2
	OWNED BY story_similarities_1000_tiny_idf.story_similarities_id;

ALTER SEQUENCE story_similarities_100_short_story_similarities_id_seq
	OWNED BY story_similarities_100_short.story_similarities_id;

ALTER SEQUENCE controversy_dates_controversy_dates_id_seq
	OWNED BY controversy_dates.controversy_dates_id;

ALTER SEQUENCE controversy_seed_urls_controversy_seed_urls_id_seq
	OWNED BY controversy_seed_urls.controversy_seed_urls_id;

ALTER SEQUENCE media_alexa_stats_media_alexa_stats_id_seq
	OWNED BY media_alexa_stats.media_alexa_stats_id;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4405;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

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

ALTER TABLE database_variables
	ADD CONSTRAINT database_variables_pkey PRIMARY KEY (database_variables_id);

ALTER TABLE media
	ADD CONSTRAINT media_self_dup CHECK (((dup_media_id IS NULL) OR (dup_media_id <> media_id)));

ALTER TABLE tags
	ADD CONSTRAINT no_lead_or_trailing_whitspace CHECK
            (tag_sets_id = 13 OR tag_sets_id = 9 OR tag_sets_id = 8 OR tag_sets_id = 6 OR tag::text = btrim(tag::text, ' 
    '::text));

ALTER TABLE media_cluster_runs
	ADD CONSTRAINT media_cluster_runs_state CHECK (((state)::text = ANY (ARRAY[('pending'::character varying)::text, ('executing'::character varying)::text, ('completed'::character varying)::text])));

ALTER TABLE media_cluster_maps
	ADD CONSTRAINT media_cluster_maps_type CHECK (((map_type)::text = ANY (ARRAY[('cluster'::character varying)::text, ('polar'::character varying)::text])));

ALTER TABLE stories_tags_map
	ADD CONSTRAINT stories_tags_map_tag FOREIGN KEY (tags_id) REFERENCES tags(tags_id) ON DELETE CASCADE;

ALTER TABLE stories_tags_map
	ADD CONSTRAINT stories_tags_map_story FOREIGN KEY (stories_id) REFERENCES stories(stories_id) ON DELETE CASCADE;

ALTER TABLE stories_tags_map
	ADD CONSTRAINT stories_tags_map_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES stories(stories_id) ON DELETE CASCADE;

ALTER TABLE stories_tags_map
	ADD CONSTRAINT stories_tags_map_tags_id_fkey FOREIGN KEY (tags_id) REFERENCES tags(tags_id) ON DELETE CASCADE;

ALTER TABLE word_cloud_topics
	ADD CONSTRAINT word_cloud_topics_source_tag_fk FOREIGN KEY (source_tags_id) REFERENCES tags(tags_id);

ALTER TABLE word_cloud_topics
	ADD CONSTRAINT word_cloud_topics_source_tags_id_fkey FOREIGN KEY (source_tags_id) REFERENCES tags(tags_id);

ALTER TABLE controversy_links
	ADD CONSTRAINT controversy_links_controversy_story_stories_id FOREIGN KEY (stories_id, controversies_id) REFERENCES controversy_stories(stories_id, controversies_id) ON DELETE CASCADE;

CREATE UNIQUE INDEX database_variables_name_key_index ON database_variables USING btree (name);

CREATE INDEX media_cluster_map_pole_similarities_map ON media_cluster_map_pole_similarities USING btree (media_cluster_maps_id);

CREATE INDEX story_similarities_1000_tiny_a_b ON story_similarities USING btree (stories_id_a, stories_id_b);

CREATE INDEX story_similarities_1000_tiny_a_s ON story_similarities USING btree (stories_id_a, similarity, publish_day_b);

CREATE INDEX story_similarities_1000_tiny_b_s ON story_similarities USING btree (stories_id_b, similarity, publish_day_a);

CREATE INDEX story_similarities_a_b ON story_similarities_1000_tiny_idf USING btree (stories_id_a, stories_id_b);

CREATE INDEX story_similarities_a_s ON story_similarities_1000_tiny_idf USING btree (stories_id_a, similarity, publish_day_b);

CREATE INDEX story_similarities_b_s ON story_similarities_1000_tiny_idf USING btree (stories_id_b, similarity, publish_day_a);

CREATE INDEX story_similarities_100_short_a_s ON story_similarities_100_short USING btree (stories_id_a, similarity, publish_day_b);

CREATE INDEX story_similarities_100_short_b_s ON story_similarities_100_short USING btree (stories_id_b, similarity, publish_day_a);

CREATE INDEX tar_downloads_queue_download ON tar_downloads_queue USING btree (downloads_id);

CREATE INDEX controversy_seed_urls_controversy ON controversy_seed_urls USING btree (controversies_id);

CREATE INDEX controversy_merged_stories_map_source ON controversy_merged_stories_map USING btree (source_stories_id);

CREATE INDEX cqssism_c ON controversy_query_story_searches_imported_stories_map USING btree (controversies_id);

CREATE INDEX cqssism_s ON controversy_query_story_searches_imported_stories_map USING btree (stories_id);

CREATE INDEX controversy_unmerged_media_media ON controversy_unmerged_media USING btree (media_id);

CREATE UNIQUE INDEX controversy_stories_sc ON controversy_stories USING btree (stories_id, controversies_id);

CREATE UNIQUE INDEX controversy_links_scr ON controversy_links USING btree (stories_id, controversies_id, ref_stories_id);

CREATE INDEX processed_stories_story ON processed_stories USING btree (stories_id);

CREATE INDEX media_rss_full_text_detection_data_media_1305311081 ON media_rss_full_text_detection_data USING btree (media_id);

CREATE INDEX media_alexa_stats_medium ON media_alexa_stats USING btree (media_id);

ALTER TABLE story_sentence_counts CLUSTER ON story_sentence_counts_pkey;

ALTER TABLE total_daily_words CLUSTER ON total_daily_words_pkey;

CREATE VIEW media_no_dups AS
	SELECT *
    FROM media
    WHERE dup_media_id IS NULL;

CREATE VIEW stories_collected_in_past_day AS
	SELECT stories.stories_id, stories.media_id, stories.url, stories.guid, stories.title, stories.description, stories.publish_date, stories.collect_date, stories.story_texts_id, stories.full_text_rss FROM stories WHERE (stories.collect_date > (now() - '1 day'::interval));

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

