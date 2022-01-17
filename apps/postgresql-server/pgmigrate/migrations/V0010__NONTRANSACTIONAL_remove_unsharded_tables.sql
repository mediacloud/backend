-- noinspection SqlResolveForFile

CREATE FUNCTION public.drop_if_table_is_not_empty(table_name TEXT) RETURNS VOID AS
$$
DECLARE
    table_has_rows BIGINT;
BEGIN
    IF NOT EXISTS(SELECT 1 WHERE table_name ILIKE 'unsharded_%') THEN
        RAISE EXCEPTION 'Table name "%s" should start with "unsharded_".', table_name;
    END IF;
    EXECUTE 'SELECT 1 WHERE EXISTS (SELECT 1 FROM ' || table_name || ') ' INTO table_has_rows;
    IF table_has_rows THEN
        RAISE EXCEPTION 'Table "%s" is not empty.', table_name;
    END IF;
    EXECUTE 'DROP TABLE ' || table_name;
END
$$ LANGUAGE plpgsql;


-- Drop partitions first
DO
$$
    DECLARE

        tables CURSOR FOR
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'unsharded_public'
              AND (
                        tablename LIKE 'download_texts_%' OR
                        tablename LIKE 'downloads_success_content_%' OR
                        tablename LIKE 'downloads_success_feed_%' OR
                        tablename LIKE 'feeds_stories_map_p_%' OR
                        tablename LIKE 'stories_tags_map_p_%' OR
                        tablename LIKE 'story_sentences_p_%'
                )
            ORDER BY
                -- First drop "download_texts", then "downloads_" partitions
                tablename LIKE 'download_texts_%' DESC,
                tablename
        ;

    BEGIN
        FOR table_record IN tables
            LOOP
                PERFORM public.drop_if_table_is_not_empty('unsharded_public.' || table_record.tablename);
            END LOOP;
    END
$$;

-- Drop various tables
-- (not using CASCADE as we want to know what exactly it is that we're dropping here, i.e. there could be some
-- undocumented tables in production)
DROP VIEW public.auth_user_request_daily_counts;
SELECT public.drop_if_table_is_not_empty('unsharded_public.auth_user_request_daily_counts');

DROP VIEW public.download_texts;
SELECT public.drop_if_table_is_not_empty('unsharded_public.download_texts');

DROP VIEW public.downloads;
SELECT public.drop_if_table_is_not_empty('unsharded_public.downloads_error');
SELECT public.drop_if_table_is_not_empty('unsharded_public.downloads_success_content');
SELECT public.drop_if_table_is_not_empty('unsharded_public.downloads_success_feed');
SELECT public.drop_if_table_is_not_empty('unsharded_public.downloads_success');
SELECT public.drop_if_table_is_not_empty('unsharded_public.downloads');

DROP VIEW public.feeds_stories_map;
DROP VIEW unsharded_public.feeds_stories_map;
SELECT public.drop_if_table_is_not_empty('unsharded_public.feeds_stories_map_p');

DROP VIEW public.media_coverage_gaps;
SELECT public.drop_if_table_is_not_empty('unsharded_public.media_coverage_gaps');

DROP VIEW public.media_stats;
SELECT public.drop_if_table_is_not_empty('unsharded_public.media_stats');

DROP VIEW public.processed_stories;
SELECT public.drop_if_table_is_not_empty('unsharded_public.processed_stories');

DROP VIEW public.scraped_stories;
SELECT public.drop_if_table_is_not_empty('unsharded_public.scraped_stories');

DROP VIEW public.solr_import_stories;
SELECT public.drop_if_table_is_not_empty('unsharded_public.solr_import_stories');

DROP VIEW public.solr_imported_stories;
SELECT public.drop_if_table_is_not_empty('unsharded_public.solr_imported_stories');

DROP VIEW public.stories;
SELECT public.drop_if_table_is_not_empty('unsharded_public.stories');

DROP VIEW public.stories_ap_syndicated;
SELECT public.drop_if_table_is_not_empty('unsharded_public.stories_ap_syndicated');

DROP VIEW public.stories_tags_map;
DROP VIEW unsharded_public.stories_tags_map;
SELECT public.drop_if_table_is_not_empty('unsharded_public.stories_tags_map_p');

DROP VIEW public.story_enclosures;
SELECT public.drop_if_table_is_not_empty('unsharded_public.story_enclosures');

DROP VIEW public.story_sentences;
DROP VIEW unsharded_public.story_sentences;
SELECT public.drop_if_table_is_not_empty('unsharded_public.story_sentences_p');

DROP VIEW public.story_statistics;
SELECT public.drop_if_table_is_not_empty('unsharded_public.story_statistics');

DROP VIEW public.story_urls;
SELECT public.drop_if_table_is_not_empty('unsharded_public.story_urls');

DROP VIEW public.topic_fetch_urls;
SELECT public.drop_if_table_is_not_empty('unsharded_public.topic_fetch_urls');

DROP VIEW public.topic_links;
SELECT public.drop_if_table_is_not_empty('unsharded_public.topic_links');

DROP VIEW public.topic_merged_stories_map;
SELECT public.drop_if_table_is_not_empty('unsharded_public.topic_merged_stories_map');

DROP VIEW public.topic_post_urls;
SELECT public.drop_if_table_is_not_empty('unsharded_public.topic_post_urls');

DROP VIEW public.topic_posts;
SELECT public.drop_if_table_is_not_empty('unsharded_public.topic_posts');

DROP VIEW public.topic_seed_urls;
SELECT public.drop_if_table_is_not_empty('unsharded_public.topic_seed_urls');

DROP VIEW public.topic_stories;
SELECT public.drop_if_table_is_not_empty('unsharded_public.topic_stories');

DROP VIEW snap.live_stories;
SELECT public.drop_if_table_is_not_empty('unsharded_snap.live_stories');

DROP VIEW snap.media;
SELECT public.drop_if_table_is_not_empty('unsharded_snap.media');

DROP VIEW snap.media_tags_map;
SELECT public.drop_if_table_is_not_empty('unsharded_snap.media_tags_map');

DROP VIEW snap.medium_link_counts;
SELECT public.drop_if_table_is_not_empty('unsharded_snap.medium_link_counts');

DROP VIEW snap.medium_links;
SELECT public.drop_if_table_is_not_empty('unsharded_snap.medium_links');

DROP VIEW snap.stories;
SELECT public.drop_if_table_is_not_empty('unsharded_snap.stories');

DROP VIEW snap.stories_tags_map;
SELECT public.drop_if_table_is_not_empty('unsharded_snap.stories_tags_map');

DROP VIEW snap.story_link_counts;
SELECT public.drop_if_table_is_not_empty('unsharded_snap.story_link_counts');

DROP VIEW snap.story_links;
SELECT public.drop_if_table_is_not_empty('unsharded_snap.story_links');

DROP VIEW snap.timespan_posts;
SELECT public.drop_if_table_is_not_empty('unsharded_snap.timespan_posts');

DROP VIEW snap.topic_links_cross_media;
SELECT public.drop_if_table_is_not_empty('unsharded_snap.topic_links_cross_media');

DROP VIEW snap.topic_stories;
SELECT public.drop_if_table_is_not_empty('unsharded_snap.topic_stories');

-- Remove unused function
DROP FUNCTION public.drop_if_table_is_not_empty(TEXT);

-- Remove old functions and types
DROP FUNCTION unsharded_public.week_start_date(DATE);
DROP FUNCTION unsharded_public.half_md5(TEXT);
DROP FUNCTION unsharded_public.generate_api_key();
DROP FUNCTION unsharded_public.update_live_story();
DROP FUNCTION unsharded_public.story_sentences_view_insert_update_delete();
DROP FUNCTION unsharded_public.feeds_stories_map_view_insert_update_delete();
DROP FUNCTION unsharded_public.stories_tags_map_view_insert_update_delete();
DROP FUNCTION unsharded_public.insert_solr_import_story();
DROP FUNCTION unsharded_public.add_normalized_title_hash();
DROP TYPE unsharded_public.feed_type;
DROP TYPE unsharded_public.download_state;
DROP TYPE unsharded_public.download_type;
DROP TYPE unsharded_public.topics_job_queue_type;
DROP TYPE unsharded_public.bot_policy_type;
DROP TYPE unsharded_public.snap_period_type;
DROP TYPE unsharded_public.focal_technique_type;
DROP TYPE unsharded_public.topic_permission;
DROP TYPE unsharded_public.media_suggestions_status;
DROP TYPE unsharded_public.retweeter_scores_match_type;

-- Forgot to move this one in the previous migration
ALTER TYPE unsharded_public.schema_version_type SET SCHEMA public;

-- Remove unsharded schemas
DROP SCHEMA unsharded_public;
DROP SCHEMA unsharded_snap;
DROP SCHEMA unsharded_cache;
DROP SCHEMA unsharded_public_store;

-- Move sharded tables to "public"
ALTER TABLE sharded_public.auth_user_request_daily_counts
    SET SCHEMA public;
ALTER TABLE sharded_public.download_texts
    SET SCHEMA public;
ALTER TABLE sharded_public.downloads
    SET SCHEMA public;
ALTER TABLE sharded_public.downloads_error
    SET SCHEMA public;
ALTER TABLE sharded_public.downloads_feed_error
    SET SCHEMA public;
ALTER TABLE sharded_public.downloads_fetching
    SET SCHEMA public;
ALTER TABLE sharded_public.downloads_pending
    SET SCHEMA public;
ALTER TABLE sharded_public.downloads_success
    SET SCHEMA public;
ALTER TABLE sharded_public.feeds_stories_map
    SET SCHEMA public;
ALTER TABLE sharded_public.media_coverage_gaps
    SET SCHEMA public;
ALTER TABLE sharded_public.media_stats
    SET SCHEMA public;
ALTER TABLE sharded_public.processed_stories
    SET SCHEMA public;
ALTER TABLE sharded_public.scraped_stories
    SET SCHEMA public;
ALTER TABLE sharded_public.solr_import_stories
    SET SCHEMA public;
ALTER TABLE sharded_public.solr_imported_stories
    SET SCHEMA public;
ALTER TABLE sharded_public.stories
    SET SCHEMA public;
ALTER TABLE sharded_public.stories_ap_syndicated
    SET SCHEMA public;
ALTER TABLE sharded_public.stories_tags_map
    SET SCHEMA public;
ALTER TABLE sharded_public.story_enclosures
    SET SCHEMA public;
ALTER TABLE sharded_public.story_sentences
    SET SCHEMA public;
ALTER TABLE sharded_public.story_statistics
    SET SCHEMA public;
ALTER TABLE sharded_public.story_urls
    SET SCHEMA public;
ALTER TABLE sharded_public.topic_fetch_urls
    SET SCHEMA public;
ALTER TABLE sharded_public.topic_links
    SET SCHEMA public;
ALTER TABLE sharded_public.topic_merged_stories_map
    SET SCHEMA public;
ALTER TABLE sharded_public.topic_post_urls
    SET SCHEMA public;
ALTER TABLE sharded_public.topic_posts
    SET SCHEMA public;
ALTER TABLE sharded_public.topic_seed_urls
    SET SCHEMA public;
ALTER TABLE sharded_public.topic_stories
    SET SCHEMA public;
ALTER TABLE sharded_snap.live_stories
    SET SCHEMA snap;
ALTER TABLE sharded_snap.media
    SET SCHEMA snap;
ALTER TABLE sharded_snap.media_tags_map
    SET SCHEMA snap;
ALTER TABLE sharded_snap.medium_link_counts
    SET SCHEMA snap;
ALTER TABLE sharded_snap.medium_links
    SET SCHEMA snap;
ALTER TABLE sharded_snap.stories
    SET SCHEMA snap;
ALTER TABLE sharded_snap.stories_tags_map
    SET SCHEMA snap;
ALTER TABLE sharded_snap.story_link_counts
    SET SCHEMA snap;
ALTER TABLE sharded_snap.story_links
    SET SCHEMA snap;
ALTER TABLE sharded_snap.timespan_posts
    SET SCHEMA snap;
ALTER TABLE sharded_snap.topic_links_cross_media
    SET SCHEMA snap;
ALTER TABLE sharded_snap.topic_stories
    SET SCHEMA snap;

-- Remove sharded schemas
DROP SCHEMA sharded_public;
DROP SCHEMA sharded_snap;
DROP SCHEMA sharded_cache;
DROP SCHEMA sharded_public_store;

-- Recreate trigger functions to touch only the sharded tables

CREATE OR REPLACE FUNCTION update_live_story() RETURNS TRIGGER AS
$$

BEGIN

    UPDATE snap.live_stories
    SET media_id              = NEW.media_id,
        url                   = NEW.url,
        guid                  = NEW.guid,
        title                 = NEW.title,
        normalized_title_hash = NEW.normalized_title_hash,
        description           = NEW.description,
        publish_date          = NEW.publish_date,
        collect_date          = NEW.collect_date,
        full_text_rss         = NEW.full_text_rss,
        language              = NEW.language
    WHERE stories_id = NEW.stories_id;

    RETURN NEW;

END;

$$ LANGUAGE plpgsql;

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('update_live_story()');

CREATE OR REPLACE FUNCTION insert_solr_import_story() RETURNS TRIGGER AS
$$

DECLARE

    queue_stories_id BIGINT;
    return_value     RECORD;

BEGIN

    IF (TG_OP = 'UPDATE') OR (TG_OP = 'INSERT') THEN
        SELECT NEW.stories_id INTO queue_stories_id;
    ELSE
        SELECT OLD.stories_id INTO queue_stories_id;
    END IF;

    IF (TG_OP = 'UPDATE') OR (TG_OP = 'INSERT') THEN
        return_value := NEW;
    ELSE
        return_value := OLD;
    END IF;

    IF NOT EXISTS(
            SELECT 1
            FROM processed_stories
            WHERE stories_id = queue_stories_id
        ) THEN
        RETURN return_value;
    END IF;

    INSERT INTO solr_import_stories (stories_id)
    VALUES (queue_stories_id)
    ON CONFLICT (stories_id) DO NOTHING;

    RETURN return_value;

END;

$$ LANGUAGE plpgsql;

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('insert_solr_import_story()');


-- Recreate triggers
SELECT run_on_shards_or_raise('stories', $cmd$

    DROP TRIGGER stories_insert_solr_import_story ON %s

    $cmd$);
SELECT run_on_shards_or_raise('stories', $cmd$

    CREATE TRIGGER stories_insert_solr_import_story
        AFTER INSERT OR UPDATE OR DELETE
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE insert_solr_import_story();

    $cmd$);

SELECT run_on_shards_or_raise('processed_stories', $cmd$

    DROP TRIGGER processed_stories_insert_solr_import_story ON %s

    $cmd$);
SELECT run_on_shards_or_raise('processed_stories', $cmd$

    CREATE TRIGGER processed_stories_insert_solr_import_story
        AFTER INSERT OR UPDATE OR DELETE
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE insert_solr_import_story();

    $cmd$);

SELECT run_on_shards_or_raise('stories_tags_map', $cmd$

    DROP TRIGGER stories_tags_map_insert_solr_import_story ON %s

    $cmd$);
SELECT run_on_shards_or_raise('stories_tags_map', $cmd$

    CREATE TRIGGER stories_tags_map_insert_solr_import_story
        AFTER INSERT OR UPDATE OR DELETE
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE insert_solr_import_story();

    $cmd$);

SELECT run_on_shards_or_raise('topic_stories', $cmd$

    CREATE TRIGGER topic_stories_insert_live_story
        AFTER INSERT
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE insert_live_story();

    $cmd$);
