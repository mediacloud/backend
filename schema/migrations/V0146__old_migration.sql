

DROP INDEX IF EXISTS relative_file_paths_to_verify;


CREATE OR REPLACE FUNCTION cat(text, text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
  DECLARE
    t text;
  BEGIN
return coalesce($1) || ' | ' || coalesce($2);
  END;
$_$;

CREATE INDEX tags_tag_sets_id ON tags USING btree (tag_sets_id);

CREATE INDEX queries_description ON queries USING btree (description);

CREATE INDEX queries_hash ON queries USING btree (md5(description));

CREATE UNIQUE INDEX queries_hash_version ON queries USING btree (md5(description), query_version);

CREATE INDEX queries_md5_signature ON queries USING btree (md5_signature);

CREATE INDEX stories_guid_non_unique ON stories USING btree (guid, media_id);

CREATE UNIQUE INDEX stories_guid_unique_temp ON stories USING btree (guid, media_id) WHERE (stories_id > 72728270);

CREATE INDEX relative_file_paths_to_verify ON downloads USING btree (relative_file_path) WHERE (((((file_status = 'tbd'::download_file_status) AND (relative_file_path <> 'tbd'::text)) AND (relative_file_path <> 'error'::text)) AND (relative_file_path <> 'na'::text)) AND (relative_file_path <> 'inline'::text));

CREATE INDEX downloads_in_old_format ON downloads USING btree (downloads_id) WHERE ((state = 'success'::download_state) AND (path ~~ 'content/%'::text));

CREATE INDEX file_status_downloads_time_new_format ON downloads USING btree (file_status, download_time) WHERE (relative_file_path ~~ 'mediacloud-%'::text);

CREATE INDEX relative_file_paths_new_format_to_verify ON downloads USING btree (relative_file_path) WHERE ((((((file_status = 'tbd'::download_file_status) AND (relative_file_path <> 'tbd'::text)) AND (relative_file_path <> 'error'::text)) AND (relative_file_path <> 'na'::text)) AND (relative_file_path <> 'inline'::text)) AND (relative_file_path ~~ 'mediacloud-%'::text));

CREATE INDEX relative_file_paths_old_format_to_verify ON downloads USING btree (relative_file_path) WHERE ((((((file_status = 'tbd'::download_file_status) AND (relative_file_path <> 'tbd'::text)) AND (relative_file_path <> 'error'::text)) AND (relative_file_path <> 'na'::text)) AND (relative_file_path <> 'inline'::text)) AND (NOT (relative_file_path ~~ 'mediacloud-%'::text)));

CREATE INDEX story_sentence_words_dm ON story_sentence_words USING btree (publish_day, media_id);

CREATE INDEX weekly_words_topic ON weekly_words USING btree (publish_week, dashboard_topics_id);

CREATE INDEX top_500_weekly_words_dmds ON top_500_weekly_words USING btree (publish_week, media_sets_id, dashboard_topics_id, stem);

CREATE INDEX total_daily_words_date ON total_daily_words USING btree (publish_day);

CREATE INDEX total_daily_words_date_dt ON total_daily_words USING btree (publish_day, dashboard_topics_id);

CREATE INDEX ssw_queue_stories_id ON ssw_queue USING btree (stories_id);

CREATE INDEX top_500_weekly_author_words_publish_week ON top_500_weekly_author_words USING btree (publish_week);

CREATE INDEX query_story_searches_stories_map_qss ON query_story_searches_stories_map USING btree (query_story_searches_id);

