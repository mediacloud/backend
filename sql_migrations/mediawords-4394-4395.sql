--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4394 and 4395.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4394, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4395, import this SQL file:
--
--     psql mediacloud < mediawords-4394-4395.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

DROP VIEW IF EXISTS controversy_links_cross_media CASCADE ;
DROP VIEW IF EXISTS media_dups_transitive  CASCADE ;
DROP VIEW IF EXISTS tags_with_sets  CASCADE ;
DROP VIEW IF EXISTS media_sets_tt2_locale_format  CASCADE ;
DROP VIEW IF EXISTS media_sets_explict_sw_data_dates  CASCADE ;
DROP VIEW IF EXISTS media_with_collections  CASCADE ;
DROP VIEW IF EXISTS dashboard_topics_tt2_locale_format  CASCADE ;
DROP VIEW IF EXISTS downloads_media  CASCADE ;
DROP VIEW IF EXISTS downloads_non_media  CASCADE ;
DROP VIEW IF EXISTS downloads_sites  CASCADE ;
DROP VIEW IF EXISTS media_extractor_training_downloads_count  CASCADE ;
DROP VIEW IF EXISTS yahoo_top_political_2008_media  CASCADE ;
DROP VIEW IF EXISTS technorati_top_political_2008_media  CASCADE ;
DROP VIEW IF EXISTS media_extractor_training_downloads_count_adjustments  CASCADE ;
DROP VIEW IF EXISTS media_adjusted_extractor_training_downloads_count  CASCADE ;
DROP VIEW IF EXISTS top_500_weekly_words_with_totals  CASCADE ;
DROP VIEW IF EXISTS top_500_weekly_words_normalized  CASCADE ;
DROP VIEW IF EXISTS daily_words_with_totals  CASCADE ;
DROP VIEW IF EXISTS story_extracted_texts  CASCADE ;
DROP VIEW IF EXISTS media_feed_counts  CASCADE ;
DROP VIEW IF EXISTS story_similarities_transitive  CASCADE ;
DROP VIEW IF EXISTS controversy_links_cross_media  CASCADE ;
DROP VIEW IF EXISTS stories_collected_in_past_day  CASCADE ;
DROP VIEW IF EXISTS downloads_to_be_extracted  CASCADE ;
DROP VIEW IF EXISTS downloads_in_past_day  CASCADE ;
DROP VIEW IF EXISTS downloads_with_error_in_past_day  CASCADE ;
DROP VIEW IF EXISTS daily_stats  CASCADE ;

ALTER TABLE daily_words
	ALTER COLUMN daily_words_id TYPE bigint  /* TYPE change - table: daily_words original: serial          primary key new: bigserial          primary key */;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4395;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

create view media_dups_transitive as     select distinct media_id, main_media_id from   ( ( select media_id, main_media_id from media where main_media_id is not null ) union ( select main_media_id as media_id, media_id as main_media_id from media where main_media_id is not null ) ) q;

--
create view tags_with_sets as select t.*, ts.name as tag_set_name from tags t, tag_sets ts where t.tag_sets_id = ts.tag_sets_id;

--
CREATE VIEW media_sets_tt2_locale_format as select  '[% c.loc("' || COALESCE( name, '') || '") %]' || E'\n' ||  '[% c.loc("' || COALESCE (description, '') || '") %] ' as tt2_value from media_sets where set_type = 'collection' order by media_sets_id;

--
CREATE VIEW media_sets_explict_sw_data_dates as  select media_sets_id, min(media.sw_data_start_date) as sw_data_start_date, max( media.sw_data_end_date) as sw_data_end_date from media_sets_media_map join media on (media_sets_media_map.media_id = media.media_id )   group by media_sets_id;

CREATE VIEW media_with_collections AS
    SELECT t.tag, m.media_id, m.url, m.name, m.moderated, m.feeds_added, m.moderation_notes, m.full_text_rss FROM media m, tags t, tag_sets ts, media_tags_map mtm WHERE (((((ts.name)::text = 'collection'::text) AND (ts.tag_sets_id = t.tag_sets_id)) AND (mtm.tags_id = t.tags_id)) AND (mtm.media_id = m.media_id)) ORDER BY m.media_id;
--
CREATE VIEW dashboard_topics_tt2_locale_format as select distinct on (tt2_value) '[% c.loc("' || name || '") %]' || ' - ' || '[% c.loc("' || lower(name) || '") %]' as tt2_value from (select * from dashboard_topics order by name, dashboard_topics_id) AS dashboard_topic_names order by tt2_value;

--
create view downloads_media as select d.*, f.media_id as _media_id from downloads d, feeds f where d.feeds_id = f.feeds_id;

create view downloads_non_media as select d.* from downloads d where d.feeds_id is null;

--
CREATE VIEW downloads_sites as select regexp_replace(host, $q$^(.)*?([^.]+)\.([^.]+)$$q$ ,E'\\2.\\3') as site, * from downloads_media;

--
CREATE VIEW media_extractor_training_downloads_count AS
    SELECT media.media_id, COALESCE(foo.extractor_training_downloads_for_media_id, (0)::bigint) AS extractor_training_download_count FROM (media LEFT JOIN (SELECT stories.media_id, count(stories.media_id) AS extractor_training_downloads_for_media_id FROM extractor_training_lines, downloads, stories WHERE ((extractor_training_lines.downloads_id = downloads.downloads_id) AND (downloads.stories_id = stories.stories_id)) GROUP BY stories.media_id ORDER BY stories.media_id) foo ON ((media.media_id = foo.media_id)));
--
CREATE VIEW yahoo_top_political_2008_media AS
    SELECT DISTINCT media_tags_map.media_id FROM media_tags_map, (SELECT tags.tags_id FROM tags, (SELECT DISTINCT media_tags_map.tags_id FROM media_tags_map ORDER BY media_tags_map.tags_id) media_tags WHERE ((tags.tags_id = media_tags.tags_id) AND ((tags.tag)::text ~~ 'yahoo_top_political_2008'::text))) interesting_media_tags WHERE (media_tags_map.tags_id = interesting_media_tags.tags_id) ORDER BY media_tags_map.media_id;
--
CREATE VIEW technorati_top_political_2008_media AS
    SELECT DISTINCT media_tags_map.media_id FROM media_tags_map, (SELECT tags.tags_id FROM tags, (SELECT DISTINCT media_tags_map.tags_id FROM media_tags_map ORDER BY media_tags_map.tags_id) media_tags WHERE ((tags.tags_id = media_tags.tags_id) AND ((tags.tag)::text ~~ 'technorati_top_political_2008'::text))) interesting_media_tags WHERE (media_tags_map.tags_id = interesting_media_tags.tags_id) ORDER BY media_tags_map.media_id;
--
CREATE VIEW media_extractor_training_downloads_count_adjustments AS
    SELECT yahoo.media_id, yahoo.yahoo_count_adjustment, tech.technorati_count_adjustment FROM (SELECT media_extractor_training_downloads_count.media_id, COALESCE(foo.yahoo_count_adjustment, 0) AS yahoo_count_adjustment FROM (media_extractor_training_downloads_count LEFT JOIN (SELECT yahoo_top_political_2008_media.media_id, 1 AS yahoo_count_adjustment FROM yahoo_top_political_2008_media) foo ON ((foo.media_id = media_extractor_training_downloads_count.media_id)))) yahoo, (SELECT media_extractor_training_downloads_count.media_id, COALESCE(foo.count_adjustment, 0) AS technorati_count_adjustment FROM (media_extractor_training_downloads_count LEFT JOIN (SELECT technorati_top_political_2008_media.media_id, 1 AS count_adjustment FROM technorati_top_political_2008_media) foo ON ((foo.media_id = media_extractor_training_downloads_count.media_id)))) tech WHERE (tech.media_id = yahoo.media_id);
--
CREATE VIEW media_adjusted_extractor_training_downloads_count AS
    SELECT media_extractor_training_downloads_count.media_id, ((media_extractor_training_downloads_count.extractor_training_download_count - (2 * media_extractor_training_downloads_count_adjustments.yahoo_count_adjustment)) - (2 * media_extractor_training_downloads_count_adjustments.technorati_count_adjustment)) AS count FROM (media_extractor_training_downloads_count JOIN media_extractor_training_downloads_count_adjustments ON ((media_extractor_training_downloads_count.media_id = media_extractor_training_downloads_count_adjustments.media_id))) ORDER BY ((media_extractor_training_downloads_count.extractor_training_download_count - (2 * media_extractor_training_downloads_count_adjustments.yahoo_count_adjustment)) - (2 * media_extractor_training_downloads_count_adjustments.technorati_count_adjustment));
--
create view top_500_weekly_words_with_totals as select t5.*, tt5.total_count from top_500_weekly_words t5, total_top_500_weekly_words tt5       where t5.media_sets_id = tt5.media_sets_id and t5.publish_week = tt5.publish_week and         ( ( t5.dashboard_topics_id = tt5.dashboard_topics_id ) or           ( t5.dashboard_topics_id is null and tt5.dashboard_topics_id is null ) );

create view top_500_weekly_words_normalized
    as select t5.stem, min(t5.term) as term,             ( least( 0.01, sum(t5.stem_count)::numeric / sum(t5.total_count)::numeric ) * count(*) ) as stem_count, t5.media_sets_id, t5.publish_week, t5.dashboard_topics_id         from top_500_weekly_words_with_totals t5    group by t5.stem, t5.publish_week, t5.media_sets_id, t5.dashboard_topics_id;
--
create view daily_words_with_totals as select d.*, t.total_count from daily_words d, total_daily_words t where d.media_sets_id = t.media_sets_id and d.publish_day = t.publish_day and ( ( d.dashboard_topics_id = t.dashboard_topics_id ) or ( d.dashboard_topics_id is null and t.dashboard_topics_id is null ) );

--
create view story_extracted_texts as select stories_id, array_to_string(array_agg(download_text), ' ') as extracted_text 
       from (select * from downloads natural join download_texts order by downloads_id) as downloads group by stories_id;
--
CREATE VIEW media_feed_counts as (SELECT media_id, count(*) as feed_count FROM feeds GROUP by media_id);

--
create view story_similarities_transitive as
    ( select story_similarities_id, stories_id_a, publish_day_a, stories_id_b, publish_day_b, similarity from story_similarities ) union  ( select story_similarities_id, stories_id_b as stories_id_a, publish_day_b as publish_day_a, stories_id_a as stories_id_b, publish_day_a as publish_day_b, similarity from story_similarities );
--
create view controversy_links_cross_media as
  select s.stories_id, substr(sm.name::text, 0, 24) as media_name, r.stories_id as ref_stories_id, substr(rm.name::text, 0, 24) as ref_media_name, substr(cl.url, 0, 144) as url, cs.controversies_id from media sm, media rm, controversy_links cl, stories s, stories r, controversy_stories cs where cl.ref_stories_id <> cl.stories_id and s.stories_id = cl.stories_id and cl.ref_stories_id = r.stories_id and s.media_id <> r.media_id and sm.media_id = s.media_id and rm.media_id = r.media_id and cs.stories_id = cl.ref_stories_id and cs.controversies_id = cl.controversies_id;
--
CREATE VIEW stories_collected_in_past_day as select * from stories where collect_date > now() - interval '1 day';

CREATE VIEW downloads_to_be_extracted as select * from downloads where extracted = 'f' and state = 'success' and type = 'content';

CREATE VIEW downloads_in_past_day as select * from downloads where download_time > now() - interval '1 day';
CREATE VIEW downloads_with_error_in_past_day as select * from downloads_in_past_day where state = 'error';

CREATE VIEW daily_stats as select * from (SELECT count(*) as daily_downloads from downloads_in_past_day) as dd, (select count(*) as daily_stories from stories_collected_in_past_day) ds , (select count(*) as downloads_to_be_extracted from downloads_to_be_extracted) dex, (select count(*) as download_errors from downloads_with_error_in_past_day ) er;



--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

