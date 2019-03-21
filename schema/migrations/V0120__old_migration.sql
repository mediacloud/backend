


DROP VIEW media_sets_tt2_locale_format;

DROP VIEW dashboard_topics_tt2_locale_format;

DROP TABLE IF EXISTS controversy_query_story_searches_imported_stories_map;

DROP TABLE IF EXISTS query_story_searches_stories_map;

DROP TABLE IF EXISTS query_story_searches;

DROP TABLE queries_country_counts_json;

DROP TABLE queries;

DROP TABLE dashboard_media_sets;

DROP TABLE story_subsets_processed_stories_map;

DROP TABLE story_subsets;

DROP TABLE media_sets_media_map;

DROP TABLE media_sets;

DROP TABLE dashboard_topics;

DROP TABLE dashboards;


DELETE FROM auth_roles WHERE role = 'query-create';


