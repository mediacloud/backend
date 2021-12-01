-- noinspection SqlResolveForFile

-- Create schemas to temporarily move the sharded tables to
CREATE SCHEMA sharded_public;
CREATE SCHEMA sharded_public_store;
CREATE SCHEMA sharded_snap;
CREATE SCHEMA sharded_cache;


--
-- DROP UNUSED VIEWS
--

DROP VIEW unsharded_public.controversies;

DROP VIEW unsharded_public.controversy_dumps;

DROP VIEW unsharded_public.controversy_dump_time_slices;

DROP VIEW unsharded_public.daily_stats;

DROP VIEW unsharded_public.downloads_media;

DROP VIEW unsharded_public.downloads_non_media;

DROP VIEW unsharded_public.downloads_to_be_extracted;

DROP VIEW unsharded_public.downloads_with_error_in_past_day;

DROP VIEW unsharded_public.downloads_in_past_day;

DROP VIEW unsharded_public.tags_with_sets;

DROP VIEW unsharded_public.media_with_media_types;

DROP VIEW unsharded_public.topic_links_cross_media;

DROP VIEW unsharded_public.feedly_unscraped_feeds;

DROP VIEW unsharded_public.stories_collected_in_past_day;

DROP VIEW unsharded_public.topics_with_user_permission;

DROP VIEW unsharded_public.topic_post_stories;

DROP VIEW unsharded_public.pending_job_states;


--
-- DROP UNUSED SEQUENCES
--

DROP SEQUENCE unsharded_public.task_id_sequence;



--
-- MOVE ALL ROWS OF SMALL TABLES
--


--
-- database_variables
--
INSERT INTO public.database_variables (database_variables_id,
                                       name,
                                       value)
SELECT database_variables_id::BIGINT,
       name::TEXT,
       value::TEXT
FROM unsharded_public.database_variables;

SELECT setval(
               pg_get_serial_sequence('public.database_variables', 'database_variables_id'),
               nextval(pg_get_serial_sequence('unsharded_public.database_variables', 'database_variables_id')),
               false
           );

TRUNCATE unsharded_public.database_variables;
DROP TABLE unsharded_public.database_variables;


--
-- color_sets
--
INSERT INTO public.color_sets (color_sets_id,
                               color,
                               color_set,
                               id)
SELECT color_sets_id::BIGINT,
       color::TEXT,
       color_set::TEXT,
       id::TEXT
FROM unsharded_public.color_sets

-- Previous migration pre-inserted a bunch of color sets that are already
-- present in the sharded table
ON CONFLICT (color_set, id) DO NOTHING;

SELECT setval(
               pg_get_serial_sequence('public.color_sets', 'color_sets_id'),
               nextval(pg_get_serial_sequence('unsharded_public.color_sets', 'color_sets_id')),
               false
           );

TRUNCATE unsharded_public.color_sets;
DROP TABLE unsharded_public.color_sets;


--
-- queued_downloads
--
INSERT INTO public.queued_downloads (
    -- queued_downloads_id is not referenced anywhere so we can reset it here
    downloads_id)
SELECT downloads_id
FROM unsharded_public.queued_downloads;

TRUNCATE unsharded_public.queued_downloads;
DROP TABLE unsharded_public.queued_downloads;


--
-- topic_modes
--

-- "unsharded_public.topic_modes" and "public.topic_modes" are
-- identical

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.topics
    DROP CONSTRAINT topics_mode_fkey;

TRUNCATE unsharded_public.topic_modes;
DROP TABLE unsharded_public.topic_modes;


--
-- topic_platforms
--

-- "unsharded_public.topic_platforms" and "public.topic_platforms" are
-- identical

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.topic_platforms_sources_map
    DROP CONSTRAINT topic_platforms_sources_map_topic_platforms_id_fkey;
ALTER TABLE unsharded_public.topic_seed_queries
    DROP CONSTRAINT topic_seed_queries_platform_fkey;
ALTER TABLE unsharded_public.topics
    DROP CONSTRAINT topics_platform_fkey;

TRUNCATE unsharded_public.topic_platforms;
DROP TABLE unsharded_public.topic_platforms;



--
-- topic_sources
--

-- "unsharded_public.topic_sources" and "public.topic_sources" are
-- identical

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.topic_platforms_sources_map
    DROP CONSTRAINT topic_platforms_sources_map_topic_sources_id_fkey;
ALTER TABLE unsharded_public.topic_seed_queries
    DROP CONSTRAINT topic_seed_queries_source_fkey;

TRUNCATE unsharded_public.topic_sources;
DROP TABLE unsharded_public.topic_sources;



--
-- topic_platforms_sources_map
--

-- "unsharded_public.topic_platforms_sources_map" and
-- "public.topic_platforms_sources_map" are identical

TRUNCATE unsharded_public.topic_platforms_sources_map;
DROP TABLE unsharded_public.topic_platforms_sources_map;



--
-- media
--

-- To be recreated later
SELECT run_on_shards_or_raise('media', $cmd$

    DROP TRIGGER media_rescraping_add_initial_state_trigger ON %s;

    $cmd$);

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.media_normalized_url;
DROP INDEX public.media_name_fts;
DROP INDEX public.media_dup_media_id;

INSERT INTO public.media (media_id,
                          url,
                          normalized_url,
                          name,
                          full_text_rss,
                          foreign_rss_links,
                          dup_media_id,
                          is_not_dup,
                          content_delay,
                          editor_notes,
                          public_notes,
                          is_monitored)
SELECT media_id::BIGINT,
       url::TEXT,
       normalized_url::TEXT,
       name::TEXT,
       full_text_rss,
       foreign_rss_links,
       dup_media_id::BIGINT,
       is_not_dup,
       content_delay,
       editor_notes,
       public_notes,
       is_monitored
FROM unsharded_public.media;

SELECT setval(
               pg_get_serial_sequence('public.media', 'media_id'),
               nextval(pg_get_serial_sequence('unsharded_public.media', 'media_id')),
               false
           );

-- Recreate indexes
CREATE INDEX media_normalized_url ON public.media (normalized_url);
CREATE INDEX media_name_fts ON public.media USING GIN (to_tsvector('english', name));
CREATE INDEX media_dup_media_id ON public.media (dup_media_id);

-- Recreate triggers
SELECT run_on_shards_or_raise('media', $cmd$

    CREATE TRIGGER media_rescraping_add_initial_state_trigger
        AFTER INSERT
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE media_rescraping_add_initial_state_trigger();

    $cmd$);

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.topic_media_codes
    -- That's how it's called in production
    DROP CONSTRAINT IF EXISTS controversy_media_codes_media_id_fkey;
ALTER TABLE unsharded_public.topic_media_codes
    DROP CONSTRAINT IF EXISTS topic_media_codes_media_id_fkey;
ALTER TABLE unsharded_public.feeds
    DROP CONSTRAINT feeds_media_id_fkey;
ALTER TABLE unsharded_public.feeds_after_rescraping
    DROP CONSTRAINT feeds_after_rescraping_media_id_fkey;
ALTER TABLE unsharded_public.media_coverage_gaps
    DROP CONSTRAINT media_coverage_gaps_media_id_fkey;
ALTER TABLE unsharded_public.media
    DROP CONSTRAINT media_dup_media_id_fkey;
ALTER TABLE unsharded_public.media_health
    -- Doesn't exist in production
    DROP CONSTRAINT IF EXISTS media_health_media_id_fkey;
ALTER TABLE unsharded_public.media_expected_volume
    -- Doesn't exist in production
    DROP CONSTRAINT IF EXISTS media_expected_volume_media_id_fkey;
ALTER TABLE unsharded_public.media_rescraping
    DROP CONSTRAINT media_rescraping_media_id_fkey;
ALTER TABLE unsharded_public.media_stats
    DROP CONSTRAINT media_stats_media_id_fkey;
ALTER TABLE unsharded_public.media_stats_weekly
    -- Doesn't exist in production
    DROP CONSTRAINT IF EXISTS media_stats_weekly_media_id_fkey;
ALTER TABLE unsharded_public.media_suggestions
    DROP CONSTRAINT media_suggestions_media_id_fkey;
ALTER TABLE unsharded_public.media_tags_map
    DROP CONSTRAINT media_tags_map_media_id_fkey;
ALTER TABLE unsharded_public.retweeter_media
    DROP CONSTRAINT retweeter_media_media_id_fkey;
ALTER TABLE unsharded_public.stories
    DROP CONSTRAINT stories_media_id_fkey;
ALTER TABLE unsharded_public.topics_media_map
    DROP CONSTRAINT topics_media_map_media_id_fkey;

DO
$$
    DECLARE

        tables CURSOR FOR
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'unsharded_public'
              AND tablename LIKE 'story_sentences_p_%'
            ORDER BY tablename;

    BEGIN
        FOR table_record IN tables
            LOOP

                EXECUTE '
            ALTER TABLE unsharded_public.' || table_record.tablename || '
                DROP CONSTRAINT ' || table_record.tablename || '_media_id_fkey
        ';

            END LOOP;
    END
$$;

TRUNCATE unsharded_public.media;
DROP TABLE unsharded_public.media;



--
-- media_rescraping
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.media_rescraping_last_rescrape_time;

INSERT INTO public.media_rescraping (
    -- Primary key does not exist in the source table
    media_id,
    disable,
    last_rescrape_time)
SELECT media_id::BIGINT,
       disable,
       last_rescrape_time
FROM unsharded_public.media_rescraping;

-- Recreate indexes
CREATE INDEX media_rescraping_last_rescrape_time
    ON public.media_rescraping (last_rescrape_time);

TRUNCATE unsharded_public.media_rescraping;
DROP TABLE unsharded_public.media_rescraping;



--
-- feeds
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.feeds_media_id;
DROP INDEX public.feeds_name;
DROP INDEX public.feeds_last_attempted_download_time;
DROP INDEX public.feeds_last_successful_download_time;

INSERT INTO public.feeds (feeds_id,
                          media_id,
                          name,
                          url,
                          type,
                          active,
                          last_checksum,
                          last_attempted_download_time,
                          last_successful_download_time,
                          last_new_story_time)
SELECT feeds_id::BIGINT,
       media_id::BIGINT,
       name::TEXT,
       url::TEXT,
       type::TEXT::public.feed_type,
       active,
       last_checksum::VARCHAR(32),
       last_attempted_download_time,
       last_successful_download_time,
       last_new_story_time
FROM unsharded_public.feeds;

SELECT setval(
               pg_get_serial_sequence('public.feeds', 'feeds_id'),
               nextval(pg_get_serial_sequence('unsharded_public.feeds', 'feeds_id')),
               false
           );

-- Recreate indexes
CREATE INDEX feeds_media_id ON public.feeds (media_id);
CREATE INDEX feeds_name ON public.feeds (name);
CREATE INDEX feeds_last_attempted_download_time ON public.feeds (last_attempted_download_time);
CREATE INDEX feeds_last_successful_download_time ON public.feeds (last_successful_download_time);

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.downloads
    DROP CONSTRAINT downloads_feeds_id_fkey;
ALTER TABLE unsharded_public.feeds_tags_map
    DROP CONSTRAINT feeds_tags_map_feeds_id_fkey;
ALTER TABLE unsharded_public.scraped_feeds
    DROP CONSTRAINT scraped_feeds_feeds_id_fkey;

DO
$$
    DECLARE

        tables CURSOR FOR
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'unsharded_public'
              AND tablename LIKE 'feeds_stories_map_p_%'
            ORDER BY tablename;

    BEGIN
        FOR table_record IN tables
            LOOP

                EXECUTE '
            ALTER TABLE unsharded_public.' || table_record.tablename || '
                DROP CONSTRAINT ' || table_record.tablename || '_feeds_id_fkey
        ';

            END LOOP;
    END
$$;

TRUNCATE unsharded_public.feeds;
DROP TABLE unsharded_public.feeds;



--
-- feeds_after_rescraping
--

INSERT INTO public.feeds_after_rescraping (feeds_after_rescraping_id,
                                           media_id,
                                           name,
                                           url,
                                           type)
SELECT feeds_after_rescraping_id::BIGINT,
       media_id::BIGINT,
       name::TEXT,
       url::TEXT,
       type::TEXT::feed_type
FROM unsharded_public.feeds_after_rescraping;

SELECT setval(
               pg_get_serial_sequence('public.feeds_after_rescraping', 'feeds_after_rescraping_id'),
               nextval(pg_get_serial_sequence('unsharded_public.feeds_after_rescraping', 'feeds_after_rescraping_id')),
               false
           );

TRUNCATE unsharded_public.feeds_after_rescraping;
DROP TABLE unsharded_public.feeds_after_rescraping;



--
-- tag_sets
--

INSERT INTO public.tag_sets (tag_sets_id,
                             name,
                             label,
                             description,
                             show_on_media,
                             show_on_stories)
SELECT tag_sets_id::BIGINT,
       name::TEXT,
       label::TEXT,
       description,
       show_on_media,
       show_on_stories
FROM unsharded_public.tag_sets
-- Previous migration pre-inserted a bunch of tag sets that are already
-- present in the sharded table
ON CONFLICT (name) DO NOTHING;

SELECT setval(
               pg_get_serial_sequence('public.tag_sets', 'tag_sets_id'),
               nextval(pg_get_serial_sequence('unsharded_public.tag_sets', 'tag_sets_id')),
               false
           );

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.auth_users_tag_sets_permissions
    DROP CONSTRAINT auth_users_tag_sets_permissions_tag_sets_id_fkey;
ALTER TABLE unsharded_public.tags
    DROP CONSTRAINT tags_tag_sets_id_fkey;
ALTER TABLE unsharded_public.topics
    DROP CONSTRAINT topics_media_type_tag_sets_id_fkey;

TRUNCATE unsharded_public.tag_sets;
DROP TABLE unsharded_public.tag_sets;



--
-- tags
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.tags_tag_sets_id;
DROP INDEX public.tags_label;
DROP INDEX public.tags_fts;
DROP INDEX public.tags_show_on_media;
DROP INDEX public.tags_show_on_stories;

INSERT INTO public.tags (tags_id,
                         tag_sets_id,
                         tag,
                         label,
                         description,
                         show_on_media,
                         show_on_stories,
                         is_static)
SELECT tags_id::BIGINT,
       tag_sets_id::BIGINT,
       tag::TEXT,
       label::TEXT,
       description,
       show_on_media,
       show_on_stories,
       is_static
FROM unsharded_public.tags;

SELECT setval(
               pg_get_serial_sequence('public.tags', 'tags_id'),
               nextval(pg_get_serial_sequence('unsharded_public.tags', 'tags_id')),
               false
           );

-- Recreate indexes
CREATE INDEX tags_tag_sets_id ON public.tags (tag_sets_id);
CREATE INDEX tags_label ON public.tags USING HASH (label);
CREATE INDEX tags_fts ON public.tags USING GIN (to_tsvector('english'::regconfig, tag || ' ' || label));
CREATE INDEX tags_show_on_media ON public.tags USING HASH (show_on_media);
CREATE INDEX tags_show_on_stories ON public.tags USING HASH (show_on_stories);

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.timespans
    DROP CONSTRAINT timespans_tags_id_fkey;
ALTER TABLE unsharded_public.feeds_tags_map
    DROP CONSTRAINT feeds_tags_map_tags_id_fkey;
ALTER TABLE unsharded_public.media_suggestions_tags_map
    DROP CONSTRAINT media_suggestions_tags_map_tags_id_fkey;
ALTER TABLE unsharded_public.media_tags_map
    DROP CONSTRAINT media_tags_map_tags_id_fkey;
ALTER TABLE unsharded_public.topics_media_tags_map
    DROP CONSTRAINT topics_media_tags_map_tags_id_fkey;

DO
$$
    DECLARE

        tables CURSOR FOR
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'unsharded_public'
              AND tablename LIKE 'stories_tags_map_p_%'
            ORDER BY tablename;

    BEGIN
        FOR table_record IN tables
            LOOP

                EXECUTE '
            ALTER TABLE unsharded_public.' || table_record.tablename || '
                DROP CONSTRAINT ' || table_record.tablename || '_tags_id_fkey
        ';

            END LOOP;
    END
$$;

TRUNCATE unsharded_public.tags;
DROP TABLE unsharded_public.tags;



--
-- feeds_tags_map
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.feeds_tags_map (
    -- Primary key is not important
    feeds_id,
    tags_id)
SELECT feeds_id::BIGINT,
       tags_id::BIGINT
FROM unsharded_public.feeds_tags_map;

TRUNCATE unsharded_public.feeds_tags_map;
DROP TABLE unsharded_public.feeds_tags_map;



--
-- media_tags_map
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.media_tags_map_media_id;
DROP INDEX public.media_tags_map_tags_id;

INSERT INTO public.media_tags_map (
    -- Primary key is not important
    media_id,
    tags_id,
    tagged_date)
SELECT media_id::BIGINT,
       tags_id::BIGINT,
       tagged_date
FROM unsharded_public.media_tags_map;

-- Recreate indexes
CREATE INDEX media_tags_map_media_id ON public.media_tags_map (media_id);
CREATE INDEX media_tags_map_tags_id ON public.media_tags_map (tags_id);

TRUNCATE unsharded_public.media_tags_map;
DROP TABLE unsharded_public.media_tags_map;



--
-- solr_imports
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.solr_imports_date;

INSERT INTO public.solr_imports (
    -- Primary key is not important
    import_date,
    full_import,
    num_stories)
SELECT import_date,
       full_import,
       num_stories
FROM unsharded_public.solr_imports;

-- Recreate indexes
CREATE INDEX solr_imports_date ON public.solr_imports (import_date);

TRUNCATE unsharded_public.solr_imports;
DROP TABLE unsharded_public.solr_imports;



--
-- scraped_feeds
--

INSERT INTO public.scraped_feeds (
    -- Primary key is not important
    feeds_id,
    scrape_date,
    import_module)
SELECT feeds_id::BIGINT,
       scrape_date,
       import_module
FROM unsharded_public.scraped_feeds;

TRUNCATE unsharded_public.scraped_feeds;
DROP TABLE unsharded_public.scraped_feeds;



--
-- auth_users
--

-- To be recreated later
SELECT run_on_shards_or_raise('auth_users', $cmd$

    DROP TRIGGER auth_user_api_keys_add_non_ip_limited_api_key ON %s;

    $cmd$);

SELECT run_on_shards_or_raise('auth_users', $cmd$

    DROP TRIGGER auth_users_set_default_limits ON %s;

    $cmd$);

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.auth_users_created_day;

INSERT INTO public.auth_users (auth_users_id,
                               email,
                               password_hash,
                               full_name,
                               notes,
                               active,
                               password_reset_token_hash,
                               last_unsuccessful_login_attempt,
                               created_date,
                               has_consented)
SELECT auth_users_id::BIGINT,
       email,
       password_hash,
       full_name,
       notes,
       active,
       password_reset_token_hash,
       last_unsuccessful_login_attempt,
       created_date,
       has_consented
FROM unsharded_public.auth_users;

SELECT setval(
               pg_get_serial_sequence('public.auth_users', 'auth_users_id'),
               nextval(pg_get_serial_sequence('unsharded_public.auth_users', 'auth_users_id')),
               false
           );

-- Recreate indexes
CREATE INDEX auth_users_created_day ON public.auth_users (date_trunc('day', created_date));

-- Recreate triggers
SELECT run_on_shards_or_raise('auth_users', $cmd$

    CREATE TRIGGER auth_user_api_keys_add_non_ip_limited_api_key
        AFTER INSERT
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE auth_user_api_keys_add_non_ip_limited_api_key();

    $cmd$);

SELECT run_on_shards_or_raise('auth_users', $cmd$

    CREATE TRIGGER auth_users_set_default_limits
        AFTER INSERT
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE auth_users_set_default_limits();

    $cmd$);

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.auth_user_api_keys
    -- Only exists in production
    DROP CONSTRAINT IF EXISTS auth_user_ip_tokens_auth_users_id_fkey;
ALTER TABLE unsharded_public.auth_user_api_keys
    DROP CONSTRAINT IF EXISTS auth_user_api_keys_auth_users_id_fkey;
ALTER TABLE unsharded_public.auth_user_limits
    DROP CONSTRAINT auth_user_limits_auth_users_id_fkey;
ALTER TABLE unsharded_public.auth_users_roles_map
    -- Only exists in production
    DROP CONSTRAINT IF EXISTS auth_users_roles_map_users_id_fkey;
ALTER TABLE unsharded_public.auth_users_roles_map
    DROP CONSTRAINT IF EXISTS auth_users_roles_map_auth_users_id_fkey;
ALTER TABLE unsharded_public.auth_users_tag_sets_permissions
    DROP CONSTRAINT auth_users_tag_sets_permissions_auth_users_id_fkey;
ALTER TABLE unsharded_public.media_suggestions
    DROP CONSTRAINT media_suggestions_auth_users_id_fkey;
ALTER TABLE unsharded_public.media_suggestions
    DROP CONSTRAINT media_suggestions_mark_auth_users_id_fkey;
ALTER TABLE unsharded_public.topic_permissions
    DROP CONSTRAINT topic_permissions_auth_users_id_fkey;

TRUNCATE unsharded_public.auth_users;
DROP TABLE unsharded_public.auth_users;



--
-- auth_user_api_keys
--

INSERT INTO public.auth_user_api_keys (
    -- Primary key is not important
    auth_users_id,
    api_key,
    ip_address)
SELECT auth_users_id::BIGINT,
       api_key,
       ip_address
FROM unsharded_public.auth_user_api_keys;

TRUNCATE unsharded_public.auth_user_api_keys;
DROP TABLE unsharded_public.auth_user_api_keys;



--
-- auth_roles
--

-- Production has some weird non-standard auth_roles.auth_roles_id which we'll want to use
WITH all_auth_roles_ids AS (
    SELECT auth_roles_id
    FROM public.auth_roles
)
DELETE
FROM public.auth_roles
WHERE public.auth_roles.auth_roles_id IN (
    SELECT auth_roles_id
    FROM all_auth_roles_ids
);

INSERT INTO public.auth_roles (auth_roles_id,
                               role,
                               description)
SELECT auth_roles_id::BIGINT,
       role,
       description
FROM unsharded_public.auth_roles;

SELECT setval(
               pg_get_serial_sequence('public.auth_roles', 'auth_roles_id'),
               nextval(pg_get_serial_sequence('unsharded_public.auth_roles', 'auth_roles_id')),
               false
           );

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.auth_users_roles_map
    -- Only exists in production
    DROP CONSTRAINT IF EXISTS auth_users_roles_map_roles_id_fkey;
ALTER TABLE unsharded_public.auth_users_roles_map
    DROP CONSTRAINT IF EXISTS auth_users_roles_map_auth_roles_id_fkey;

TRUNCATE unsharded_public.auth_roles;
DROP TABLE unsharded_public.auth_roles;



--
-- auth_users_roles_map
--

INSERT INTO public.auth_users_roles_map (
    -- Primary key is not important
    auth_users_id,
    auth_roles_id)
SELECT auth_users_id::BIGINT,
       auth_roles_id::BIGINT
FROM unsharded_public.auth_users_roles_map;

TRUNCATE unsharded_public.auth_users_roles_map;
DROP TABLE unsharded_public.auth_users_roles_map;



--
-- auth_user_limits
--

INSERT INTO public.auth_user_limits (
    -- Primary key is not important
    auth_users_id,
    weekly_requests_limit,
    weekly_requested_items_limit,
    max_topic_stories)
SELECT auth_users_id::BIGINT,
       weekly_requests_limit::BIGINT,
       weekly_requested_items_limit::BIGINT,
       max_topic_stories::BIGINT
FROM unsharded_public.auth_user_limits;

TRUNCATE unsharded_public.auth_user_limits;
DROP TABLE unsharded_public.auth_user_limits;



--
-- auth_users_tag_sets_permissions
--

INSERT INTO public.auth_users_tag_sets_permissions (
    -- Primary key is not important
    auth_users_id,
    tag_sets_id,
    apply_tags,
    create_tags,
    edit_tag_set_descriptors,
    edit_tag_descriptors)
SELECT auth_users_id::BIGINT,
       tag_sets_id::BIGINT,
       apply_tags,
       create_tags,
       edit_tag_set_descriptors,
       edit_tag_descriptors
FROM unsharded_public.auth_users_tag_sets_permissions;

TRUNCATE unsharded_public.auth_users_tag_sets_permissions;
DROP TABLE unsharded_public.auth_users_tag_sets_permissions;



--
-- activities
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.activities_name;
DROP INDEX public.activities_creation_date;
DROP INDEX public.activities_user_identifier;
DROP INDEX public.activities_object_id;

INSERT INTO public.activities (
    -- Primary key is not important
    name,
    creation_date,
    user_identifier,
    object_id,
    reason,
    description)
SELECT name::TEXT,
       creation_date,
       user_identifier,
       object_id,
       reason,
       description_json::JSONB
FROM unsharded_public.activities;

-- Recreate indexes
CREATE INDEX activities_name ON public.activities (name);
CREATE INDEX activities_creation_date ON public.activities (creation_date);
CREATE INDEX activities_user_identifier ON public.activities (user_identifier);
CREATE INDEX activities_object_id ON public.activities (object_id);

TRUNCATE unsharded_public.activities;
DROP TABLE unsharded_public.activities;



--
-- feeds_from_yesterday
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.feeds_from_yesterday_feeds_id;
DROP INDEX public.feeds_from_yesterday_media_id;
DROP INDEX public.feeds_from_yesterday_name;

INSERT INTO public.feeds_from_yesterday (
    -- Primary key does not exist in the source table
    feeds_id,
    media_id,
    name,
    url,
    type,
    active)
SELECT feeds_id::BIGINT,
       media_id::BIGINT,
       name::TEXT,
       url::TEXT,
       type::TEXT::public.feed_type,
       active
FROM unsharded_public.feeds_from_yesterday;

-- Recreate indexes
CREATE INDEX feeds_from_yesterday_feeds_id ON public.feeds_from_yesterday (feeds_id);
CREATE INDEX feeds_from_yesterday_media_id ON public.feeds_from_yesterday (media_id);
CREATE INDEX feeds_from_yesterday_name ON public.feeds_from_yesterday (name);

TRUNCATE unsharded_public.feeds_from_yesterday;
DROP TABLE unsharded_public.feeds_from_yesterday;



--
-- api_links
--

INSERT INTO public.api_links (api_links_id,
                              path,
                              params,
                              next_link_id,
                              previous_link_id)
SELECT api_links_id,
       path,
       params_json::JSONB,
       next_link_id,
       previous_link_id
FROM unsharded_public.api_links;

SELECT setval(
               pg_get_serial_sequence('public.api_links', 'api_links_id'),
               nextval(pg_get_serial_sequence('unsharded_public.api_links', 'api_links_id')),
               false
           );

TRUNCATE unsharded_public.api_links;
DROP TABLE unsharded_public.api_links;



--
-- media_suggestions_tags_map
--

INSERT INTO public.media_suggestions_tags_map (
    -- Primary key does not exist in the source table
    media_suggestions_id,
    tags_id)
SELECT media_suggestions_id::BIGINT,
       tags_id::BIGINT
FROM unsharded_public.media_suggestions_tags_map;

TRUNCATE unsharded_public.media_suggestions_tags_map;
DROP TABLE unsharded_public.media_suggestions_tags_map;



--
-- media_suggestions
--

INSERT INTO public.media_suggestions (media_suggestions_id,
                                      name,
                                      url,
                                      feed_url,
                                      reason,
                                      auth_users_id,
                                      mark_auth_users_id,
                                      date_submitted,
                                      media_id,
                                      date_marked,
                                      mark_reason,
                                      status)
SELECT media_suggestions_id::BIGINT,
       name,
       url,
       feed_url,
       reason,
       auth_users_id::BIGINT,
       mark_auth_users_id::BIGINT,
       date_submitted,
       media_id::BIGINT,
       date_marked,
       mark_reason,
       status::TEXT::public.media_suggestions_status
FROM unsharded_public.media_suggestions;

SELECT setval(
               pg_get_serial_sequence('public.media_suggestions', 'media_suggestions_id'),
               nextval(pg_get_serial_sequence('unsharded_public.media_suggestions', 'media_suggestions_id')),
               false
           );

TRUNCATE unsharded_public.media_suggestions;
DROP TABLE unsharded_public.media_suggestions;



--
-- mediacloud_stats
--

INSERT INTO public.mediacloud_stats (
    -- Primary key does not exist in the source table
    stats_date,
    daily_downloads,
    daily_stories,
    active_crawled_media,
    active_crawled_feeds,
    total_stories,
    total_downloads,
    total_sentences)
SELECT stats_date,
       daily_downloads,
       daily_stories,
       active_crawled_media,
       active_crawled_feeds,
       total_stories,
       total_downloads,
       total_sentences
FROM unsharded_public.mediacloud_stats;

TRUNCATE unsharded_public.mediacloud_stats;
DROP TABLE unsharded_public.mediacloud_stats;



--
-- media_stats_weekly
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.media_stats_weekly_media_id;

INSERT INTO public.media_stats_weekly (
    -- Primary key does not exist in the source table
    media_id,
    stories_rank,
    num_stories,
    sentences_rank,
    num_sentences,
    stat_week)
SELECT media_id::BIGINT,
       stories_rank::BIGINT,
       num_stories,
       sentences_rank::BIGINT,
       num_sentences,
       stat_week
FROM unsharded_public.media_stats_weekly;

-- Recreate indexes
CREATE INDEX media_stats_weekly_media_id ON public.media_stats_weekly (media_id);

TRUNCATE unsharded_public.media_stats_weekly;
DROP TABLE unsharded_public.media_stats_weekly;



--
-- media_expected_volume
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.media_expected_volume_media_id;

INSERT INTO public.media_expected_volume (
    -- Primary key does not exist in the source table
    media_id,
    start_date,
    end_date,
    expected_stories,
    expected_sentences)
SELECT media_id::BIGINT,
       start_date,
       end_date,
       expected_stories,
       expected_sentences
FROM unsharded_public.media_expected_volume;

-- Recreate indexes
CREATE INDEX media_expected_volume_media_id ON public.media_expected_volume (media_id);

TRUNCATE unsharded_public.media_expected_volume;
DROP TABLE unsharded_public.media_expected_volume;



--
-- media_health
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.media_health_media_id;
DROP INDEX public.media_health_is_healthy;
DROP INDEX public.media_health_num_stories_90;

INSERT INTO public.media_health (
    -- Primary key is not important
    media_id,
    num_stories,
    num_stories_y,
    num_stories_w,
    num_stories_90,
    num_sentences,
    num_sentences_y,
    num_sentences_w,
    num_sentences_90,
    is_healthy,
    has_active_feed,
    start_date,
    end_date,
    expected_sentences,
    expected_stories,
    coverage_gaps)
SELECT media_id::BIGINT,
       num_stories,
       num_stories_y,
       num_stories_w,
       num_stories_90,
       num_sentences,
       num_sentences_y,
       num_sentences_w,
       num_sentences_90,
       is_healthy,
       has_active_feed,
       start_date,
       end_date,
       expected_sentences,
       expected_stories,
       coverage_gaps::BIGINT
FROM unsharded_public.media_health;

-- Recreate indexes
CREATE INDEX media_health_media_id ON public.media_health (media_id);
CREATE INDEX media_health_is_healthy ON public.media_health (is_healthy);
CREATE INDEX media_health_num_stories_90 ON public.media_health (num_stories_90);

TRUNCATE unsharded_public.media_health;
DROP TABLE unsharded_public.media_health;



--
-- public_store.timespan_files
--

INSERT INTO public_store.timespan_files (
    -- Primary key is not important
    object_id,
    raw_data)
SELECT object_id::BIGINT,
       raw_data
FROM unsharded_public_store.timespan_files;

TRUNCATE unsharded_public_store.timespan_files;
DROP TABLE unsharded_public_store.timespan_files;



--
-- public_store.snapshot_files
--

INSERT INTO public_store.snapshot_files (
    -- Primary key is not important
    object_id,
    raw_data)
SELECT object_id::BIGINT,
       raw_data
FROM unsharded_public_store.snapshot_files;

TRUNCATE unsharded_public_store.snapshot_files;
DROP TABLE unsharded_public_store.snapshot_files;



--
-- public_store.timespan_maps
--

INSERT INTO public_store.timespan_maps (
    -- Primary key is not important
    object_id,
    raw_data)
SELECT object_id::BIGINT,
       raw_data
FROM unsharded_public_store.timespan_maps;

TRUNCATE unsharded_public_store.timespan_maps;
DROP TABLE unsharded_public_store.timespan_maps;



--
-- raw_downloads
--
-- Even though the downloads are not copied at this point, there's no foreign
-- key from raw_downloads to downloads in the sharded layout, plus the table in
-- production is very small (although it should have been empty), so we can
-- just copy it at this point
--

INSERT INTO public.raw_downloads (
    -- Primary key is not important
    object_id,
    raw_data)
SELECT object_id::BIGINT,
       raw_data
FROM unsharded_public.raw_downloads;

-- No references in the unsharded schema so safe to drop
TRUNCATE unsharded_public.raw_downloads;
DROP TABLE unsharded_public.raw_downloads;



--
-- topics
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.topics (topics_id,
                           name,
                           pattern,
                           solr_seed_query,
                           solr_seed_query_run,
                           description,
                           media_type_tag_sets_id,
                           max_iterations,
                           state,
                           message,
                           is_public,
                           is_logogram,
                           start_date,
                           end_date,
                           respider_stories,
                           respider_start_date,
                           respider_end_date,
                           snapshot_periods,
                           platform,
                           mode,
                           job_queue,
                           max_stories,
                           is_story_index_ready,
                           only_snapshot_engaged_stories)
SELECT topics_id::BIGINT,
       name::TEXT,
       pattern,
       solr_seed_query,
       solr_seed_query_run,
       description,
       media_type_tag_sets_id::BIGINT,
       max_iterations::BIGINT,
       state,
       message,
       is_public,
       is_logogram,
       start_date,
       end_date,
       respider_stories,
       respider_start_date,
       respider_end_date,
       snapshot_periods,
       platform::TEXT,
       mode::TEXT,
       job_queue::TEXT::public.topics_job_queue_type,
       max_stories::BIGINT,
       is_story_index_ready,
       only_snapshot_engaged_stories
FROM unsharded_public.topics;

SELECT setval(
               pg_get_serial_sequence('public.topics', 'topics_id'),
               nextval(pg_get_serial_sequence('unsharded_public.topics', 'topics_id')),
               false
           );

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.focal_set_definitions
    DROP CONSTRAINT focal_set_definitions_topics_id_fkey;
ALTER TABLE unsharded_public.retweeter_scores
    DROP CONSTRAINT retweeter_scores_topics_id_fkey;
ALTER TABLE unsharded_public.snapshots
    -- Exists only on production
    DROP CONSTRAINT IF EXISTS controversy_dumps_controversies_id_fkey;
ALTER TABLE unsharded_public.snapshots
    DROP CONSTRAINT IF EXISTS snapshots_topics_id_fkey;
ALTER TABLE unsharded_public.topic_dates
    -- Exists only in production
    DROP CONSTRAINT IF EXISTS controversy_dates_controversies_id_fkey;
ALTER TABLE unsharded_public.topic_dates
    DROP CONSTRAINT IF EXISTS topic_dates_topics_id_fkey;
ALTER TABLE unsharded_public.topic_fetch_urls
    DROP CONSTRAINT topic_fetch_urls_topics_id_fkey;
ALTER TABLE unsharded_public.topic_media_codes
    -- Exists only in production
    DROP CONSTRAINT IF EXISTS controversy_media_codes_controversies_id_fkey;
ALTER TABLE unsharded_public.topic_media_codes
    DROP CONSTRAINT IF EXISTS topic_media_codes_topics_id_fkey;
ALTER TABLE unsharded_public.topic_permissions
    DROP CONSTRAINT topic_permissions_topics_id_fkey;
ALTER TABLE unsharded_public.topic_query_story_searches_imported_stories_map
    DROP CONSTRAINT topic_query_story_searches_imported_stories_map_topics_id_fkey;
ALTER TABLE unsharded_public.topic_seed_queries
    DROP CONSTRAINT topic_seed_queries_topics_id_fkey;
ALTER TABLE unsharded_public.topic_seed_urls
    -- Exists only in production
    DROP CONSTRAINT IF EXISTS controversy_seed_urls_controversies_id_fkey;
ALTER TABLE unsharded_public.topic_seed_urls
    DROP CONSTRAINT topic_seed_urls_topics_id_fkey;
ALTER TABLE unsharded_public.topic_spider_metrics
    DROP CONSTRAINT topic_spider_metrics_topics_id_fkey;
ALTER TABLE unsharded_public.topic_stories
    -- Exists only in production
    DROP CONSTRAINT IF EXISTS controversy_stories_controversies_id_fkey;
ALTER TABLE unsharded_public.topic_stories
    DROP CONSTRAINT topic_stories_topics_id_fkey;
ALTER TABLE unsharded_public.topics_media_map
    DROP CONSTRAINT topics_media_map_topics_id_fkey;
ALTER TABLE unsharded_public.topics_media_tags_map
    DROP CONSTRAINT topics_media_tags_map_topics_id_fkey;
ALTER TABLE unsharded_snap.live_stories
    DROP CONSTRAINT live_stories_topics_id_fkey;

TRUNCATE unsharded_public.topics;
DROP TABLE unsharded_public.topics;



--
-- topic_seed_queries
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.topic_seed_queries (topic_seed_queries_id,
                                       topics_id,
                                       source,
                                       platform,
                                       query,
                                       imported_date,
                                       ignore_pattern)
SELECT topic_seed_queries_id::BIGINT,
       topics_id::BIGINT,
       source::TEXT,
       platform::TEXT,
       query,
       imported_date,
       ignore_pattern
FROM unsharded_public.topic_seed_queries;

SELECT setval(
               pg_get_serial_sequence('public.topic_seed_queries', 'topic_seed_queries_id'),
               nextval(pg_get_serial_sequence('unsharded_public.topic_seed_queries', 'topic_seed_queries_id')),
               false
           );

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.topic_post_days
    DROP CONSTRAINT topic_post_days_topic_seed_queries_id_fkey;
ALTER TABLE unsharded_public.topic_seed_urls
    -- Exists only on production
    DROP CONSTRAINT IF EXISTS topic_seed_urls_query;
ALTER TABLE unsharded_public.topic_seed_urls
    DROP CONSTRAINT topic_seed_urls_topic_seed_queries_id_fkey;

TRUNCATE unsharded_public.topic_seed_queries;
DROP TABLE unsharded_public.topic_seed_queries;



--
-- topic_dates
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.topic_dates (topic_dates_id,
                                topics_id,
                                start_date,
                                end_date,
                                boundary)
SELECT topic_dates_id::BIGINT,
       topics_id::BIGINT,
       start_date,
       end_date,
       boundary
FROM unsharded_public.topic_dates;

SELECT setval(
               pg_get_serial_sequence('public.topic_dates', 'topic_dates_id'),
               nextval(pg_get_serial_sequence('unsharded_public.topic_dates', 'topic_dates_id')),
               false
           );

TRUNCATE unsharded_public.topic_dates;
DROP TABLE unsharded_public.topic_dates;



--
-- topics_media_map
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.topics_media_map (
    -- Primary key does not exist in the source table
    topics_id,
    media_id)
SELECT topics_id::BIGINT,
       media_id::BIGINT
FROM unsharded_public.topics_media_map;

TRUNCATE unsharded_public.topics_media_map;
DROP TABLE unsharded_public.topics_media_map;



--
-- topics_media_tags_map
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.topics_media_tags_map (
    -- Primary key does not exist in the source table
    topics_id,
    tags_id)
SELECT topics_id::BIGINT,
       tags_id::BIGINT
FROM unsharded_public.topics_media_tags_map;

TRUNCATE unsharded_public.topics_media_tags_map;
DROP TABLE unsharded_public.topics_media_tags_map;



--
-- topic_media_codes
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.topic_media_codes (
    -- Primary key does not exist in the source table
    topics_id,
    media_id,
    code_type,
    code)
SELECT topics_id::BIGINT,
       media_id::BIGINT,
       code_type,
       code
FROM unsharded_public.topic_media_codes;

TRUNCATE unsharded_public.topic_media_codes;
DROP TABLE unsharded_public.topic_media_codes;



--
-- topic_domains
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.topic_domains (topic_domains_id,
                                  topics_id,
                                  domain,
                                  self_links)
SELECT topic_domains_id::BIGINT,
       topics_id::BIGINT,
       domain,
       self_links::BIGINT
FROM unsharded_public.topic_domains;

SELECT setval(
               pg_get_serial_sequence('public.topic_domains', 'topic_domains_id'),
               nextval(pg_get_serial_sequence('unsharded_public.topic_domains', 'topic_domains_id')),
               false
           );

TRUNCATE unsharded_public.topic_domains;
DROP TABLE unsharded_public.topic_domains;



--
-- topic_dead_links
--
-- Foreign key to stories.stories_id is missing so we can just copy it here
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.topic_dead_links_topics_id;
DROP INDEX public.topic_dead_links_stories_id;

INSERT INTO public.topic_dead_links (topic_dead_links_id,
                                     topics_id,
                                     stories_id,
                                     url)
SELECT topic_dead_links_id::BIGINT,
       topics_id::BIGINT,
       stories_id::BIGINT,
       url
FROM unsharded_public.topic_dead_links;

SELECT setval(
               pg_get_serial_sequence('public.topic_dead_links', 'topic_dead_links_id'),
               nextval(pg_get_serial_sequence('unsharded_public.topic_dead_links', 'topic_dead_links_id')),
               false
           );

-- Recreate indexes
CREATE INDEX topic_dead_links_topics_id ON topic_dead_links (topics_id);
CREATE INDEX topic_dead_links_stories_id ON topic_dead_links (stories_id);

TRUNCATE unsharded_public.topic_dead_links;
DROP TABLE unsharded_public.topic_dead_links;



--
-- topic_ignore_redirects
--

INSERT INTO public.topic_ignore_redirects (
    -- Primary key is not important
    url)
SELECT url::TEXT
FROM unsharded_public.topic_ignore_redirects;

TRUNCATE unsharded_public.topic_ignore_redirects;
DROP TABLE unsharded_public.topic_ignore_redirects;



--
-- snapshots
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.snapshots (snapshots_id,
                              topics_id,
                              snapshot_date,
                              start_date,
                              end_date,
                              note,
                              state,
                              message,
                              searchable,
                              bot_policy,
                              seed_queries)
SELECT snapshots_id::BIGINT,
       topics_id::BIGINT,
       snapshot_date,
       start_date,
       end_date,
       note,
       state,
       message,
       searchable,
       bot_policy::TEXT::public.bot_policy_type,
       seed_queries
FROM unsharded_public.snapshots;

SELECT setval(
               pg_get_serial_sequence('public.snapshots', 'snapshots_id'),
               nextval(pg_get_serial_sequence('unsharded_public.snapshots', 'snapshots_id')),
               false
           );

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.focal_sets
    DROP CONSTRAINT focal_sets_snapshots_id_fkey;
ALTER TABLE unsharded_public.snapshot_files
    DROP CONSTRAINT snapshot_files_snapshots_id_fkey;
ALTER TABLE unsharded_public.timespans
    -- Exists only on production
    DROP CONSTRAINT IF EXISTS controversy_dump_time_slices_controversy_dumps_id_fkey;
ALTER TABLE unsharded_public.timespans
    DROP CONSTRAINT IF EXISTS timespans_snapshots_id_fkey;
ALTER TABLE unsharded_public.timespans
    DROP CONSTRAINT timespans_archive_snapshots_id_fkey;
ALTER TABLE unsharded_snap.media
    -- Exists only on production
    DROP CONSTRAINT IF EXISTS media_controversy_dumps_id_fkey;
ALTER TABLE unsharded_snap.media
    DROP CONSTRAINT IF EXISTS media_snapshots_id_fkey;
ALTER TABLE unsharded_snap.media_tags_map
    -- Exists only on production
    DROP CONSTRAINT IF EXISTS media_tags_map_controversy_dumps_id_fkey;
ALTER TABLE unsharded_snap.media_tags_map
    DROP CONSTRAINT IF EXISTS media_tags_map_snapshots_id_fkey;
ALTER TABLE unsharded_snap.stories
    -- Exists only on production
    DROP CONSTRAINT IF EXISTS stories_controversy_dumps_id_fkey;
ALTER TABLE unsharded_snap.stories
    DROP CONSTRAINT IF EXISTS stories_snapshots_id_fkey;
ALTER TABLE unsharded_snap.stories_tags_map
    -- Exists only on production
    DROP CONSTRAINT IF EXISTS stories_tags_map_controversy_dumps_id_fkey;
ALTER TABLE unsharded_snap.stories_tags_map
    DROP CONSTRAINT IF EXISTS stories_tags_map_snapshots_id_fkey;
ALTER TABLE unsharded_snap.topic_links_cross_media
    -- Exists only on production
    DROP CONSTRAINT IF EXISTS controversy_links_cross_media_controversy_dumps_id_fkey;
ALTER TABLE unsharded_snap.topic_links_cross_media
    DROP CONSTRAINT topic_links_cross_media_snapshots_id_fkey;
ALTER TABLE unsharded_snap.topic_media_codes
    -- Exists only on production
    DROP CONSTRAINT IF EXISTS controversy_media_codes_controversy_dumps_id_fkey;
ALTER TABLE unsharded_snap.topic_media_codes
    -- Exists only on production
    DROP CONSTRAINT IF EXISTS topic_media_codes_snapshots_id_fkey;
ALTER TABLE unsharded_snap.topic_stories
    -- Exists only on production
    DROP CONSTRAINT IF EXISTS controversy_stories_controversy_dumps_id_fkey;
ALTER TABLE unsharded_snap.topic_stories
    DROP CONSTRAINT topic_stories_snapshots_id_fkey;
ALTER TABLE unsharded_snap.word2vec_models
    DROP CONSTRAINT word2vec_models_object_id_fkey;


TRUNCATE unsharded_public.snapshots;
DROP TABLE unsharded_public.snapshots;



--
-- focal_set_definitions
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.focal_set_definitions (focal_set_definitions_id,
                                          topics_id,
                                          name,
                                          description,
                                          focal_technique)
SELECT focal_set_definitions_id::BIGINT,
       topics_id::BIGINT,
       name,
       description,
       focal_technique::TEXT::public.focal_technique_type
FROM unsharded_public.focal_set_definitions;

SELECT setval(
               pg_get_serial_sequence('public.focal_set_definitions', 'focal_set_definitions_id'),
               nextval(pg_get_serial_sequence('unsharded_public.focal_set_definitions', 'focal_set_definitions_id')),
               false
           );

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.focus_definitions
    DROP CONSTRAINT focus_definitions_focal_set_definitions_id_fkey;

TRUNCATE unsharded_public.focal_set_definitions;
DROP TABLE unsharded_public.focal_set_definitions;



--
-- focus_definitions
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.focus_definitions (focus_definitions_id,
                                      topics_id,
                                      focal_set_definitions_id,
                                      name,
                                      description,
                                      arguments)
SELECT focus_definitions.focus_definitions_id::BIGINT,
       focal_set_definitions.topics_id::BIGINT,
       focus_definitions.focal_set_definitions_id::BIGINT,
       focus_definitions.name,
       focus_definitions.description,
       focus_definitions.arguments::JSONB
FROM unsharded_public.focus_definitions AS focus_definitions
         -- Join the sharded table that we have just copied
         INNER JOIN public.focal_set_definitions AS focal_set_definitions
                    ON focus_definitions.focal_set_definitions_id = focal_set_definitions.focal_set_definitions_id;

SELECT setval(
               pg_get_serial_sequence('public.focus_definitions', 'focus_definitions_id'),
               nextval(pg_get_serial_sequence('unsharded_public.focus_definitions', 'focus_definitions_id')),
               false
           );

TRUNCATE unsharded_public.focus_definitions;
DROP TABLE unsharded_public.focus_definitions;



--
-- focal_sets
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.focal_sets (focal_sets_id,
                               topics_id,
                               snapshots_id,
                               name,
                               description,
                               focal_technique)
SELECT focal_sets.focal_sets_id::BIGINT,
       snapshots.topics_id::BIGINT,
       focal_sets.snapshots_id::BIGINT,
       focal_sets.name,
       focal_sets.description,
       focal_sets.focal_technique::TEXT::public.focal_technique_type
FROM unsharded_public.focal_sets AS focal_sets
         -- Join the sharded table that we have just copied
         INNER JOIN public.snapshots AS snapshots
                    ON focal_sets.snapshots_id = snapshots.snapshots_id;

SELECT setval(
               pg_get_serial_sequence('public.focal_sets', 'focal_sets_id'),
               nextval(pg_get_serial_sequence('unsharded_public.focal_sets', 'focal_sets_id')),
               false
           );

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.foci
    DROP CONSTRAINT foci_focal_sets_id_fkey;

TRUNCATE unsharded_public.focal_sets;
DROP TABLE unsharded_public.focal_sets;



--
-- foci
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.foci (foci_id,
                         topics_id,
                         focal_sets_id,
                         name,
                         description,
                         arguments)
SELECT foci.foci_id::BIGINT,
       snapshots.topics_id::BIGINT,
       foci.focal_sets_id::BIGINT,
       foci.name,
       foci.description,
       foci.arguments::JSONB
FROM unsharded_public.foci AS foci
         -- Join the sharded table that we have just copied
         INNER JOIN public.focal_sets AS focal_sets
                    ON foci.focal_sets_id = focal_sets.focal_sets_id
    -- Join the sharded table that we have just copied
         INNER JOIN public.snapshots AS snapshots
                    ON focal_sets.snapshots_id = snapshots.snapshots_id;

SELECT setval(
               pg_get_serial_sequence('public.foci', 'foci_id'),
               nextval(pg_get_serial_sequence('unsharded_public.foci', 'foci_id')),
               false
           );

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.timespans
    DROP CONSTRAINT timespans_foci_id_fkey;

TRUNCATE unsharded_public.foci;
DROP TABLE unsharded_public.foci;



--
-- timespans
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.timespans_topics_id;
DROP INDEX public.timespans_topics_id_snapshots_id;

INSERT INTO public.timespans (timespans_id,
                              topics_id,
                              snapshots_id,
                              archive_snapshots_id,
                              foci_id,
                              start_date,
                              end_date,
                              period,
                              model_r2_mean,
                              model_r2_stddev,
                              model_num_media,
                              story_count,
                              story_link_count,
                              medium_count,
                              medium_link_count,
                              post_count,
                              tags_id)
SELECT timespans.timespans_id::BIGINT,
       snapshots.topics_id::BIGINT,
       timespans.snapshots_id::BIGINT,
       timespans.archive_snapshots_id::BIGINT,
       timespans.foci_id::BIGINT,
       timespans.start_date,
       timespans.end_date,
       timespans.period::TEXT::public.snap_period_type,
       timespans.model_r2_mean,
       timespans.model_r2_stddev,
       timespans.model_num_media::BIGINT,
       timespans.story_count::BIGINT,
       timespans.story_link_count::BIGINT,
       timespans.medium_count::BIGINT,
       timespans.medium_link_count::BIGINT,
       timespans.post_count::BIGINT,
       timespans.tags_id::BIGINT
FROM unsharded_public.timespans AS timespans
         -- Join the sharded table that we have just copied
         INNER JOIN public.snapshots AS snapshots
                    ON timespans.snapshots_id = snapshots.snapshots_id;

SELECT setval(
               pg_get_serial_sequence('public.timespans', 'timespans_id'),
               nextval(pg_get_serial_sequence('unsharded_public.timespans', 'timespans_id')),
               false
           );

-- Recreate indexes
CREATE INDEX timespans_topics_id ON public.timespans (topics_id);
CREATE INDEX timespans_topics_id_snapshots_id ON public.timespans (topics_id, snapshots_id);

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_snap.medium_link_counts
    -- Only on production
    DROP CONSTRAINT IF EXISTS medium_link_counts_controversy_dump_time_slices_id_fkey;
ALTER TABLE unsharded_snap.medium_link_counts
    DROP CONSTRAINT IF EXISTS medium_link_counts_timespans_id_fkey;
ALTER TABLE unsharded_snap.medium_links
    -- Only on production
    DROP CONSTRAINT IF EXISTS medium_links_controversy_dump_time_slices_id_fkey;
ALTER TABLE unsharded_snap.medium_links
    DROP CONSTRAINT IF EXISTS medium_links_timespans_id_fkey;
ALTER TABLE unsharded_snap.story_link_counts
    -- Only on production
    DROP CONSTRAINT IF EXISTS story_link_counts_controversy_dump_time_slices_id_fkey;
ALTER TABLE unsharded_snap.story_link_counts
    DROP CONSTRAINT IF EXISTS story_link_counts_timespans_id_fkey;
ALTER TABLE unsharded_snap.story_links
    -- Only in production
    DROP CONSTRAINT IF EXISTS story_links_controversy_dump_time_slices_id_fkey;
ALTER TABLE unsharded_snap.story_links
    DROP CONSTRAINT IF EXISTS story_links_timespans_id_fkey;
ALTER TABLE unsharded_public.timespan_files
    DROP CONSTRAINT timespan_files_timespans_id_fkey;
ALTER TABLE unsharded_public.timespan_maps
    DROP CONSTRAINT timespan_maps_timespans_id_fkey;
ALTER TABLE unsharded_snap.timespan_posts
    -- Only on production (misspelled?)
    DROP CONSTRAINT IF EXISTS timespan_tweets_timespans_id_fkey;
ALTER TABLE unsharded_snap.timespan_posts
    DROP CONSTRAINT timespan_posts_timespans_id_fkey;

TRUNCATE unsharded_public.timespans;
DROP TABLE unsharded_public.timespans;



--
-- timespan_maps
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.timespan_maps_topics_id;
DROP INDEX public.timespan_maps_topics_id_timespans_id;

INSERT INTO public.timespan_maps (timespan_maps_id,
                                  topics_id,
                                  timespans_id,
                                  options,
                                  content,
                                  url,
                                  format)
SELECT timespan_maps.timespan_maps_id::BIGINT,
       snapshots.topics_id::BIGINT,
       timespan_maps.timespans_id::BIGINT,
       timespan_maps.options,
       timespan_maps.content,
       timespan_maps.url,
       timespan_maps.format::TEXT
FROM unsharded_public.timespan_maps AS timespan_maps
         -- Join the sharded table that we have just copied
         INNER JOIN public.timespans AS timespans
                    ON timespan_maps.timespans_id = timespans.timespans_id
    -- Join the sharded table that we have just copied
         INNER JOIN public.snapshots AS snapshots
                    ON timespans.snapshots_id = snapshots.snapshots_id;

SELECT setval(
               pg_get_serial_sequence('public.timespan_maps', 'timespan_maps_id'),
               nextval(pg_get_serial_sequence('unsharded_public.timespan_maps', 'timespan_maps_id')),
               false
           );

-- Recreate indexes
CREATE INDEX timespan_maps_topics_id
    ON public.timespan_maps (topics_id);

CREATE INDEX timespan_maps_topics_id_timespans_id
    ON public.timespan_maps (topics_id, timespans_id);

TRUNCATE unsharded_public.timespan_maps;
DROP TABLE unsharded_public.timespan_maps;



--
-- timespan_files
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.timespan_files_topics_id;

INSERT INTO public.timespan_files (timespan_files_id,
                                   topics_id,
                                   timespans_id,
                                   name,
                                   url)
SELECT timespan_files.timespan_files_id::BIGINT,
       snapshots.topics_id::BIGINT,
       timespan_files.timespans_id::BIGINT,
       timespan_files.name,
       timespan_files.url
FROM unsharded_public.timespan_files AS timespan_files
         -- Join the sharded table that we have just copied
         INNER JOIN public.timespans AS timespans
                    ON timespan_files.timespans_id = timespans.timespans_id
    -- Join the sharded table that we have just copied
         INNER JOIN public.snapshots AS snapshots
                    ON timespans.snapshots_id = snapshots.snapshots_id;

SELECT setval(
               pg_get_serial_sequence('public.timespan_files', 'timespan_files_id'),
               nextval(pg_get_serial_sequence('unsharded_public.timespan_files', 'timespan_files_id')),
               false
           );

-- Recreate indexes
CREATE INDEX timespan_files_topics_id ON public.timespan_files (topics_id);

TRUNCATE unsharded_public.timespan_files;
DROP TABLE unsharded_public.timespan_files;



--
-- topic_spider_metrics
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX topic_spider_metrics_topics_id;
DROP INDEX topic_spider_metrics_processed_date;

INSERT INTO public.topic_spider_metrics (topic_spider_metrics_id,
                                         topics_id,
                                         iteration,
                                         links_processed,
                                         elapsed_time,
                                         processed_date)
SELECT topic_spider_metrics_id::BIGINT,
       topics_id::BIGINT,
       iteration::BIGINT,
       links_processed::BIGINT,
       elapsed_time::BIGINT,
       processed_date
FROM unsharded_public.topic_spider_metrics;

SELECT setval(
               pg_get_serial_sequence('public.topic_spider_metrics', 'topic_spider_metrics_id'),
               nextval(pg_get_serial_sequence('unsharded_public.topic_spider_metrics', 'topic_spider_metrics_id')),
               false
           );

-- Recreate indexes
CREATE INDEX topic_spider_metrics_topics_id
    ON public.topic_spider_metrics (topics_id);
CREATE INDEX topic_spider_metrics_processed_date
    ON public.topic_spider_metrics (processed_date);

TRUNCATE unsharded_public.topic_spider_metrics;
DROP TABLE unsharded_public.topic_spider_metrics;



--
-- snapshot_files
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.snapshot_files (snapshot_files_id,
                                   topics_id,
                                   snapshots_id,
                                   name,
                                   url)
SELECT snapshot_files.snapshot_files_id::BIGINT,
       snapshots.topics_id::BIGINT,
       snapshot_files.snapshots_id::BIGINT,
       snapshot_files.name,
       snapshot_files.url
FROM unsharded_public.snapshot_files AS snapshot_files
         -- Join the sharded table that we have just copied
         INNER JOIN public.snapshots AS snapshots
                    ON snapshot_files.snapshots_id = snapshots.snapshots_id;

SELECT setval(
               pg_get_serial_sequence('public.snapshot_files', 'snapshot_files_id'),
               nextval(pg_get_serial_sequence('unsharded_public.snapshot_files', 'snapshot_files_id')),
               false
           );

TRUNCATE unsharded_public.snapshot_files;
DROP TABLE unsharded_public.snapshot_files;



--
-- snap.topic_media_codes
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO snap.topic_media_codes (
    -- Primary key does not exist in the source table
    topics_id,
    snapshots_id,
    media_id,
    code_type,
    code)
SELECT topics_id::BIGINT,
       snapshots_id::BIGINT,
       media_id::BIGINT,
       code_type,
       code
FROM unsharded_snap.topic_media_codes;

TRUNCATE unsharded_snap.topic_media_codes;
DROP TABLE unsharded_snap.topic_media_codes;



--
-- snap.topic_media_codes
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX snap.snap_word2vec_models_topics_id;
DROP INDEX snap.snap_word2vec_models_topics_id_snapshots_id_creation_date;

INSERT INTO snap.word2vec_models (snap_word2vec_models_id,
                                  topics_id,
                                  snapshots_id,
                                  creation_date,
                                  raw_data)
SELECT word2vec_models.word2vec_models_id::BIGINT AS snap_word2vec_models_id,
       snapshots.topics_id::BIGINT,
       word2vec_models.object_id::BIGINT          AS snapshots_id,
       word2vec_models.creation_date,
       word2vec_models_data.raw_data
FROM unsharded_snap.word2vec_models AS word2vec_models
         -- Join the sharded table that we have just copied
         INNER JOIN public.snapshots AS snapshots
                    ON word2vec_models.object_id = snapshots.snapshots_id
         INNER JOIN unsharded_snap.word2vec_models_data AS word2vec_models_data
                    ON word2vec_models.word2vec_models_id = word2vec_models_data.object_id;

SELECT setval(
               pg_get_serial_sequence('snap.word2vec_models', 'snap_word2vec_models_id'),
               nextval(pg_get_serial_sequence('unsharded_snap.word2vec_models', 'word2vec_models_id')),
               false
           );

-- Recreate indexes
CREATE INDEX snap_word2vec_models_topics_id
    ON snap.word2vec_models (topics_id);
CREATE INDEX snap_word2vec_models_topics_id_snapshots_id_creation_date
    ON snap.word2vec_models (topics_id, snapshots_id, creation_date);

TRUNCATE unsharded_snap.word2vec_models_data;
DROP TABLE unsharded_snap.word2vec_models_data;
TRUNCATE unsharded_snap.word2vec_models;
DROP TABLE unsharded_snap.word2vec_models;



--
-- topic_permissions
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.topic_permissions (
    -- Primary key is not important
    topics_id,
    auth_users_id,
    permission)
SELECT topics_id::BIGINT,
       auth_users_id::BIGINT,
       permission::TEXT::public.topic_permission
FROM unsharded_public.topic_permissions;

TRUNCATE unsharded_public.topic_permissions;
DROP TABLE unsharded_public.topic_permissions;



--
-- topic_post_days
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.topic_post_days (topic_post_days_id,
                                    topics_id,
                                    topic_seed_queries_id,
                                    day,
                                    num_posts_stored,
                                    num_posts_fetched,
                                    posts_fetched)
SELECT topic_post_days.topic_post_days_id::BIGINT,
       topic_seed_queries.topics_id::BIGINT,
       topic_post_days.topic_seed_queries_id::BIGINT,
       topic_post_days.day,
       topic_post_days.num_posts_stored::BIGINT,
       topic_post_days.num_posts_fetched::BIGINT,
       topic_post_days.posts_fetched
FROM unsharded_public.topic_post_days AS topic_post_days
         -- Join the sharded table that we have just copied
         INNER JOIN public.topic_seed_queries AS topic_seed_queries
                    ON topic_post_days.topic_seed_queries_id = topic_seed_queries.topic_seed_queries_id;

SELECT setval(
               pg_get_serial_sequence('public.topic_post_days', 'topic_post_days_id'),
               nextval(pg_get_serial_sequence('unsharded_public.topic_post_days', 'topic_post_days_id')),
               false
           );


-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.topic_posts
    -- Only on production (misspelled?)
    DROP CONSTRAINT IF EXISTS topic_tweets_topic_tweet_days_id_fkey;
ALTER TABLE unsharded_public.topic_posts
    DROP CONSTRAINT IF EXISTS topic_posts_topic_post_days_id_fkey;

TRUNCATE unsharded_public.topic_post_days;
DROP TABLE unsharded_public.topic_post_days;



--
-- job_states
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.job_states_class_last_updated;

INSERT INTO public.job_states (job_states_id,
                               class,
                               state,
                               message,
                               last_updated,
                               args,
                               priority,
                               hostname,
                               process_id)
SELECT job_states_id::BIGINT,
       class::TEXT,
       state::TEXT,
       message::TEXT,
       last_updated,
       args::JSONB,
       priority,
       hostname,
       process_id::BIGINT
FROM unsharded_public.job_states;

SELECT setval(
               pg_get_serial_sequence('public.job_states', 'job_states_id'),
               nextval(pg_get_serial_sequence('unsharded_public.job_states', 'job_states_id')),
               false
           );

-- Recreate indexes
CREATE INDEX job_states_class_last_updated ON public.job_states (class, last_updated);

TRUNCATE unsharded_public.job_states;
DROP TABLE unsharded_public.job_states;



--
-- retweeter_scores
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.retweeter_scores (retweeter_scores_id,
                                     topics_id,
                                     group_a_id,
                                     group_b_id,
                                     name,
                                     state,
                                     message,
                                     num_partitions,
                                     match_type)
SELECT retweeter_scores_id::BIGINT,
       topics_id::BIGINT,
       group_a_id::BIGINT,
       group_b_id::BIGINT,
       name,
       state,
       message,
       num_partitions::BIGINT,
       match_type::TEXT::public.retweeter_scores_match_type
FROM unsharded_public.retweeter_scores;

SELECT setval(
               pg_get_serial_sequence('public.retweeter_scores', 'retweeter_scores_id'),
               nextval(pg_get_serial_sequence('unsharded_public.retweeter_scores', 'retweeter_scores_id')),
               false
           );

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.retweeter_groups
    DROP CONSTRAINT retweeter_groups_retweeter_scores_id_fkey;
ALTER TABLE unsharded_public.retweeter_groups_users_map
    DROP CONSTRAINT retweeter_groups_users_map_retweeter_scores_id_fkey;
ALTER TABLE unsharded_public.retweeter_media
    DROP CONSTRAINT retweeter_media_retweeter_scores_id_fkey;
ALTER TABLE unsharded_public.retweeter_partition_matrix
    DROP CONSTRAINT retweeter_partition_matrix_retweeter_scores_id_fkey;
ALTER TABLE unsharded_public.retweeter_stories
    DROP CONSTRAINT retweeter_stories_retweeter_scores_id_fkey;
ALTER TABLE unsharded_public.retweeters
    DROP CONSTRAINT retweeters_retweeter_scores_id_fkey;

TRUNCATE unsharded_public.retweeter_scores;
DROP TABLE unsharded_public.retweeter_scores;



--
-- retweeter_groups
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.retweeter_groups (retweeter_groups_id,
                                     topics_id,
                                     retweeter_scores_id,
                                     name)
SELECT retweeter_groups.retweeter_groups_id::BIGINT,
       retweeter_scores.topics_id::BIGINT,
       retweeter_groups.retweeter_scores_id::BIGINT,
       retweeter_groups.name
FROM unsharded_public.retweeter_groups AS retweeter_groups
         -- Join the sharded table that we have just copied
         INNER JOIN public.retweeter_scores AS retweeter_scores
                    ON retweeter_groups.retweeter_scores_id = retweeter_scores.retweeter_scores_id;

SELECT setval(
               pg_get_serial_sequence('public.retweeter_groups', 'retweeter_groups_id'),
               nextval(pg_get_serial_sequence('unsharded_public.retweeter_groups', 'retweeter_groups_id')),
               false
           );

-- Drop foreign keys that point to the table
ALTER TABLE unsharded_public.retweeter_groups_users_map
    -- Only in production
    DROP CONSTRAINT IF EXISTS retweeter_groups_users_map_retweeter_groups_id_fkey;
ALTER TABLE unsharded_public.retweeter_partition_matrix
    -- Only in production
    DROP CONSTRAINT IF EXISTS retweeter_partition_matrix_retweeter_groups_id_fkey;
ALTER TABLE unsharded_public.retweeter_partition_matrix
    -- Only in production
    DROP CONSTRAINT IF EXISTS retweeter_partition_matrix_retweeter_groups_id_fkey;
ALTER TABLE unsharded_public.retweeter_groups
    -- Not in production
    DROP CONSTRAINT IF EXISTS retweeter_groups_retweeter_scores_id_fkey;
ALTER TABLE unsharded_public.retweeters
    -- Not in production
    DROP CONSTRAINT IF EXISTS retweeters_retweeter_scores_id_fkey;

TRUNCATE unsharded_public.retweeter_groups;
DROP TABLE unsharded_public.retweeter_groups;



--
-- retweeters
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.retweeters (retweeters_id,
                               topics_id,
                               retweeter_scores_id,
                               twitter_user,
                               retweeted_user)
SELECT retweeters.retweeters_id::BIGINT,
       retweeter_scores.topics_id::BIGINT,
       retweeters.retweeter_scores_id::BIGINT,
       retweeters.twitter_user::TEXT,
       retweeters.retweeted_user::TEXT
FROM unsharded_public.retweeters AS retweeters
         -- Join the sharded table that we have just copied
         INNER JOIN public.retweeter_scores AS retweeter_scores
                    ON retweeters.retweeter_scores_id = retweeter_scores.retweeter_scores_id;

SELECT setval(
               pg_get_serial_sequence('public.retweeters', 'retweeters_id'),
               nextval(pg_get_serial_sequence('unsharded_public.retweeters', 'retweeters_id')),
               false
           );

TRUNCATE unsharded_public.retweeters;
DROP TABLE unsharded_public.retweeters;



--
-- retweeter_groups_users_map
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.retweeter_groups_users_map (
    -- Primary key does not exist in the source table
    topics_id,
    retweeter_groups_id,
    retweeter_scores_id,
    retweeted_user)
SELECT retweeter_scores.topics_id::BIGINT,
       retweeter_groups_users_map.retweeter_groups_id::BIGINT,
       retweeter_groups_users_map.retweeter_scores_id::BIGINT,
       retweeter_groups_users_map.retweeted_user::TEXT
FROM unsharded_public.retweeter_groups_users_map AS retweeter_groups_users_map
         -- Join the sharded table that we have just copied
         INNER JOIN public.retweeter_scores AS retweeter_scores
                    ON retweeter_groups_users_map.retweeter_scores_id = retweeter_scores.retweeter_scores_id;

TRUNCATE unsharded_public.retweeter_groups_users_map;
DROP TABLE unsharded_public.retweeter_groups_users_map;



--
-- retweeter_stories
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.retweeter_stories (
    -- Primary key is not important
    -- (and has a typo in the source table anyway)
    topics_id,
    retweeter_scores_id,
    stories_id,
    retweeted_user,
    share_count)
SELECT retweeter_scores.topics_id::BIGINT,
       retweeter_stories.retweeter_scores_id::BIGINT,
       retweeter_stories.stories_id::BIGINT,
       retweeter_stories.retweeted_user::TEXT,
       retweeter_stories.share_count::BIGINT
FROM unsharded_public.retweeter_stories AS retweeter_stories
         -- Join the sharded table that we have just copied
         INNER JOIN public.retweeter_scores AS retweeter_scores
                    ON retweeter_stories.retweeter_scores_id = retweeter_scores.retweeter_scores_id;

TRUNCATE unsharded_public.retweeter_stories;
DROP TABLE unsharded_public.retweeter_stories;



--
-- retweeter_media
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.retweeter_media (retweeter_media_id,
                                    topics_id,
                                    retweeter_scores_id,
                                    media_id,
                                    group_a_count,
                                    group_b_count,
                                    group_a_count_n,
                                    score,
                                    partition)
SELECT retweeter_media.retweeter_media_id::BIGINT,
       retweeter_scores.topics_id::BIGINT,
       retweeter_media.retweeter_scores_id::BIGINT,
       retweeter_media.media_id::BIGINT,
       retweeter_media.group_a_count::BIGINT,
       retweeter_media.group_b_count::BIGINT,
       retweeter_media.group_a_count_n,
       retweeter_media.score,
       retweeter_media.partition::BIGINT
FROM unsharded_public.retweeter_media AS retweeter_media
         -- Join the sharded table that we have just copied
         INNER JOIN public.retweeter_scores AS retweeter_scores
                    ON retweeter_media.retweeter_scores_id = retweeter_scores.retweeter_scores_id;

SELECT setval(
               pg_get_serial_sequence('public.retweeter_media', 'retweeter_media_id'),
               nextval(pg_get_serial_sequence('unsharded_public.retweeter_media', 'retweeter_media_id')),
               false
           );

TRUNCATE unsharded_public.retweeter_media;
DROP TABLE unsharded_public.retweeter_media;



--
-- retweeter_partition_matrix
--

-- Don't temporarily drop any indexes as the table is too small

INSERT INTO public.retweeter_partition_matrix (retweeter_partition_matrix_id,
                                               topics_id,
                                               retweeter_scores_id,
                                               retweeter_groups_id,
                                               group_name,
                                               share_count,
                                               group_proportion,
                                               partition)
SELECT retweeter_partition_matrix.retweeter_partition_matrix_id,
       retweeter_scores.topics_id::BIGINT,
       retweeter_partition_matrix.retweeter_scores_id,
       retweeter_partition_matrix.retweeter_groups_id,
       retweeter_partition_matrix.group_name,
       retweeter_partition_matrix.share_count,
       retweeter_partition_matrix.group_proportion,
       retweeter_partition_matrix.partition
FROM unsharded_public.retweeter_partition_matrix AS retweeter_partition_matrix
         -- Join the sharded table that we have just copied
         INNER JOIN public.retweeter_scores AS retweeter_scores
                    ON retweeter_partition_matrix.retweeter_scores_id = retweeter_scores.retweeter_scores_id;

SELECT setval(
               pg_get_serial_sequence('public.retweeter_partition_matrix', 'retweeter_partition_matrix_id'),
               nextval(pg_get_serial_sequence('unsharded_public.retweeter_partition_matrix',
                                              'retweeter_partition_matrix_id')),
               false
           );

TRUNCATE unsharded_public.retweeter_partition_matrix;
DROP TABLE unsharded_public.retweeter_partition_matrix;



--
-- celery_groups
--

-- Table's contents will be recreated by Celery
TRUNCATE unsharded_public.celery_groups;
DROP TABLE unsharded_public.celery_groups;



--
-- celery_tasks
--

-- Table's contents will be recreated by Celery
TRUNCATE unsharded_public.celery_tasks;
DROP TABLE unsharded_public.celery_tasks;


--
-- cache.s3_raw_downloads_cache
--

-- Cache table can be just purged
TRUNCATE unsharded_cache.s3_raw_downloads_cache;
DROP TABLE unsharded_cache.s3_raw_downloads_cache;



--
-- cache.extractor_results_cache
--

-- Cache table can be just purged
TRUNCATE unsharded_cache.extractor_results_cache;
DROP TABLE unsharded_cache.extractor_results_cache;


--
-- domain_web_requests
--

-- Nothing worth preserving in this table too
TRUNCATE unsharded_public.domain_web_requests;
DROP TABLE unsharded_public.domain_web_requests;



--
-- MOVE PUBLICLY USED FUNCTIONS
--


--
-- week_start_date()
--

-- Old function is still used in story_sentences_p for indexing


--
-- half_md5()
--

-- Old function is still used in story_sentences_p for indexing


--
-- media_has_active_syndicated_feeds()
--

DROP FUNCTION unsharded_public.media_has_active_syndicated_feeds(INT);



--
-- media_rescraping_add_initial_state_trigger()
--
DROP FUNCTION unsharded_public.media_rescraping_add_initial_state_trigger();



--
-- feed_is_stale()
--

DROP FUNCTION unsharded_public.feed_is_stale(INT);



--
-- pop_queued_download()
--

DROP FUNCTION unsharded_public.pop_queued_download();



--
-- get_normalized_title()
--

DROP FUNCTION unsharded_public.get_normalized_title(TEXT, INT);



--
-- insert_platform_source_pair()
--

DROP FUNCTION unsharded_public.insert_platform_source_pair(TEXT, TEXT);



--
-- generate_api_key()
--

-- Old function is still used in story_sentences_p for indexing


--
-- story_is_english_and_has_sentences()
--

DROP FUNCTION unsharded_public.story_is_english_and_has_sentences(INT);



--
-- update_feeds_from_yesterday()
--

DROP FUNCTION unsharded_public.update_feeds_from_yesterday();



--
-- rescraping_changes()
--

DROP FUNCTION unsharded_public.rescraping_changes();


--
-- cache.purge_object_caches()
--

DROP FUNCTION unsharded_cache.purge_object_caches();



--
-- get_domain_web_requests_lock()
--
DROP FUNCTION unsharded_public.get_domain_web_requests_lock(TEXT, FLOAT);



--
-- DROP UNUSED FUNCTIONS
--

DROP FUNCTION unsharded_public.table_exists(VARCHAR);

DROP FUNCTION unsharded_public.partition_name(TEXT, BIGINT, BIGINT);

DROP FUNCTION unsharded_public.partition_by_stories_id_chunk_size();

DROP FUNCTION unsharded_public.partition_by_stories_id_partition_name(TEXT, BIGINT);

DROP FUNCTION unsharded_public.partition_by_stories_id_create_partitions(TEXT);

DROP FUNCTION unsharded_public.partition_by_downloads_id_chunk_size();

DROP FUNCTION unsharded_public.partition_by_downloads_id_partition_name(TEXT, BIGINT);

DROP FUNCTION unsharded_public.partition_by_downloads_id_create_partitions(TEXT);

DROP FUNCTION unsharded_public.downloads_create_subpartitions(TEXT);

DROP FUNCTION unsharded_public.downloads_success_content_create_partitions();

DROP FUNCTION unsharded_public.downloads_success_feed_create_partitions();

DROP FUNCTION unsharded_public.feeds_stories_map_create_partitions();

DROP FUNCTION unsharded_public.stories_tags_map_create_partitions();

DROP FUNCTION unsharded_public.download_texts_create_partitions();

DROP FUNCTION unsharded_public.story_sentences_create_partitions();

DROP FUNCTION unsharded_public.auth_user_limits_weekly_usage(CITEXT);

DROP FUNCTION unsharded_public.create_missing_partitions();



--
-- DROP UNUSED TRIGGERS
--

DROP TRIGGER stories_tags_map_p_upsert_trigger ON unsharded_public.stories_tags_map_p;
DROP FUNCTION unsharded_public.stories_tags_map_p_upsert_trigger();

DROP TRIGGER story_sentences_p_insert_trigger ON unsharded_public.story_sentences_p;
DROP FUNCTION unsharded_public.story_sentences_p_insert_trigger();

-- New INSERTs will happen only to the sharded table
DROP TRIGGER topic_stories_insert_live_story ON unsharded_public.topic_stories;
DROP FUNCTION unsharded_public.insert_live_story();

DROP TRIGGER stories_update_live_story ON unsharded_public.stories;
DROP FUNCTION unsharded_public.update_live_story();

-- Table doesn't exist anymore so no need to DROP the trigger
-- DROP TRIGGER auth_user_api_keys_add_non_ip_limited_api_key ON unsharded_public.auth_users;
DROP FUNCTION unsharded_public.auth_user_api_keys_add_non_ip_limited_api_key();

-- Table doesn't exist anymore so no need to DROP the trigger
-- DROP TRIGGER auth_users_set_default_limits ON unsharded_public.auth_users;
DROP FUNCTION unsharded_public.auth_users_set_default_limits();

DROP FUNCTION unsharded_cache.update_cache_db_row_last_updated();

DROP TRIGGER downloads_error_test_referenced_download_trigger ON unsharded_public.downloads_error;
DROP TRIGGER downloads_feed_error_test_referenced_download_trigger ON unsharded_public.downloads_feed_error;
DROP TRIGGER downloads_fetching_test_referenced_download_trigger ON unsharded_public.downloads_fetching;
DROP TRIGGER downloads_pending_test_referenced_download_trigger ON unsharded_public.downloads_pending;

-- Table is gone so no need to drop the trigger
-- DROP TRIGGER raw_downloads_test_referenced_download_trigger ON unsharded_public.raw_downloads;

DO
$$
    DECLARE

        tables CURSOR FOR
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'unsharded_public'
              AND (
                        tablename LIKE 'downloads_success_content_%' OR
                        tablename LIKE 'downloads_success_feed_%' OR
                        tablename LIKE 'download_texts_%'
                )

            ORDER BY tablename;

    BEGIN
        FOR table_record IN tables
            LOOP

                EXECUTE '
            DROP TRIGGER ' || table_record.tablename || '_test_referenced_download_trigger
                ON unsharded_public.' || table_record.tablename || '
        ';

            END LOOP;
    END
$$;

DROP FUNCTION unsharded_public.test_referenced_download_trigger();

DROP TRIGGER feeds_stories_map_p_insert_trigger ON unsharded_public.feeds_stories_map_p;
DROP FUNCTION unsharded_public.feeds_stories_map_p_insert_trigger();

-- No more INSERTs will be happening to the unsharded table; update the
-- normalized title hash only on UPDATEs
DROP TRIGGER stories_add_normalized_title ON unsharded_public.stories;
CREATE TRIGGER stories_add_normalized_title
    BEFORE UPDATE
    ON unsharded_public.stories
    FOR EACH ROW
EXECUTE PROCEDURE unsharded_public.add_normalized_title_hash();

-- Update the insert_solr_import_story() triggers to not be fired on INSERTs as
-- those won't be happening anymore; the workflow moving the rows from
-- unsharded table to the sharded one will skip the triggers or run the
-- appropriate actions manually
DROP TRIGGER stories_insert_solr_import_story ON unsharded_public.stories;
DROP TRIGGER stories_tags_map_p_insert_solr_import_story ON unsharded_public.stories_tags_map_p;
DROP TRIGGER ps_insert_solr_import_story ON unsharded_public.processed_stories;
CREATE TRIGGER stories_insert_solr_import_story
    AFTER UPDATE OR DELETE
    ON unsharded_public.stories
    FOR EACH ROW
EXECUTE PROCEDURE unsharded_public.insert_solr_import_story();
CREATE TRIGGER stories_tags_map_p_insert_solr_import_story
    BEFORE UPDATE OR DELETE
    ON unsharded_public.stories_tags_map_p
    FOR EACH ROW
EXECUTE PROCEDURE unsharded_public.insert_solr_import_story();
CREATE TRIGGER ps_insert_solr_import_story
    AFTER UPDATE OR DELETE
    ON unsharded_public.processed_stories
    FOR EACH ROW
EXECUTE PROCEDURE unsharded_public.insert_solr_import_story();



--
-- MOVE EMPTY SOON-TO-BE-HUGE SHARDED TABLES TO THEIR OWN SCHEMA
--


--
-- auth_user_request_daily_counts
--

ALTER TABLE public.auth_user_request_daily_counts
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.auth_user_request_daily_counts',
                                      'auth_user_request_daily_counts_id'),
               nextval(pg_get_serial_sequence('unsharded_public.auth_user_request_daily_counts',
                                              'auth_user_request_daily_counts_id')),
               false
           );

CREATE VIEW public.auth_user_request_daily_counts AS
SELECT auth_user_request_daily_counts_id::BIGINT,
       email,
       day,
       requests_count::BIGINT,
       requested_items_count::BIGINT
FROM unsharded_public.auth_user_request_daily_counts

UNION

SELECT auth_user_request_daily_counts_id,
       email,
       day,
       requests_count,
       requested_items_count
FROM sharded_public.auth_user_request_daily_counts
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.auth_user_request_daily_counts
    ALTER COLUMN auth_user_request_daily_counts_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.auth_user_request_daily_counts',
                                                   'auth_user_request_daily_counts_id'));

CREATE OR REPLACE FUNCTION public.auth_user_request_daily_counts_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.auth_user_request_daily_counts SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER auth_user_request_daily_counts_insert
    INSTEAD OF INSERT
    ON public.auth_user_request_daily_counts
    FOR EACH ROW
EXECUTE PROCEDURE public.auth_user_request_daily_counts_insert();



--
-- media_stats
--

ALTER TABLE public.media_stats
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.media_stats', 'media_stats_id'),
               nextval(pg_get_serial_sequence('unsharded_public.media_stats', 'media_stats_id')),
               false
           );

CREATE VIEW public.media_stats AS
SELECT media_stats_id::BIGINT,
       media_id::BIGINT,
       num_stories::BIGINT,
       num_sentences::BIGINT,
       stat_date
FROM unsharded_public.media_stats

UNION

SELECT media_stats_id,
       media_id,
       num_stories,
       num_sentences,
       stat_date
FROM sharded_public.media_stats
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.media_stats
    ALTER COLUMN media_stats_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.media_stats', 'media_stats_id'));

CREATE OR REPLACE FUNCTION public.media_stats_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.media_stats SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER media_stats_insert
    INSTEAD OF INSERT
    ON public.media_stats
    FOR EACH ROW
EXECUTE PROCEDURE public.media_stats_insert();



--
-- media_coverage_gaps
--

ALTER TABLE public.media_coverage_gaps
    SET SCHEMA sharded_public;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW public.media_coverage_gaps AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS media_coverage_gaps_id,
    media_id::BIGINT,
    stat_week,
    num_stories,
    expected_stories,
    num_sentences,
    expected_sentences
FROM unsharded_public.media_coverage_gaps

UNION

SELECT media_coverage_gaps_id,
       media_id,
       stat_week,
       num_stories,
       expected_stories,
       num_sentences,
       expected_sentences
FROM sharded_public.media_coverage_gaps
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.media_coverage_gaps
    ALTER COLUMN media_coverage_gaps_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.media_coverage_gaps', 'media_coverage_gaps_id'));

CREATE OR REPLACE FUNCTION public.media_coverage_gaps_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.media_coverage_gaps SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER media_coverage_gaps_insert
    INSTEAD OF INSERT
    ON public.media_coverage_gaps
    FOR EACH ROW
EXECUTE PROCEDURE public.media_coverage_gaps_insert();



--
-- stories
--

ALTER TABLE public.stories
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.stories', 'stories_id'),
               nextval(pg_get_serial_sequence('unsharded_public.stories', 'stories_id')),
               false
           );

CREATE VIEW public.stories AS
SELECT stories_id::BIGINT,
       media_id::BIGINT,
       url::TEXT,
       guid::TEXT,
       title,
       normalized_title_hash,
       description,
       publish_date,
       collect_date,
       full_text_rss,
       language
FROM unsharded_public.stories

UNION

SELECT stories_id,
       media_id,
       url,
       guid,
       title,
       normalized_title_hash,
       description,
       publish_date,
       collect_date,
       full_text_rss,
       language
FROM sharded_public.stories
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.stories
    ALTER COLUMN stories_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.stories', 'stories_id'));

CREATE OR REPLACE FUNCTION public.stories_insert() RETURNS trigger AS
$$
BEGIN

    -- Do the same as add_normalized_title_hash() would on INSERTs; skip doing it on
    -- UPDATEs as the title hashes will be updated when moving rows from unsharded
    -- table to the sharded one
    SELECT INTO NEW.normalized_title_hash MD5(get_normalized_title(NEW.title, NEW.media_id))::uuid;

    -- Set default values (not supported by updatable views)
    IF NEW.collect_date IS NULL THEN
        SELECT NOW() INTO NEW.collect_date;
    END IF;
    IF NEW.full_text_rss IS NULL THEN
        SELECT 'f' INTO NEW.full_text_rss;
    END IF;

    -- Insert only into the sharded table
    INSERT INTO sharded_public.stories SELECT NEW.*;
    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER stories_insert
    INSTEAD OF INSERT
    ON public.stories
    FOR EACH ROW
EXECUTE PROCEDURE public.stories_insert();



--
-- stories_ap_syndicated
--

ALTER TABLE public.stories_ap_syndicated
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.stories_ap_syndicated', 'stories_ap_syndicated_id'),
               nextval(pg_get_serial_sequence('unsharded_public.stories_ap_syndicated', 'stories_ap_syndicated_id')),
               false
           );

CREATE VIEW public.stories_ap_syndicated AS
SELECT stories_ap_syndicated_id::BIGINT,
       stories_id::BIGINT,
       ap_syndicated
FROM unsharded_public.stories_ap_syndicated

UNION

SELECT stories_ap_syndicated_id,
       stories_id,
       ap_syndicated
FROM sharded_public.stories_ap_syndicated
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.stories_ap_syndicated
    ALTER COLUMN stories_ap_syndicated_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.stories_ap_syndicated', 'stories_ap_syndicated_id'));

CREATE OR REPLACE FUNCTION public.stories_ap_syndicated_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.stories_ap_syndicated SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER stories_ap_syndicated_insert
    INSTEAD OF INSERT
    ON public.stories_ap_syndicated
    FOR EACH ROW
EXECUTE PROCEDURE public.stories_ap_syndicated_insert();



--
-- story_urls
--

ALTER TABLE public.story_urls
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.story_urls', 'story_urls_id'),
               nextval(pg_get_serial_sequence('unsharded_public.story_urls', 'story_urls_id')),
               false
           );

CREATE VIEW public.story_urls AS
SELECT story_urls_id::BIGINT,
       stories_id::BIGINT,
       url::TEXT
FROM unsharded_public.story_urls

UNION

SELECT story_urls_id,
       stories_id,
       url
FROM sharded_public.story_urls
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.story_urls
    ALTER COLUMN story_urls_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.story_urls', 'story_urls_id'));

CREATE OR REPLACE FUNCTION public.story_urls_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.story_urls SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER story_urls_insert
    INSTEAD OF INSERT
    ON public.story_urls
    FOR EACH ROW
EXECUTE PROCEDURE public.story_urls_insert();



--
-- feeds_stories_map
--

ALTER TABLE public.feeds_stories_map
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.feeds_stories_map', 'feeds_stories_map_id'),
           -- Read max. primary key value from the partitioned table, not the view
               nextval(pg_get_serial_sequence('unsharded_public.feeds_stories_map_p', 'feeds_stories_map_p_id')),
               false
           );

CREATE VIEW public.feeds_stories_map AS
SELECT feeds_stories_map_p_id AS feeds_stories_map_id,
       feeds_id::BIGINT,
       stories_id::BIGINT
       -- Read partitioned table directly and not the view
FROM unsharded_public.feeds_stories_map_p

UNION

SELECT feeds_stories_map_id,
       feeds_id,
       stories_id
FROM sharded_public.feeds_stories_map
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.feeds_stories_map
    ALTER COLUMN feeds_stories_map_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.feeds_stories_map', 'feeds_stories_map_id'));

CREATE OR REPLACE FUNCTION public.feeds_stories_map_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.feeds_stories_map SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER feeds_stories_map_insert
    INSTEAD OF INSERT
    ON public.feeds_stories_map
    FOR EACH ROW
EXECUTE PROCEDURE public.feeds_stories_map_insert();



--
-- stories_tags_map
--

ALTER TABLE public.stories_tags_map
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.stories_tags_map', 'stories_tags_map_id'),
           -- Read max. primary key value from the partitioned table, not the view
               nextval(pg_get_serial_sequence('unsharded_public.stories_tags_map_p', 'stories_tags_map_p_id')),
               false
           );

CREATE VIEW public.stories_tags_map AS
SELECT stories_tags_map_p_id AS stories_tags_map_id,
       stories_id::BIGINT,
       tags_id::BIGINT
       -- Read partitioned table directly and not the view
FROM unsharded_public.stories_tags_map_p

UNION

SELECT stories_tags_map_id,
       stories_id,
       tags_id
FROM sharded_public.stories_tags_map
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.stories_tags_map
    ALTER COLUMN stories_tags_map_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.stories_tags_map', 'stories_tags_map_id'));

CREATE OR REPLACE FUNCTION public.stories_tags_map_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.stories_tags_map SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER stories_tags_map_insert
    INSTEAD OF INSERT
    ON public.stories_tags_map
    FOR EACH ROW
EXECUTE PROCEDURE public.stories_tags_map_insert();



--
-- story_sentences
--

ALTER TABLE public.story_sentences
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.story_sentences', 'story_sentences_id'),
           -- Read max. primary key value from the partitioned table, not the view
               nextval(pg_get_serial_sequence('unsharded_public.story_sentences_p', 'story_sentences_p_id')),
               false
           );

CREATE VIEW public.story_sentences AS
SELECT story_sentences_p_id AS story_sentences_id,
       stories_id::BIGINT,
       sentence_number,
       sentence,
       media_id::BIGINT,
       publish_date,
       language,
       is_dup
       -- Read partitioned table directly and not the view
FROM unsharded_public.story_sentences_p

UNION

SELECT story_sentences_id,
       stories_id,
       sentence_number,
       sentence,
       media_id,
       publish_date,
       language,
       is_dup
FROM sharded_public.story_sentences
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.story_sentences
    ALTER COLUMN story_sentences_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.story_sentences', 'story_sentences_id'));

CREATE OR REPLACE FUNCTION public.story_sentences_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.story_sentences SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER story_sentences_insert
    INSTEAD OF INSERT
    ON public.story_sentences
    FOR EACH ROW
EXECUTE PROCEDURE public.story_sentences_insert();



--
-- solr_import_stories
--

ALTER TABLE public.solr_import_stories
    SET SCHEMA sharded_public;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW public.solr_import_stories AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS solr_import_stories_id,
    stories_id::BIGINT
FROM unsharded_public.solr_import_stories

UNION

SELECT solr_import_stories_id,
       stories_id
FROM sharded_public.solr_import_stories
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.solr_import_stories
    ALTER COLUMN solr_import_stories_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.solr_import_stories', 'solr_import_stories_id'));

CREATE OR REPLACE FUNCTION public.solr_import_stories_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.solr_import_stories SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER solr_import_stories_insert
    INSTEAD OF INSERT
    ON public.solr_import_stories
    FOR EACH ROW
EXECUTE PROCEDURE public.solr_import_stories_insert();



--
-- solr_imported_stories
--

ALTER TABLE public.solr_imported_stories
    SET SCHEMA sharded_public;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW public.solr_imported_stories AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS solr_imported_stories_id,
    stories_id::BIGINT,
    import_date
FROM unsharded_public.solr_imported_stories

UNION

SELECT solr_imported_stories_id,
       stories_id,
       import_date
FROM sharded_public.solr_imported_stories
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.solr_imported_stories
    ALTER COLUMN solr_imported_stories_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.solr_imported_stories', 'solr_imported_stories_id'));

CREATE OR REPLACE FUNCTION public.solr_imported_stories_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.solr_imported_stories SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER solr_imported_stories_insert
    INSTEAD OF INSERT
    ON public.solr_imported_stories
    FOR EACH ROW
EXECUTE PROCEDURE public.solr_imported_stories_insert();



--
-- topic_merged_stories_map
--

ALTER TABLE public.topic_merged_stories_map
    SET SCHEMA sharded_public;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW public.topic_merged_stories_map AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS topic_merged_stories_map_id,
    source_stories_id::BIGINT,
    target_stories_id::BIGINT
FROM unsharded_public.topic_merged_stories_map

UNION

SELECT topic_merged_stories_map_id,
       source_stories_id,
       target_stories_id
FROM sharded_public.topic_merged_stories_map
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.topic_merged_stories_map
    ALTER COLUMN topic_merged_stories_map_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.topic_merged_stories_map',
                                                   'topic_merged_stories_map_id'));

CREATE OR REPLACE FUNCTION public.topic_merged_stories_map_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.topic_merged_stories_map SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER topic_merged_stories_map_insert
    INSTEAD OF INSERT
    ON public.topic_merged_stories_map
    FOR EACH ROW
EXECUTE PROCEDURE public.topic_merged_stories_map_insert();



--
-- story_statistics
--

ALTER TABLE public.story_statistics
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.story_statistics', 'story_statistics_id'),
               nextval(pg_get_serial_sequence('unsharded_public.story_statistics', 'story_statistics_id')),
               false
           );

CREATE VIEW public.story_statistics AS
SELECT story_statistics_id::BIGINT,
       stories_id::BIGINT,
       facebook_share_count::BIGINT,
       facebook_comment_count::BIGINT,
       facebook_reaction_count::BIGINT,
       facebook_api_collect_date,
       facebook_api_error
FROM unsharded_public.story_statistics

UNION

SELECT story_statistics_id,
       stories_id,
       facebook_share_count,
       facebook_comment_count,
       facebook_reaction_count,
       facebook_api_collect_date,
       facebook_api_error
FROM sharded_public.story_statistics
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.story_statistics
    ALTER COLUMN story_statistics_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.story_statistics', 'story_statistics_id'));

CREATE OR REPLACE FUNCTION public.story_statistics_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.story_statistics SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER story_statistics_insert
    INSTEAD OF INSERT
    ON public.story_statistics
    FOR EACH ROW
EXECUTE PROCEDURE public.story_statistics_insert();



--
-- processed_stories
--

ALTER TABLE public.processed_stories
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.processed_stories', 'processed_stories_id'),
               nextval(pg_get_serial_sequence('unsharded_public.processed_stories', 'processed_stories_id')),
               false
           );

CREATE VIEW public.processed_stories AS
SELECT processed_stories_id::BIGINT,
       stories_id::BIGINT
FROM unsharded_public.processed_stories

UNION

SELECT processed_stories_id,
       stories_id
FROM sharded_public.processed_stories
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.processed_stories
    ALTER COLUMN processed_stories_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.processed_stories', 'processed_stories_id'));

CREATE OR REPLACE FUNCTION public.processed_stories_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.processed_stories SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER processed_stories_insert
    INSTEAD OF INSERT
    ON public.processed_stories
    FOR EACH ROW
EXECUTE PROCEDURE public.processed_stories_insert();



--
-- scraped_stories
--

ALTER TABLE public.scraped_stories
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.scraped_stories', 'scraped_stories_id'),
               nextval(pg_get_serial_sequence('unsharded_public.scraped_stories', 'scraped_stories_id')),
               false
           );

CREATE VIEW public.scraped_stories AS
SELECT scraped_stories_id::BIGINT,
       stories_id::BIGINT,
       import_module
FROM unsharded_public.scraped_stories

UNION

SELECT scraped_stories_id,
       stories_id,
       import_module
FROM sharded_public.scraped_stories
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.scraped_stories
    ALTER COLUMN scraped_stories_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.scraped_stories', 'scraped_stories_id'));

CREATE OR REPLACE FUNCTION public.scraped_stories_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.scraped_stories SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER scraped_stories_insert
    INSTEAD OF INSERT
    ON public.scraped_stories
    FOR EACH ROW
EXECUTE PROCEDURE public.scraped_stories_insert();



--
-- story_enclosures
--

ALTER TABLE public.story_enclosures
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.story_enclosures', 'story_enclosures_id'),
               nextval(pg_get_serial_sequence('unsharded_public.story_enclosures', 'story_enclosures_id')),
               false
           );

CREATE VIEW public.story_enclosures AS
SELECT story_enclosures_id::BIGINT,
       stories_id::BIGINT,
       url,
       mime_type,
       length
FROM unsharded_public.story_enclosures

UNION

SELECT story_enclosures_id,
       stories_id,
       url,
       mime_type,
       length
FROM sharded_public.story_enclosures
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.story_enclosures
    ALTER COLUMN story_enclosures_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.story_enclosures', 'story_enclosures_id'));

CREATE OR REPLACE FUNCTION public.story_enclosures_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.story_enclosures SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER story_enclosures_insert
    INSTEAD OF INSERT
    ON public.story_enclosures
    FOR EACH ROW
EXECUTE PROCEDURE public.story_enclosures_insert();



--
-- downloads
--

ALTER TABLE public.downloads
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.downloads', 'downloads_id'),
               nextval(pg_get_serial_sequence('unsharded_public.downloads', 'downloads_id')),
               false
           );

CREATE VIEW public.downloads AS
SELECT downloads_id,
       feeds_id::BIGINT,
       stories_id::BIGINT,
       parent,
       url,
       host,
       download_time,
       type::TEXT::public.download_type,
       state::TEXT::public.download_state,
       path,
       error_message,
       priority,
       sequence,
       extracted
FROM unsharded_public.downloads

UNION

SELECT downloads_id,
       feeds_id,
       stories_id,
       parent,
       url,
       host,
       download_time,
       type,
       state,
       path,
       error_message,
       priority,
       sequence,
       extracted
FROM sharded_public.downloads
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.downloads
    ALTER COLUMN downloads_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.downloads', 'downloads_id'));

CREATE OR REPLACE FUNCTION public.downloads_insert() RETURNS trigger AS
$$
BEGIN

    -- Set default values (not supported by updatable views)
    IF NEW.download_time IS NULL THEN
        SELECT NOW() INTO NEW.download_time;
    END IF;
    IF NEW.extracted IS NULL THEN
        SELECT 'f' INTO NEW.extracted;
    END IF;

    -- Insert only into the sharded table
    INSERT INTO sharded_public.downloads SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER downloads_insert
    INSTEAD OF INSERT
    ON public.downloads
    FOR EACH ROW
EXECUTE PROCEDURE public.downloads_insert();



--
-- download_texts
--

ALTER TABLE public.download_texts
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.download_texts', 'download_texts_id'),
               nextval(pg_get_serial_sequence('unsharded_public.download_texts', 'download_texts_id')),
               false
           );

CREATE VIEW public.download_texts AS
SELECT download_texts_id,
       downloads_id,
       download_text,
       download_text_length
FROM unsharded_public.download_texts

UNION

SELECT download_texts_id,
       downloads_id,
       download_text,
       download_text_length
FROM sharded_public.download_texts
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.download_texts
    ALTER COLUMN download_texts_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.download_texts', 'download_texts_id'));

CREATE OR REPLACE FUNCTION public.download_texts_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.download_texts SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER download_texts_insert
    INSTEAD OF INSERT
    ON public.download_texts
    FOR EACH ROW
EXECUTE PROCEDURE public.download_texts_insert();



--
-- topic_stories
--

ALTER TABLE public.topic_stories
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.topic_stories', 'topic_stories_id'),
               nextval(pg_get_serial_sequence('unsharded_public.topic_stories', 'topic_stories_id')),
               false
           );

CREATE VIEW public.topic_stories AS
SELECT topic_stories_id::BIGINT,
       topics_id::BIGINT,
       stories_id::BIGINT,
       link_mined,
       iteration::BIGINT,
       link_weight,
       redirect_url,
       valid_foreign_rss_story,
       link_mine_error
FROM unsharded_public.topic_stories

UNION

SELECT topic_stories_id,
       topics_id,
       stories_id,
       link_mined,
       iteration,
       link_weight,
       redirect_url,
       valid_foreign_rss_story,
       link_mine_error
FROM sharded_public.topic_stories
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.topic_stories
    ALTER COLUMN topic_stories_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.topic_stories', 'topic_stories_id'));

CREATE OR REPLACE FUNCTION public.topic_stories_insert() RETURNS trigger AS
$$
BEGIN

    -- Set default values (not supported by updatable views)
    IF NEW.link_mined IS NULL THEN
        SELECT 'f' INTO NEW.link_mined;
    END IF;
    IF NEW.iteration IS NULL THEN
        SELECT 0 INTO NEW.iteration;
    END IF;
    IF NEW.valid_foreign_rss_story IS NULL THEN
        SELECT 'f' INTO NEW.valid_foreign_rss_story;
    END IF;

    -- Insert only into the sharded table
    INSERT INTO sharded_public.topic_stories SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER topic_stories_insert
    INSTEAD OF INSERT
    ON public.topic_stories
    FOR EACH ROW
EXECUTE PROCEDURE public.topic_stories_insert();



--
-- topic_links
--

ALTER TABLE public.topic_links
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.topic_links', 'topic_links_id'),
               nextval(pg_get_serial_sequence('unsharded_public.topic_links', 'topic_links_id')),
               false
           );

CREATE VIEW public.topic_links AS
SELECT topic_links_id::BIGINT,
       topics_id::BIGINT,
       stories_id::BIGINT,
       url,
       redirect_url,
       ref_stories_id::BIGINT,
       link_spidered
FROM unsharded_public.topic_links

UNION

SELECT topic_links_id,
       topics_id,
       stories_id,
       url,
       redirect_url,
       ref_stories_id,
       link_spidered
FROM sharded_public.topic_links
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.topic_links
    ALTER COLUMN topic_links_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.topic_links', 'topic_links_id'));

CREATE OR REPLACE FUNCTION public.topic_links_insert() RETURNS trigger AS
$$
BEGIN

    -- Set default values (not supported by updatable views)
    IF NEW.link_spidered IS NULL THEN
        SELECT 'f' INTO NEW.link_spidered;
    END IF;

    -- Insert only into the sharded table
    INSERT INTO sharded_public.topic_links SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER topic_links_insert
    INSTEAD OF INSERT
    ON public.topic_links
    FOR EACH ROW
EXECUTE PROCEDURE public.topic_links_insert();



--
-- topic_fetch_urls
--

ALTER TABLE public.topic_fetch_urls
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.topic_fetch_urls', 'topic_fetch_urls_id'),
               nextval(pg_get_serial_sequence('unsharded_public.topic_fetch_urls', 'topic_fetch_urls_id')),
               false
           );

CREATE VIEW public.topic_fetch_urls AS
SELECT topic_fetch_urls_id,
       topics_id::BIGINT,
       url,
       code,
       fetch_date,
       state,
       message,
       stories_id::BIGINT,
       assume_match,
       topic_links_id::BIGINT
FROM unsharded_public.topic_fetch_urls

UNION

SELECT topic_fetch_urls_id,
       topics_id,
       url,
       code,
       fetch_date,
       state,
       message,
       stories_id,
       assume_match,
       topic_links_id
FROM sharded_public.topic_fetch_urls
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.topic_fetch_urls
    ALTER COLUMN topic_fetch_urls_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.topic_fetch_urls', 'topic_fetch_urls_id'));

CREATE OR REPLACE FUNCTION public.topic_fetch_urls_insert() RETURNS trigger AS
$$
BEGIN

    IF NEW.assume_match IS NULL THEN
        SELECT 'f' INTO NEW.assume_match;
    END IF;

    -- Insert only into the sharded table
    INSERT INTO sharded_public.topic_fetch_urls SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER topic_fetch_urls_insert
    INSTEAD OF INSERT
    ON public.topic_fetch_urls
    FOR EACH ROW
EXECUTE PROCEDURE public.topic_fetch_urls_insert();



--
-- topic_posts
--

ALTER TABLE public.topic_posts
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.topic_posts', 'topic_posts_id'),
               nextval(pg_get_serial_sequence('unsharded_public.topic_posts', 'topic_posts_id')),
               false
           );

CREATE VIEW public.topic_posts AS
SELECT topic_posts.topic_posts_id::BIGINT,
       topic_post_days.topics_id::BIGINT,
       topic_posts.topic_post_days_id::BIGINT,
       topic_posts.data,
       topic_posts.post_id::TEXT,
       topic_posts.content,
       topic_posts.publish_date,
       topic_posts.author::TEXT,
       topic_posts.channel::TEXT,
       topic_posts.url
FROM unsharded_public.topic_posts AS topic_posts
         -- Join the newly copied table
         INNER JOIN public.topic_post_days AS topic_post_days
                    ON topic_posts.topic_post_days_id = topic_post_days.topic_post_days_id

UNION

SELECT topic_posts_id,
       topics_id,
       topic_post_days_id,
       data,
       post_id,
       content,
       publish_date,
       author,
       channel,
       url
FROM sharded_public.topic_posts
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.topic_posts
    ALTER COLUMN topic_posts_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.topic_posts', 'topic_posts_id'));

CREATE OR REPLACE FUNCTION public.topic_posts_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.topic_posts SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER topic_posts_insert
    INSTEAD OF INSERT
    ON public.topic_posts
    FOR EACH ROW
EXECUTE PROCEDURE public.topic_posts_insert();



--
-- topic_post_urls
--

ALTER TABLE public.topic_post_urls
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.topic_post_urls', 'topic_post_urls_id'),
               nextval(pg_get_serial_sequence('unsharded_public.topic_post_urls', 'topic_post_urls_id')),
               false
           );

CREATE VIEW public.topic_post_urls AS
SELECT topic_post_urls.topic_post_urls_id::BIGINT,
       topic_post_days.topics_id::BIGINT,
       topic_post_urls.topic_posts_id::BIGINT,
       topic_post_urls.url::TEXT
FROM unsharded_public.topic_post_urls AS topic_post_urls
         INNER JOIN unsharded_public.topic_posts AS topic_posts
                    ON topic_post_urls.topic_posts_id = topic_posts.topic_posts_id
    -- Join the newly copied table
         INNER JOIN public.topic_post_days AS topic_post_days
                    ON topic_posts.topic_post_days_id = topic_post_days.topic_post_days_id

UNION

SELECT topic_post_urls_id,
       topics_id,
       topic_posts_id,
       url
FROM sharded_public.topic_post_urls
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.topic_post_urls
    ALTER COLUMN topic_post_urls_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.topic_post_urls', 'topic_post_urls_id'));

CREATE OR REPLACE FUNCTION public.topic_post_urls_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_public.topic_post_urls SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER topic_post_urls_insert
    INSTEAD OF INSERT
    ON public.topic_post_urls
    FOR EACH ROW
EXECUTE PROCEDURE public.topic_post_urls_insert();



--
-- topic_seed_urls
--

ALTER TABLE public.topic_seed_urls
    SET SCHEMA sharded_public;

SELECT setval(
               pg_get_serial_sequence('sharded_public.topic_seed_urls', 'topic_seed_urls_id'),
               nextval(pg_get_serial_sequence('unsharded_public.topic_seed_urls', 'topic_seed_urls_id')),
               false
           );

CREATE VIEW public.topic_seed_urls AS
SELECT topic_seed_urls_id::BIGINT,
       topics_id::BIGINT,
       url,
       source,
       stories_id::BIGINT,
       processed,
       assume_match,
       content,
       guid,
       title,
       publish_date,
       topic_seed_queries_id::BIGINT,
       topic_post_urls_id::BIGINT
FROM unsharded_public.topic_seed_urls

UNION

SELECT topic_seed_urls_id,
       topics_id,
       url,
       source,
       stories_id,
       processed,
       assume_match,
       content,
       guid,
       title,
       publish_date,
       topic_seed_queries_id,
       topic_post_urls_id
FROM sharded_public.topic_seed_urls
;

-- Make INSERT ... RETURNING work
    ALTER VIEW public.topic_seed_urls
    ALTER COLUMN topic_seed_urls_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_public.topic_seed_urls', 'topic_seed_urls_id'));

CREATE OR REPLACE FUNCTION public.topic_seed_urls_insert() RETURNS trigger AS
$$
BEGIN

    -- Set default values (not supported by updatable views)
    IF NEW.processed IS NULL THEN
        SELECT 'f' INTO NEW.processed;
    END IF;
    IF NEW.assume_match IS NULL THEN
        SELECT 'f' INTO NEW.assume_match;
    END IF;

    -- Insert only into the sharded table
    INSERT INTO sharded_public.topic_seed_urls SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER topic_seed_urls_insert
    INSTEAD OF INSERT
    ON public.topic_seed_urls
    FOR EACH ROW
EXECUTE PROCEDURE public.topic_seed_urls_insert();



--
-- snap.stories
--

ALTER TABLE snap.stories
    SET SCHEMA sharded_snap;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW snap.stories AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS snap_stories_id,
    snapshots.topics_id::BIGINT,
    snap_stories.snapshots_id::BIGINT,
    snap_stories.stories_id::BIGINT,
    snap_stories.media_id::BIGINT,
    snap_stories.url::TEXT,
    snap_stories.guid::TEXT,
    snap_stories.title,
    snap_stories.publish_date,
    snap_stories.collect_date,
    snap_stories.full_text_rss,
    snap_stories.language
FROM unsharded_snap.stories AS snap_stories
         -- Join the newly copied table
         INNER JOIN public.snapshots AS snapshots
                    ON snap_stories.snapshots_id = snapshots.snapshots_id

UNION

SELECT snap_stories_id,
       topics_id,
       snapshots_id,
       stories_id,
       media_id,
       url,
       guid,
       title,
       publish_date,
       collect_date,
       full_text_rss,
       language
FROM sharded_snap.stories
;

-- Make INSERT ... RETURNING work
    ALTER VIEW snap.stories
    ALTER COLUMN snap_stories_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_snap.stories', 'snap_stories_id'));

CREATE OR REPLACE FUNCTION snap.stories_insert() RETURNS trigger AS
$$
BEGIN

    -- Set default values (not supported by updatable views)
    IF NEW.full_text_rss IS NULL THEN
        SELECT 'f' INTO NEW.full_text_rss;
    END IF;

    -- Insert only into the sharded table
    INSERT INTO sharded_snap.stories SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER snap_stories_insert
    INSTEAD OF INSERT
    ON snap.stories
    FOR EACH ROW
EXECUTE PROCEDURE snap.stories_insert();



--
-- snap.topic_stories
--

ALTER TABLE snap.topic_stories
    SET SCHEMA sharded_snap;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW snap.topic_stories AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS snap_topic_stories_id,
    -- Different order than the sharded table
    topics_id::BIGINT,
    snapshots_id::BIGINT,
    topic_stories_id::BIGINT,
    stories_id::BIGINT,
    link_mined,
    iteration::BIGINT,
    link_weight,
    redirect_url,
    valid_foreign_rss_story
FROM unsharded_snap.topic_stories

UNION

SELECT snap_topic_stories_id,
       topics_id,
       snapshots_id,
       topic_stories_id,
       stories_id,
       link_mined,
       iteration,
       link_weight,
       redirect_url,
       valid_foreign_rss_story
FROM sharded_snap.topic_stories
;

-- Make INSERT ... RETURNING work
    ALTER VIEW snap.topic_stories
    ALTER COLUMN snap_topic_stories_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_snap.topic_stories', 'snap_topic_stories_id'));

CREATE OR REPLACE FUNCTION snap.topic_stories_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_snap.topic_stories SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER snap_topic_stories_insert
    INSTEAD OF INSERT
    ON snap.topic_stories
    FOR EACH ROW
EXECUTE PROCEDURE snap.topic_stories_insert();



--
-- snap.topic_links_cross_media
--

ALTER TABLE snap.topic_links_cross_media
    SET SCHEMA sharded_snap;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW snap.topic_links_cross_media AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS snap_topic_links_cross_media_id,
    -- Different order than the sharded table
    topics_id::BIGINT,
    snapshots_id::BIGINT,
    topic_links_id::BIGINT,
    stories_id::BIGINT,
    url,
    ref_stories_id::BIGINT
FROM unsharded_snap.topic_links_cross_media

UNION

SELECT snap_topic_links_cross_media_id,
       topics_id,
       snapshots_id,
       topic_links_id,
       stories_id,
       url,
       ref_stories_id
FROM sharded_snap.topic_links_cross_media
;

-- Make INSERT ... RETURNING work
    ALTER VIEW snap.topic_links_cross_media
    ALTER COLUMN snap_topic_links_cross_media_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_snap.topic_links_cross_media',
                                                   'snap_topic_links_cross_media_id'));

CREATE OR REPLACE FUNCTION snap.topic_links_cross_media_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_snap.topic_links_cross_media SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER snap_topic_links_cross_media_insert
    INSTEAD OF INSERT
    ON snap.topic_links_cross_media
    FOR EACH ROW
EXECUTE PROCEDURE snap.topic_links_cross_media_insert();



--
-- snap.media
--

ALTER TABLE snap.media
    SET SCHEMA sharded_snap;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW snap.media AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS snap_media_id,
    snapshots.topics_id,
    snap_media.snapshots_id::BIGINT,
    snap_media.media_id::BIGINT,
    snap_media.url::TEXT,
    snap_media.name::TEXT,
    snap_media.full_text_rss,
    snap_media.foreign_rss_links,
    snap_media.dup_media_id::BIGINT,
    snap_media.is_not_dup
FROM unsharded_snap.media AS snap_media
         -- Join the newly copied table
         INNER JOIN public.snapshots AS snapshots
                    ON snap_media.snapshots_id = snapshots.snapshots_id

UNION

SELECT snap_media_id,
       topics_id,
       snapshots_id,
       media_id,
       url,
       name,
       full_text_rss,
       foreign_rss_links,
       dup_media_id,
       is_not_dup
FROM sharded_snap.media
;

-- Make INSERT ... RETURNING work
    ALTER VIEW snap.media
    ALTER COLUMN snap_media_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_snap.media', 'snap_media_id'));

CREATE OR REPLACE FUNCTION snap.media_insert() RETURNS trigger AS
$$
BEGIN

    -- Set default values (not supported by updatable views)
    IF NEW.foreign_rss_links IS NULL THEN
        SELECT 'f' INTO NEW.foreign_rss_links;
    END IF;

    -- Insert only into the sharded table
    INSERT INTO sharded_snap.media SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER snap_media_insert
    INSTEAD OF INSERT
    ON snap.media
    FOR EACH ROW
EXECUTE PROCEDURE snap.media_insert();



--
-- snap.media_tags_map
--

ALTER TABLE snap.media_tags_map
    SET SCHEMA sharded_snap;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW snap.media_tags_map AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS snap_media_tags_map_id,
    snapshots.topics_id,
    snap_media_tags_map.snapshots_id::BIGINT,
    snap_media_tags_map.media_tags_map_id::BIGINT,
    snap_media_tags_map.media_id::BIGINT,
    snap_media_tags_map.tags_id::BIGINT
FROM unsharded_snap.media_tags_map AS snap_media_tags_map
         -- Join the newly copied table
         INNER JOIN public.snapshots AS snapshots
                    ON snap_media_tags_map.snapshots_id = snapshots.snapshots_id

UNION

SELECT snap_media_tags_map_id,
       topics_id,
       snapshots_id,
       media_tags_map_id,
       media_id,
       tags_id
FROM sharded_snap.media_tags_map
;

-- Make INSERT ... RETURNING work
    ALTER VIEW snap.media_tags_map
    ALTER COLUMN snap_media_tags_map_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_snap.media_tags_map', 'snap_media_tags_map_id'));

CREATE OR REPLACE FUNCTION snap.media_tags_map_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_snap.media_tags_map SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER snap_media_tags_map_insert
    INSTEAD OF INSERT
    ON snap.media_tags_map
    FOR EACH ROW
EXECUTE PROCEDURE snap.media_tags_map_insert();



--
-- snap.stories_tags_map
--

ALTER TABLE snap.stories_tags_map
    SET SCHEMA sharded_snap;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW snap.stories_tags_map AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS snap_stories_tags_map_id,
    snapshots.topics_id,
    snap_stories_tags_map.snapshots_id::BIGINT,
    snap_stories_tags_map.stories_tags_map_id::BIGINT,
    snap_stories_tags_map.stories_id::BIGINT,
    snap_stories_tags_map.tags_id::BIGINT
FROM unsharded_snap.stories_tags_map AS snap_stories_tags_map
         -- Join the newly copied table
         INNER JOIN public.snapshots AS snapshots
                    ON snap_stories_tags_map.snapshots_id = snapshots.snapshots_id

UNION

SELECT snap_stories_tags_map_id,
       topics_id,
       snapshots_id,
       stories_tags_map_id,
       stories_id,
       tags_id
FROM sharded_snap.stories_tags_map
;

-- Make INSERT ... RETURNING work
    ALTER VIEW snap.stories_tags_map
    ALTER COLUMN snap_stories_tags_map_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_snap.stories_tags_map', 'snap_stories_tags_map_id'));

CREATE OR REPLACE FUNCTION snap.stories_tags_map_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_snap.stories_tags_map SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER snap_stories_tags_map_insert
    INSTEAD OF INSERT
    ON snap.stories_tags_map
    FOR EACH ROW
EXECUTE PROCEDURE snap.stories_tags_map_insert();



--
-- snap.story_links
--

ALTER TABLE snap.story_links
    SET SCHEMA sharded_snap;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW snap.story_links AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS snap_story_links_id,
    timespans.topics_id,
    snap_story_links.timespans_id::BIGINT,
    snap_story_links.source_stories_id::BIGINT,
    snap_story_links.ref_stories_id::BIGINT
FROM unsharded_snap.story_links AS snap_story_links
         -- Join the newly copied table
         INNER JOIN public.timespans AS timespans
                    ON snap_story_links.timespans_id = timespans.timespans_id

UNION

SELECT snap_story_links_id,
       topics_id,
       timespans_id,
       source_stories_id,
       ref_stories_id
FROM sharded_snap.story_links
;

-- Make INSERT ... RETURNING work
    ALTER VIEW snap.story_links
    ALTER COLUMN snap_story_links_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_snap.story_links', 'snap_story_links_id'));

CREATE OR REPLACE FUNCTION snap.story_links_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_snap.story_links SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER snap_story_links_insert
    INSTEAD OF INSERT
    ON snap.story_links
    FOR EACH ROW
EXECUTE PROCEDURE snap.story_links_insert();



--
-- snap.story_link_counts
--

ALTER TABLE snap.story_link_counts
    SET SCHEMA sharded_snap;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW snap.story_link_counts AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS snap_story_link_counts_id,
    timespans.topics_id,
    snap_story_link_counts.timespans_id::BIGINT,
    snap_story_link_counts.stories_id::BIGINT,
    snap_story_link_counts.media_inlink_count::BIGINT,
    snap_story_link_counts.inlink_count::BIGINT,
    snap_story_link_counts.outlink_count::BIGINT,
    snap_story_link_counts.facebook_share_count::BIGINT,
    snap_story_link_counts.post_count::BIGINT,
    snap_story_link_counts.author_count::BIGINT,
    snap_story_link_counts.channel_count::BIGINT
FROM unsharded_snap.story_link_counts AS snap_story_link_counts
         -- Join the newly copied table
         INNER JOIN public.timespans AS timespans
                    ON snap_story_link_counts.timespans_id = timespans.timespans_id

UNION

SELECT snap_story_link_counts_id,
       topics_id,
       timespans_id,
       stories_id,
       media_inlink_count,
       inlink_count,
       outlink_count,
       facebook_share_count,
       post_count,
       author_count,
       channel_count
FROM sharded_snap.story_link_counts
;

-- Make INSERT ... RETURNING work
    ALTER VIEW snap.story_link_counts
    ALTER COLUMN snap_story_link_counts_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_snap.story_link_counts', 'snap_story_link_counts_id'));

CREATE OR REPLACE FUNCTION snap.story_link_counts_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_snap.story_link_counts SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER snap_story_link_counts_insert
    INSTEAD OF INSERT
    ON snap.story_link_counts
    FOR EACH ROW
EXECUTE PROCEDURE snap.story_link_counts_insert();



--
-- snap.medium_link_counts
--

ALTER TABLE snap.medium_link_counts
    SET SCHEMA sharded_snap;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW snap.medium_link_counts AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS snap_medium_link_counts_id,
    timespans.topics_id,
    snap_medium_link_counts.timespans_id::BIGINT,
    snap_medium_link_counts.media_id::BIGINT,
    snap_medium_link_counts.sum_media_inlink_count::BIGINT,
    snap_medium_link_counts.media_inlink_count::BIGINT,
    snap_medium_link_counts.inlink_count::BIGINT,
    snap_medium_link_counts.outlink_count::BIGINT,
    snap_medium_link_counts.story_count::BIGINT,
    snap_medium_link_counts.facebook_share_count::BIGINT,
    snap_medium_link_counts.sum_post_count::BIGINT,
    snap_medium_link_counts.sum_author_count::BIGINT,
    snap_medium_link_counts.sum_channel_count::BIGINT
FROM unsharded_snap.medium_link_counts AS snap_medium_link_counts
         -- Join the newly copied table
         INNER JOIN public.timespans AS timespans
                    ON snap_medium_link_counts.timespans_id = timespans.timespans_id

UNION

SELECT snap_medium_link_counts_id,
       topics_id,
       timespans_id,
       media_id,
       sum_media_inlink_count,
       media_inlink_count,
       inlink_count,
       outlink_count,
       story_count,
       facebook_share_count,
       sum_post_count,
       sum_author_count,
       sum_channel_count
FROM sharded_snap.medium_link_counts
;

-- Make INSERT ... RETURNING work
    ALTER VIEW snap.medium_link_counts
    ALTER COLUMN snap_medium_link_counts_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_snap.medium_link_counts', 'snap_medium_link_counts_id'));

CREATE OR REPLACE FUNCTION snap.medium_link_counts_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_snap.medium_link_counts SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER snap_medium_link_counts_insert
    INSTEAD OF INSERT
    ON snap.medium_link_counts
    FOR EACH ROW
EXECUTE PROCEDURE snap.medium_link_counts_insert();



--
-- snap.medium_links
--

ALTER TABLE snap.medium_links
    SET SCHEMA sharded_snap;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW snap.medium_links AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS snap_medium_links_id,
    timespans.topics_id,
    snap_medium_links.timespans_id::BIGINT,
    snap_medium_links.source_media_id::BIGINT,
    snap_medium_links.ref_media_id::BIGINT,
    snap_medium_links.link_count::BIGINT
FROM unsharded_snap.medium_links AS snap_medium_links
         -- Join the newly copied table
         INNER JOIN public.timespans AS timespans
                    ON snap_medium_links.timespans_id = timespans.timespans_id

UNION

SELECT snap_medium_links_id,
       topics_id,
       timespans_id,
       source_media_id,
       ref_media_id,
       link_count
FROM sharded_snap.medium_links
;

-- Make INSERT ... RETURNING work
    ALTER VIEW snap.medium_links
    ALTER COLUMN snap_medium_links_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_snap.medium_links', 'snap_medium_links_id'));

CREATE OR REPLACE FUNCTION snap.medium_links_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_snap.medium_links SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER snap_medium_links_insert
    INSTEAD OF INSERT
    ON snap.medium_links
    FOR EACH ROW
EXECUTE PROCEDURE snap.medium_links_insert();



--
-- snap.timespan_posts
--

ALTER TABLE snap.timespan_posts
    SET SCHEMA sharded_snap;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW snap.timespan_posts AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS snap_timespan_posts_id,
    timespans.topics_id,
    snap_timespan_posts.timespans_id::BIGINT,
    snap_timespan_posts.topic_posts_id::BIGINT
FROM unsharded_snap.timespan_posts AS snap_timespan_posts
         -- Join the newly copied table
         INNER JOIN public.timespans AS timespans
                    ON snap_timespan_posts.timespans_id = timespans.timespans_id

UNION

SELECT snap_timespan_posts_id,
       topics_id,
       timespans_id,
       topic_posts_id
FROM sharded_snap.timespan_posts
;

-- Make INSERT ... RETURNING work
    ALTER VIEW snap.timespan_posts
    ALTER COLUMN snap_timespan_posts_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_snap.timespan_posts', 'snap_timespan_posts_id'));

CREATE OR REPLACE FUNCTION snap.timespan_posts_insert() RETURNS trigger AS
$$
BEGIN
    -- Insert only into the sharded table
    INSERT INTO sharded_snap.timespan_posts SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER snap_timespan_posts_insert
    INSTEAD OF INSERT
    ON snap.timespan_posts
    FOR EACH ROW
EXECUTE PROCEDURE snap.timespan_posts_insert();



--
-- snap.live_stories
--

ALTER TABLE snap.live_stories
    SET SCHEMA sharded_snap;

-- No setval(pg_get_serial_sequence(), nextval(), false) because unsharded
-- table doesn't have primary key

CREATE VIEW snap.live_stories AS
SELECT
    -- No primary key on unsharded table
    0::BIGINT AS snap_live_stories_id,
    topics_id::BIGINT,
    topic_stories_id::BIGINT,
    stories_id::BIGINT,
    media_id::BIGINT,
    url::TEXT,
    guid::TEXT,
    title,
    normalized_title_hash,
    description,
    publish_date,
    collect_date,
    full_text_rss,
    language
FROM unsharded_snap.live_stories

UNION

SELECT snap_live_stories_id,
       topics_id,
       topic_stories_id,
       stories_id,
       media_id,
       url,
       guid,
       title,
       normalized_title_hash,
       description,
       publish_date,
       collect_date,
       full_text_rss,
       language
FROM sharded_snap.live_stories
;

-- Make INSERT ... RETURNING work
    ALTER VIEW snap.live_stories
    ALTER COLUMN snap_live_stories_id
        SET DEFAULT nextval(pg_get_serial_sequence('sharded_snap.live_stories', 'snap_live_stories_id'));

CREATE OR REPLACE FUNCTION snap.live_stories_insert() RETURNS trigger AS
$$
BEGIN

    -- Set default values (not supported by updatable views)
    IF NEW.full_text_rss IS NULL THEN
        SELECT 'f' INTO NEW.full_text_rss;
    END IF;

    -- Insert only into the sharded table
    INSERT INTO sharded_snap.live_stories SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- UPDATEs and DELETEs don't work: https://github.com/citusdata/citus/issues/2046
CREATE TRIGGER snap_live_stories_insert
    INSTEAD OF INSERT
    ON snap.live_stories
    FOR EACH ROW
EXECUTE PROCEDURE snap.live_stories_insert();

-- New rows will end up only in sharded snap.live_stories() so
-- insert_live_story() will be triggered

-- Recreate update_live_story() and re-add it as a trigger for it to UPDATE
-- both the unsharded and sharded tables
CREATE OR REPLACE FUNCTION unsharded_public.update_live_story() RETURNS TRIGGER AS
$$

BEGIN

    UPDATE unsharded_snap.live_stories
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

    UPDATE sharded_snap.live_stories
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

CREATE TRIGGER stories_update_live_story
    AFTER UPDATE
    ON unsharded_public.stories
    FOR EACH ROW
EXECUTE PROCEDURE unsharded_public.update_live_story();


-- MC_CITUS_SHARDING_UPDATABLE_VIEW_HACK: update update_live_story() on the
-- sharded table too; later it's to be made to update only the sharded table
-- again, just like it used to do in the previous migration
CREATE OR REPLACE FUNCTION public.update_live_story() RETURNS TRIGGER AS
$$

BEGIN

    UPDATE unsharded_snap.live_stories
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

    UPDATE sharded_snap.live_stories
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



--
-- UPDATE VIEWS IN FRONT OF UNSHARDED PARTITIONED TABLED
--

--
-- story_sentences
--

DROP VIEW unsharded_public.story_sentences;
CREATE VIEW unsharded_public.story_sentences AS

SELECT story_sentences_p_id AS story_sentences_id,
       stories_id,
       sentence_number,
       sentence,
       media_id,
       publish_date,
       language,
       is_dup
FROM unsharded_public.story_sentences_p;

DROP FUNCTION unsharded_public.story_sentences_view_insert_update_delete();
CREATE FUNCTION unsharded_public.story_sentences_view_insert_update_delete() RETURNS trigger AS
$$
BEGIN

    IF (TG_OP = 'INSERT') THEN

        RAISE EXCEPTION 'You should not be inserting into the unsharded table anymore.';

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE unsharded_public.story_sentences_p
        SET stories_id      = NEW.stories_id,
            sentence_number = NEW.sentence_number,
            sentence        = NEW.sentence,
            media_id        = NEW.media_id,
            publish_date    = NEW.publish_date,
            language        = NEW.language,
            is_dup          = NEW.is_dup
        WHERE stories_id = OLD.stories_id
          AND sentence_number = OLD.sentence_number;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        DELETE
        FROM unsharded_public.story_sentences_p
        WHERE stories_id = OLD.stories_id
          AND sentence_number = OLD.sentence_number;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER story_sentences_view_insert_update_delete_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE
    ON unsharded_public.story_sentences
    FOR EACH ROW
EXECUTE PROCEDURE unsharded_public.story_sentences_view_insert_update_delete();


--
-- feeds_stories_map
--

DROP VIEW unsharded_public.feeds_stories_map;
CREATE VIEW unsharded_public.feeds_stories_map AS
SELECT feeds_stories_map_p_id AS feeds_stories_map_id,
       feeds_id,
       stories_id
FROM unsharded_public.feeds_stories_map_p;

DROP FUNCTION unsharded_public.feeds_stories_map_view_insert_update_delete();
CREATE FUNCTION unsharded_public.feeds_stories_map_view_insert_update_delete() RETURNS trigger AS
$$

BEGIN

    IF (TG_OP = 'INSERT') THEN

        RAISE EXCEPTION 'You should not be inserting into the unsharded table anymore.';

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE unsharded_public.feeds_stories_map_p
        SET feeds_id   = NEW.feeds_id,
            stories_id = NEW.stories_id
        WHERE feeds_id = OLD.feeds_id
          AND stories_id = OLD.stories_id;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        DELETE
        FROM unsharded_public.feeds_stories_map_p
        WHERE feeds_id = OLD.feeds_id
          AND stories_id = OLD.stories_id;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER feeds_stories_map_view_insert_update_delete_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE
    ON unsharded_public.feeds_stories_map
    FOR EACH ROW
EXECUTE PROCEDURE unsharded_public.feeds_stories_map_view_insert_update_delete();



--
-- stories_tags_map
--

DROP VIEW unsharded_public.stories_tags_map;
CREATE VIEW unsharded_public.stories_tags_map AS

SELECT stories_tags_map_p_id AS stories_tags_map_id,
       stories_id,
       tags_id
FROM unsharded_public.stories_tags_map_p;

DROP FUNCTION unsharded_public.stories_tags_map_view_insert_update_delete();
CREATE FUNCTION unsharded_public.stories_tags_map_view_insert_update_delete() RETURNS trigger AS
$$
BEGIN

    IF (TG_OP = 'INSERT') THEN

        RAISE EXCEPTION 'You should not be inserting into the unsharded table anymore.';

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE unsharded_public.stories_tags_map_p
        SET stories_id = NEW.stories_id,
            tags_id    = NEW.tags_id
        WHERE stories_id = OLD.stories_id
          AND tags_id = OLD.tags_id;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        DELETE
        FROM unsharded_public.stories_tags_map_p
        WHERE stories_id = OLD.stories_id
          AND tags_id = OLD.tags_id;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER stories_tags_map_view_insert_update_delete
    INSTEAD OF INSERT OR UPDATE OR DELETE
    ON unsharded_public.stories_tags_map
    FOR EACH ROW
EXECUTE PROCEDURE unsharded_public.stories_tags_map_view_insert_update_delete();



CREATE OR REPLACE FUNCTION public.insert_solr_import_story() RETURNS TRIGGER AS
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

    -- MC_CITUS_SHARDING_UPDATABLE_VIEW_HACK: don't test the old table anymore after moving rows
    IF NOT EXISTS(
            SELECT 1
            FROM unsharded_public.solr_import_stories
            WHERE stories_id = queue_stories_id
        ) THEN

        INSERT INTO sharded_public.solr_import_stories (stories_id)
        VALUES (queue_stories_id)
        ON CONFLICT (stories_id) DO NOTHING;

    END IF;

    RETURN return_value;

END;

$$ LANGUAGE plpgsql;

-- noinspection SqlResolve @ routine/"create_distributed_function"
SELECT create_distributed_function('public.insert_solr_import_story()');


--
-- DROP FOREIGN KEYS ON BIG UNSHARDED TABLES
-- (makes it easier to gradually move rows)
--


--
-- unsharded_public.auth_user_request_daily_counts
--

-- No foreign keys



--
-- unsharded_public.media_stats
--

-- No foreign keys


--
-- unsharded_public.media_coverage_gaps
--

-- No foreign keys


--
-- unsharded_public.stories
--

ALTER TABLE unsharded_public.downloads
    DROP CONSTRAINT downloads_stories_id_fkey;
ALTER TABLE unsharded_public.processed_stories
    DROP CONSTRAINT processed_stories_stories_id_fkey;
ALTER TABLE unsharded_public.scraped_stories
    DROP CONSTRAINT scraped_stories_stories_id_fkey;
ALTER TABLE unsharded_public.solr_import_stories
    -- Not in production
    DROP CONSTRAINT IF EXISTS solr_import_stories_stories_id_fkey;
ALTER TABLE unsharded_public.solr_import_stories
    -- Only in production
    DROP CONSTRAINT IF EXISTS solr_import_extra_stories_stories_id_fkey;
ALTER TABLE unsharded_public.solr_imported_stories
    DROP CONSTRAINT solr_imported_stories_stories_id_fkey;
ALTER TABLE unsharded_public.stories_ap_syndicated
    DROP CONSTRAINT stories_ap_syndicated_stories_id_fkey;
ALTER TABLE unsharded_public.story_enclosures
    DROP CONSTRAINT story_enclosures_stories_id_fkey;
ALTER TABLE unsharded_public.story_statistics
    DROP CONSTRAINT story_statistics_stories_id_fkey;
ALTER TABLE unsharded_public.story_urls
    DROP CONSTRAINT story_urls_stories_id_fkey;
ALTER TABLE unsharded_public.topic_fetch_urls
    DROP CONSTRAINT topic_fetch_urls_stories_id_fkey;
ALTER TABLE unsharded_public.topic_links
    -- Not in production
    DROP CONSTRAINT IF EXISTS topic_links_ref_stories_id_fkey;
ALTER TABLE unsharded_public.topic_links
    -- Only in production
    DROP CONSTRAINT IF EXISTS controversy_links_ref_stories_id_fkey;
ALTER TABLE unsharded_public.topic_merged_stories_map
    -- Not in production
    DROP CONSTRAINT IF EXISTS topic_merged_stories_map_source_stories_id_fkey;
ALTER TABLE unsharded_public.topic_merged_stories_map
    -- Only in production
    DROP CONSTRAINT IF EXISTS controversy_merged_stories_map_source_stories_id_fkey;
ALTER TABLE unsharded_public.topic_merged_stories_map
    -- Not in production
    DROP CONSTRAINT IF EXISTS topic_merged_stories_map_target_stories_id_fkey;
ALTER TABLE unsharded_public.topic_merged_stories_map
    -- Only in production
    DROP CONSTRAINT IF EXISTS controversy_merged_stories_map_target_stories_id_fkey;
ALTER TABLE unsharded_public.topic_query_story_searches_imported_stories_map
    DROP CONSTRAINT topic_query_story_searches_imported_stories_map_stories_id_fkey;
ALTER TABLE unsharded_public.topic_seed_urls
    -- Not in production
    DROP CONSTRAINT IF EXISTS topic_seed_urls_stories_id_fkey;
ALTER TABLE unsharded_public.topic_seed_urls
    -- Only in production
    DROP CONSTRAINT IF EXISTS controversy_seed_urls_stories_id_fkey;
ALTER TABLE unsharded_public.topic_stories
    -- Not in production
    DROP CONSTRAINT IF EXISTS topic_stories_stories_id_fkey;
ALTER TABLE unsharded_public.topic_stories
    -- Only in production
    DROP CONSTRAINT IF EXISTS controversy_stories_stories_id_fkey;
ALTER TABLE unsharded_snap.live_stories
    DROP CONSTRAINT live_stories_stories_id_fkey;

DO
$$
    DECLARE

        tables CURSOR FOR
            SELECT tablename
            FROM pg_tables
            WHERE
                schemaname = 'unsharded_public' AND
                (
                    tablename LIKE 'feeds_stories_map_p_%' OR
                    tablename LIKE 'stories_tags_map_p_%' OR
                    tablename LIKE 'story_sentences_p_%'
                )
            ORDER BY tablename;

    BEGIN
        FOR table_record IN tables
            LOOP

                EXECUTE '
            ALTER TABLE unsharded_public.' || table_record.tablename || '
                DROP CONSTRAINT ' || table_record.tablename || '_stories_id_fkey
        ';

            END LOOP;
    END
$$;


--
-- unsharded_public.stories_ap_syndicated
--

-- No foreign keys


--
-- unsharded_public.story_urls
--

-- No foreign keys


--
-- unsharded_public.feeds_stories_map_p
--

-- No foreign keys



--
-- unsharded_public.stories_tags_map_p
--

-- No foreign keys



--
-- unsharded_public.story_sentences_p
--

-- No foreign keys



--
-- unsharded_public.solr_import_stories
--

-- No foreign keys



--
-- unsharded_public.solr_imported_stories
--

-- No foreign keys



--
-- unsharded_public.topic_merged_stories_map
--

-- No foreign keys



--
-- unsharded_public.story_statistics
--

-- No foreign keys



--
-- unsharded_public.processed_stories
--

-- No foreign keys



--
-- unsharded_public.scraped_stories
--

-- No foreign keys



--
-- unsharded_public.story_enclosures
--

-- No foreign keys



--
-- unsharded_public.downloads
--

DO
$$
    DECLARE

        tables CURSOR FOR
            SELECT tablename
            FROM pg_tables
            WHERE
                schemaname = 'unsharded_public' AND
                tablename LIKE 'download_texts_%'
            ORDER BY tablename;

    BEGIN
        FOR table_record IN tables
            LOOP

                EXECUTE '
            ALTER TABLE unsharded_public.' || table_record.tablename || '
                DROP CONSTRAINT ' || table_record.tablename || '_downloads_id_fkey
        ';

            END LOOP;
    END
$$;



--
-- unsharded_public.topic_stories
--

ALTER TABLE unsharded_snap.live_stories
    -- Not in production
    DROP CONSTRAINT IF EXISTS live_stories_topic_stories_id_fkey;
ALTER TABLE unsharded_snap.live_stories
    -- Only in production
    DROP CONSTRAINT IF EXISTS live_stories_controvery_stories_id_fkey;
ALTER TABLE unsharded_public.topic_links
    DROP CONSTRAINT topic_links_topic_story_stories_id;


--
-- unsharded_public.topic_links
--

ALTER TABLE unsharded_public.topic_fetch_urls
    -- Not in production
    DROP CONSTRAINT IF EXISTS topic_fetch_urls_topic_links_id_fkey;
ALTER TABLE unsharded_public.topic_fetch_urls
    -- Only in production
    DROP CONSTRAINT IF EXISTS topic_fetch_urls_topic_links_id_fkey1;


--
-- unsharded_public.topic_fetch_urls
--

-- No foreign keys



--
-- unsharded_public.topic_posts
--

ALTER TABLE unsharded_snap.timespan_posts
    -- Not in production
    DROP CONSTRAINT IF EXISTS timespan_posts_topic_posts_id_fkey;
ALTER TABLE unsharded_snap.timespan_posts
    -- Only in production
    DROP CONSTRAINT IF EXISTS timespan_tweets_topic_tweets_id_fkey;
ALTER TABLE unsharded_public.topic_post_urls
    -- Not in production
    DROP CONSTRAINT IF EXISTS topic_post_urls_topic_posts_id_fkey;
ALTER TABLE unsharded_public.topic_post_urls
    -- Not in production
    DROP CONSTRAINT IF EXISTS topic_tweet_urls_topic_tweets_id_fkey;



--
-- unsharded_public.topic_post_urls
--

ALTER TABLE unsharded_public.topic_seed_urls
    -- Not in production
    DROP CONSTRAINT IF EXISTS topic_seed_urls_topic_post_urls_id_fkey;
ALTER TABLE unsharded_public.topic_seed_urls
    -- Only in production
    DROP CONSTRAINT IF EXISTS topic_tweet_urls_topic_tweets_id_fkey;



--
-- unsharded_public.topic_seed_urls
--

-- No foreign keys



--
-- unsharded_snap.stories
--

-- No foreign keys



--
-- unsharded_snap.topic_stories
--

-- No foreign keys



--
-- unsharded_snap.topic_links_cross_media
--

-- No foreign keys



--
-- unsharded_snap.media
--

-- No foreign keys



--
-- unsharded_snap.media_tags_map
--

-- No foreign keys



--
-- unsharded_snap.stories_tags_map
--

-- No foreign keys



--
-- unsharded_snap.story_links
--

-- No foreign keys



--
-- unsharded_snap.story_link_counts
--

-- No foreign keys



--
-- unsharded_snap.medium_link_counts
--

-- No foreign keys



--
-- unsharded_snap.medium_links
--

-- No foreign keys



--
-- unsharded_snap.timespan_posts
--

-- No foreign keys



--
-- unsharded_snap.live_stories
--

-- No foreign keys
