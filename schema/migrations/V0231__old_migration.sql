

CREATE OR REPLACE VIEW daily_stats AS
    SELECT *
    FROM (
            SELECT COUNT(*) AS daily_downloads
            FROM downloads_in_past_day
         ) AS dd,
         (
            SELECT COUNT(*) AS daily_stories
            FROM stories_collected_in_past_day
         ) AS ds,
         (
            SELECT COUNT(*) AS downloads_to_be_extracted
            FROM downloads_to_be_extracted
         ) AS dex,
         (
            SELECT COUNT(*) AS download_errors
            FROM downloads_with_error_in_past_day
         ) AS er,
         (
             SELECT COALESCE( SUM( num_stories ), 0  ) AS solr_stories
            FROM solr_imports WHERE import_date > now() - interval '1 day'
         ) AS si;



