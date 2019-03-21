


DROP TABLE bitly_clicks_daily;

DROP FUNCTION upsert_bitly_clicks_daily(param_stories_id INT, param_day DATE, param_click_count INT);

DROP FUNCTION bitly_clicks_daily_partition_by_stories_id_insert_trigger();


