

ALTER TABLE controversy_stories
	ADD COLUMN valid_foreign_rss_story boolean DEFAULT false;


CREATE SCHEMA stories_tags_map_media_sub_tables;


DROP VIEW media_no_dups;

DROP VIEW stories_collected_in_past_day;

ALTER TABLE database_variables
	DROP CONSTRAINT database_variables_pkey;

ALTER TABLE media
	DROP CONSTRAINT media_self_dup;

ALTER TABLE tags
	DROP CONSTRAINT no_lead_or_trailing_whitspace;

ALTER TABLE media_cluster_runs
	DROP CONSTRAINT media_cluster_runs_state;

ALTER TABLE media_cluster_maps
	DROP CONSTRAINT media_cluster_maps_type;

ALTER TABLE stories_tags_map
	DROP CONSTRAINT stories_tags_map_tag;

ALTER TABLE stories_tags_map
	DROP CONSTRAINT stories_tags_map_story;

ALTER TABLE stories_tags_map
	DROP CONSTRAINT stories_tags_map_stories_id_fkey;

ALTER TABLE stories_tags_map
	DROP CONSTRAINT stories_tags_map_tags_id_fkey;

ALTER TABLE controversy_links
	DROP CONSTRAINT controversy_links_controversy_story_stories_id;

DROP INDEX database_variables_name_key_index;

DROP INDEX tags_tag_sets_id;

DROP INDEX queries_description;

DROP INDEX queries_hash;

DROP INDEX queries_hash_version;

DROP INDEX queries_md5_signature;

DROP INDEX media_rss_full_text_detection_data_media_1305311081;

DROP INDEX media_cluster_map_pole_similarities_map;

DROP INDEX stories_guid_non_unique;

DROP INDEX stories_guid_unique_temp;

DROP INDEX story_sentence_words_dm;

DROP INDEX weekly_words_topic;

DROP INDEX top_500_weekly_words_media_null_dashboard;

DROP INDEX top_500_weekly_words_dmds;

DROP INDEX total_daily_words_date;

DROP INDEX total_daily_words_date_dt;

DROP INDEX top_500_weekly_author_words_publish_week;

DROP INDEX query_story_searches_stories_map_qss;

DROP INDEX story_similarities_1000_tiny_a_b;

DROP INDEX story_similarities_1000_tiny_a_s;

DROP INDEX story_similarities_1000_tiny_b_s;

DROP INDEX controversy_merged_stories_map_source;

DROP INDEX controversy_stories_sc;

DROP INDEX controversy_links_scr;

DROP INDEX controversy_seed_urls_controversy;

DROP INDEX processed_stories_story;

DROP INDEX cqssism_c;

DROP INDEX cqssism_s;

DROP TABLE word_cloud_topics;

DROP TABLE ssw_queue;

DROP TABLE story_similarities_1000_tiny_idf;

DROP TABLE story_similarities_100_short;

DROP TABLE tar_downloads_queue;

DROP TABLE controversy_unmerged_media;

DROP TABLE adhoc_momentum;

DROP TABLE controversy_links_copy;

DROP TABLE controversy_links_copy_20120920;

DROP TABLE controversy_media_codes_20121020;

DROP TABLE controversy_stories_20121018;

DROP TABLE controversy_links_20121018;

DROP TABLE controversy_stories_copy;

DROP TABLE controversy_stories_copy_20120920;

DROP TABLE controversy_links_distinct;

DROP TABLE extractor_training_lines_corrupted_download_content;

DROP TABLE hr_pilot_study_stories;

DROP TABLE india_million;

DROP TABLE ma_ms_queue;

DROP TABLE pilot_story_sims;

DROP TABLE pilot_story_sims_code;

DROP TABLE pilot_study_stories;

DROP TABLE questionable_downloads_rows;

DROP TABLE ssw_dump;

DROP TABLE stories_description_not_salvaged;

DROP TABLE total_daily_media_words;

DROP TABLE valid_trayvon_stories;

DROP TABLE media_alexa_stats;

DROP SEQUENCE database_variables_datebase_variables_id_seq;

DROP SEQUENCE media_cluster_map_pole_simila_media_cluster_map_pole_simila_seq;

DROP SEQUENCE total_top_500_weekly_words_total_top_500_words_id_seq;

DROP SEQUENCE total_top_500_weekly_author_words_total_top_500_words_id_seq;

DROP SEQUENCE story_similarities_story_similarities_id_seq1;

DROP SEQUENCE story_similarities_story_similarities_id_seq2;

DROP SEQUENCE story_similarities_100_short_story_similarities_id_seq;

DROP SEQUENCE controversy_dates_controversy_dates_id_seq;

DROP SEQUENCE controversy_seed_urls_controversy_seed_urls_id_seq;

DROP SEQUENCE media_alexa_stats_media_alexa_stats_id_seq;

ALTER TABLE database_variables
	ALTER COLUMN database_variables_id TYPE serial          primary key /* TYPE change - table: database_variables original: integer new: serial          primary key */,
	ALTER COLUMN database_variables_id DROP DEFAULT,
	ALTER COLUMN database_variables_id DROP NOT NULL;

ALTER TABLE media
	ADD COLUMN use_pager boolean,
	ADD COLUMN unpaged_stories int             not null DEFAULT 0,
	ALTER COLUMN dup_media_id TYPE int             null references media on delete set /* TYPE change - table: media original: integer         REFERENCES media(media_id) ON DELETE SET new: int             null references media on delete set */;

ALTER TABLE feeds
	ADD COLUMN last_checksum text;

ALTER TABLE media_rss_full_text_detection_data
	DROP COLUMN avg_extracted_length,
	ADD COLUMN avg_expected_length numeric,
	ALTER COLUMN media_id TYPE int references media on delete cascade /* TYPE change - table: media_rss_full_text_detection_data original: integer new: int references media on delete cascade */;

ALTER TABLE media_clusters
	ALTER COLUMN media_clusters_id TYPE serial	primary key /* TYPE change - table: media_clusters original: serial    primary key new: serial	primary key */,
	ALTER COLUMN media_cluster_runs_id TYPE int	    not null references media_cluster_runs on delete cascade /* TYPE change - table: media_clusters original: int        not null references media_cluster_runs on delete cascade new: int	    not null references media_cluster_runs on delete cascade */;

ALTER TABLE media_cluster_map_pole_similarities
	ALTER COLUMN media_cluster_map_pole_similarities_id TYPE serial  primary key /* TYPE change - table: media_cluster_map_pole_similarities original: integer primary key new: serial  primary key */,
	ALTER COLUMN media_cluster_map_pole_similarities_id DROP DEFAULT,
	ALTER COLUMN media_cluster_map_pole_similarities_id DROP NOT NULL,
	ALTER COLUMN media_id TYPE int     not null references media on delete cascade /* TYPE change - table: media_cluster_map_pole_similarities original: integer NOT NULL REFERENCES media(media_id) new: int     not null references media on delete cascade */,
	ALTER COLUMN queries_id TYPE int     not null references queries on delete cascade /* TYPE change - table: media_cluster_map_pole_similarities original: integer NOT NULL REFERENCES queries(queries_id) new: int     not null references queries on delete cascade */,
	ALTER COLUMN similarity TYPE int /* TYPE change - table: media_cluster_map_pole_similarities original: integer new: int */,
	ALTER COLUMN media_cluster_maps_id TYPE int     not null references media_cluster_maps on delete cascade /* TYPE change - table: media_cluster_map_pole_similarities original: integer NOT NULL REFERENCES media_cluster_maps(media_cluster_maps_id) new: int     not null references media_cluster_maps on delete cascade */;

ALTER TABLE media_cluster_words
	ALTER COLUMN media_cluster_words_id TYPE serial	primary key /* TYPE change - table: media_cluster_words original: serial    primary key new: serial	primary key */,
	ALTER COLUMN media_clusters_id TYPE int	    not null references media_clusters on delete cascade /* TYPE change - table: media_cluster_words original: int        not null references media_clusters on delete cascade new: int	    not null references media_clusters on delete cascade */;

ALTER TABLE media_cluster_links
	ALTER COLUMN media_cluster_runs_id TYPE int	    not null     references media_cluster_runs on delete cascade /* TYPE change - table: media_cluster_links original: int        not null     references media_cluster_runs on delete cascade new: int	    not null     references media_cluster_runs on delete cascade */;

ALTER TABLE media_cluster_zscores
	ALTER COLUMN media_cluster_runs_id TYPE int 	 not null     references media_cluster_runs on delete cascade /* TYPE change - table: media_cluster_zscores original: int      not null     references media_cluster_runs on delete cascade new: int 	 not null     references media_cluster_runs on delete cascade */;

ALTER TABLE stories
	DROP COLUMN story_texts_id;

ALTER TABLE ONLY downloads ALTER COLUMN "host" SET STATISTICS -1;

ALTER TABLE stories_tags_map
	ALTER COLUMN stories_id TYPE int     not null references stories on delete cascade /* TYPE change - table: stories_tags_map original: int new: int     not null references stories on delete cascade */,
	ALTER COLUMN stories_id DROP NOT NULL,
	ALTER COLUMN tags_id TYPE int     not null references tags on delete cascade /* TYPE change - table: stories_tags_map original: int new: int     not null references tags on delete cascade */,
	ALTER COLUMN tags_id DROP NOT NULL;

ALTER TABLE top_ten_tags_for_media
	ALTER COLUMN media_id TYPE integer /* TYPE change - table: top_ten_tags_for_media original: integer NOT NULL REFERENCES media(media_id) ON DELETE CASCADE new: integer */,
	ALTER COLUMN media_id SET NOT NULL,
	ALTER COLUMN tags_id TYPE integer /* TYPE change - table: top_ten_tags_for_media original: integer NOT NULL REFERENCES tags(tags_id) new: integer */,
	ALTER COLUMN tags_id SET NOT NULL,
	ALTER COLUMN tag_sets_id TYPE integer /* TYPE change - table: top_ten_tags_for_media original: integer NOT NULL REFERENCES tag_sets(tag_sets_id) new: integer */,
	ALTER COLUMN tag_sets_id SET NOT NULL;

ALTER TABLE total_top_500_weekly_words
	ALTER COLUMN total_top_500_weekly_words_id TYPE serial          primary key /* TYPE change - table: total_top_500_weekly_words original: int          primary key new: serial          primary key */,
	ALTER COLUMN total_top_500_weekly_words_id DROP DEFAULT,
	ALTER COLUMN media_sets_id TYPE int             not null references media_sets on delete cascade /* TYPE change - table: total_top_500_weekly_words original: int             not null references media_sets(media_sets_id) on delete cascade new: int             not null references media_sets on delete cascade */,
	ALTER COLUMN dashboard_topics_id TYPE int             null references dashboard_topics /* TYPE change - table: total_top_500_weekly_words original: int             null references dashboard_topics(dashboard_topics_id) on delete cascade new: int             null references dashboard_topics */;

ALTER TABLE total_top_500_weekly_author_words
	ALTER COLUMN total_top_500_weekly_author_words_id TYPE serial          primary key /* TYPE change - table: total_top_500_weekly_author_words original: integer          primary key new: serial          primary key */,
	ALTER COLUMN total_top_500_weekly_author_words_id DROP DEFAULT;

ALTER TABLE query_story_searches_stories_map
	ALTER COLUMN query_story_searches_id TYPE int references query_story_searches on delete cascade /* TYPE change - table: query_story_searches_stories_map original: int REFERENCES query_story_searches(query_story_searches_id) ON DELETE CASCADE new: int references query_story_searches on delete cascade */,
	ALTER COLUMN stories_id TYPE int references stories on delete cascade /* TYPE change - table: query_story_searches_stories_map original: int REFERENCES stories(stories_id) ON DELETE CASCADE new: int references stories on delete cascade */;

ALTER TABLE story_similarities
	ALTER COLUMN story_similarities_id TYPE serial primary key /* TYPE change - table: story_similarities original: integer primary key new: serial primary key */,
	ALTER COLUMN story_similarities_id DROP DEFAULT;

ALTER TABLE controversy_dates
	ALTER COLUMN controversy_dates_id TYPE serial primary key /* TYPE change - table: controversy_dates original: integer primary key new: serial primary key */,
	ALTER COLUMN controversy_dates_id DROP DEFAULT,
	ALTER COLUMN controversy_dates_id DROP NOT NULL,
	ALTER COLUMN controversies_id TYPE int not null references controversies on delete cascade /* TYPE change - table: controversy_dates original: integer NOT NULL REFERENCES controversies(controversies_id) ON DELETE CASCADE new: int not null references controversies on delete cascade */;

ALTER TABLE controversy_merged_stories_map
	ALTER COLUMN source_stories_id TYPE int not null references stories on delete cascade /* TYPE change - table: controversy_merged_stories_map original: integer NOT NULL REFERENCES stories(stories_id) ON DELETE CASCADE new: int not null references stories on delete cascade */,
	ALTER COLUMN target_stories_id TYPE int not null references stories on delete cascade /* TYPE change - table: controversy_merged_stories_map original: integer NOT NULL REFERENCES stories(stories_id) ON DELETE CASCADE new: int not null references stories on delete cascade */;

ALTER TABLE controversy_stories
	ADD COLUMN valid_foreign_rss_story boolean DEFAULT false,
	ALTER COLUMN controversies_id TYPE int not null references controversies on delete cascade /* TYPE change - table: controversy_stories original: int not null references controversies(controversies_id) on delete cascade new: int not null references controversies on delete cascade */,
	ALTER COLUMN stories_id TYPE int not null references stories on delete cascade /* TYPE change - table: controversy_stories original: int not null references stories(stories_id) on delete cascade new: int not null references stories on delete cascade */;

ALTER TABLE controversy_seed_urls
	ALTER COLUMN controversy_seed_urls_id TYPE serial primary key /* TYPE change - table: controversy_seed_urls original: integer primary key new: serial primary key */,
	ALTER COLUMN controversy_seed_urls_id DROP DEFAULT,
	ALTER COLUMN controversy_seed_urls_id DROP NOT NULL,
	ALTER COLUMN controversies_id TYPE int not null references controversies on delete cascade /* TYPE change - table: controversy_seed_urls original: integer NOT NULL REFERENCES controversies(controversies_id) ON DELETE CASCADE new: int not null references controversies on delete cascade */,
	ALTER COLUMN stories_id TYPE int references stories on delete cascade /* TYPE change - table: controversy_seed_urls original: integer REFERENCES stories(stories_id) ON DELETE CASCADE new: int references stories on delete cascade */,
	ALTER COLUMN processed TYPE boolean not null /* TYPE change - table: controversy_seed_urls original: boolean new: boolean not null */,
	ALTER COLUMN processed DROP NOT NULL;

ALTER TABLE controversy_query_story_searches_imported_stories_map
	ALTER COLUMN controversies_id TYPE int not null references controversies on delete cascade /* TYPE change - table: controversy_query_story_searches_imported_stories_map original: integer NOT NULL REFERENCES controversies(controversies_id) ON DELETE CASCADE new: int not null references controversies on delete cascade */,
	ALTER COLUMN stories_id TYPE int not null references stories on delete cascade /* TYPE change - table: controversy_query_story_searches_imported_stories_map original: integer NOT NULL REFERENCES stories(stories_id) ON DELETE CASCADE new: int not null references stories on delete cascade */;


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

ALTER TABLE media
	ADD CONSTRAINT media_self_dup CHECK ( dup_media_id IS NULL OR dup_media_id <> media_id );

ALTER TABLE media_cluster_runs
	ADD CONSTRAINT media_cluster_runs_state check (state in ('pending', 'executing', 'completed'));

ALTER TABLE media_cluster_maps
	ADD CONSTRAINT media_cluster_maps_type check( map_type in ('cluster', 'polar' ));

ALTER TABLE controversy_links
	ADD CONSTRAINT controversy_links_controversy_story_stories_id foreign key ( stories_id, controversies_id ) references controversy_stories ( stories_id, controversies_id )
    on delete cascade;

CREATE INDEX tags_tag_sets_id ON tags (tag_sets_id);

CREATE UNIQUE INDEX queries_hash_version ON queries (md5_signature, query_version);

CREATE INDEX queries_md5_signature ON queries (md5_signature);

CREATE INDEX media_rss_full_text_detection_data_media ON media_rss_full_text_detection_data (media_id);

CREATE INDEX media_cluster_map_pole_similarities_map ON media_cluster_map_pole_similarities (media_cluster_maps_id);

CREATE UNIQUE INDEX stories_guid ON stories (guid, media_id);

CREATE INDEX story_sentence_words_dm ON story_sentence_words (publish_day, media_id);

CREATE INDEX weekly_words_topic ON weekly_words (publish_week, dashboard_topics_id);

CREATE INDEX top_500_weekly_words_media_null_dashboard ON top_500_weekly_words (publish_week,media_sets_id, dashboard_topics_id) 
    where dashboard_topics_id is null;

CREATE INDEX top_500_weekly_words_dmds ON top_500_weekly_words using btree (publish_week, media_sets_id, dashboard_topics_id, stem);

CREATE INDEX top_500_weekly_author_words_publish_week ON top_500_weekly_author_words (publish_week);

CREATE INDEX story_similarities_a_b ON story_similarities ( stories_id_a, stories_id_b );

CREATE INDEX story_similarities_a_s ON story_similarities ( stories_id_a, similarity, publish_day_b );

CREATE INDEX story_similarities_b_s ON story_similarities ( stories_id_b, similarity, publish_day_a );

CREATE INDEX controversy_merged_stories_map_source ON controversy_merged_stories_map ( source_stories_id );

CREATE UNIQUE INDEX controversy_stories_sc ON controversy_stories ( stories_id, controversies_id );

CREATE UNIQUE INDEX controversy_links_scr ON controversy_links ( stories_id, controversies_id, ref_stories_id );

CREATE INDEX controversy_seed_urls_controversy ON controversy_seed_urls ( controversies_id );

CREATE INDEX processed_stories_story ON processed_stories ( stories_id );

CREATE INDEX cqssism_c ON controversy_query_story_searches_imported_stories_map ( controversies_id );

CREATE INDEX cqssism_s ON controversy_query_story_searches_imported_stories_map ( stories_id );

CREATE VIEW stories_collected_in_past_day AS
	select * from stories where collect_date > now() - interval '1 day';
	
	