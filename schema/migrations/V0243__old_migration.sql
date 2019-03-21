


DROP FUNCTION loop_forever();

DROP FUNCTION add_query_version(new_query_version_enum_string character varying);

DROP FUNCTION show_stat_activity();

DROP FUNCTION cat(text, text);

DROP FUNCTION cancel_pg_process(cancel_pid integer);

DROP VIEW story_extracted_texts;

DROP VIEW media_feed_counts;

DROP TABLE url_discovery_counts;

DROP TABLE extractor_results_cache;

DROP TABLE feedless_stories;

DROP SEQUENCE IF EXISTS extractor_results_cache_extractor_results_cache_id_seq;


