-- Create schemas to temporarily move the sharded tables to
CREATE SCHEMA sharded_public;
CREATE SCHEMA sharded_public_store;
CREATE SCHEMA sharded_snap;
CREATE SCHEMA sharded_cache;


-- "schema_version" table is small and local so we can just move it straight away






--
-- DROP UNUSED VIEWS
--

DROP VIEW unsharded_public.controversies;

DROP VIEW unsharded_public.controversy_dumps;

DROP VIEW unsharded_public.controversy_dump_time_slices;

-- Will have to do copying from partitions directly
DROP VIEW unsharded_public.story_sentences;

-- Will have to do copying from partitions directly
DROP VIEW unsharded_public.feeds_stories_map;

-- Will have to do copying from partitions directly
DROP VIEW unsharded_public.stories_tags_map;

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
-- MOVE ALL ROWS FOR SMALL TABLES
--


--
-- database_variables
--
INSERT INTO public.database_variables (
    database_variables_id,
    name,
    value
)
    SELECT
        database_variables_id::BIGINT,
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
INSERT INTO public.color_sets (
    color_sets_id,
    color,
    color_set,
    id
)
    SELECT
        color_sets_id::BIGINT,
        color::TEXT,
        color_set::TEXT,
        id::TEXT
    FROM unsharded_public.color_sets

-- Previous migration pre-inserted a bunch of color sets that are already
-- present in the unsharded table
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
    downloads_id
)
    SELECT
        downloads_id
    FROM unsharded_public.queued_downloads;

TRUNCATE unsharded_public.queued_downloads;
DROP TABLE unsharded_public.queued_downloads;


--
-- topic_modes
--

-- "unsharded_public.topic_modes" and "public.topic_modes" are
-- identical; can't drop the unsharded table here because it's referenced in
-- multiple places, so let's just pretend it doesn't exist at this point


--
-- topic_platforms
--

-- "unsharded_public.topic_platforms" and "public.topic_platforms" are
-- identical; can't drop the unsharded table here because it's referenced in
-- multiple places, so let's just pretend it doesn't exist at this point



--
-- topic_sources
--

-- "unsharded_public.topic_sources" and "public.topic_sources" are
-- identical; can't drop the unsharded table here because it's referenced in
-- multiple places, so let's just pretend it doesn't exist at this point




--
-- topic_platforms_sources_map
--

-- "unsharded_public.topic_platforms_sources_map" and "public.topic_platforms_sources_map" are
-- identical; can't drop the unsharded table here because it's referenced in
-- multiple places, so let's just pretend it doesn't exist at this point



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

INSERT INTO public.media (
    media_id,
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
    is_monitored
)
    SELECT
        media_id::BIGINT,
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

-- Recreate triggers
SELECT run_on_shards_or_raise('media', $cmd$

    CREATE TRIGGER media_rescraping_add_initial_state_trigger
        AFTER INSERT
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE media_rescraping_add_initial_state_trigger();

    $cmd$);

-- Can't drop the unsharded table here because it's referenced in multiple
-- places, so let's just pretend it doesn't exist at this point


--
-- media_rescraping
--

INSERT INTO public.media_rescraping (
    -- Primary key does not exist in the source table
    media_id,
    disable,
    last_rescrape_time
)
    SELECT
        media_id::BIGINT,
        disable,
        last_rescrape_time
    FROM unsharded_public.media_rescraping;

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

INSERT INTO public.feeds (
    feeds_id,
    media_id,
    name,
    url,
    type,
    active,
    last_checksum,
    last_attempted_download_time,
    last_successful_download_time,
    last_new_story_time
)
    SELECT
        feeds_id::BIGINT,
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

-- Can't drop the unsharded table here because it's referenced in multiple
-- places, so let's just pretend it doesn't exist at this point



--
-- feeds_after_rescraping
--

INSERT INTO public.feeds_after_rescraping (
    feeds_after_rescraping_id,
    media_id,
    name,
    url,
    type
)
    SELECT
        feeds_after_rescraping_id::BIGINT,
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

INSERT INTO public.tag_sets (
    tag_sets_id,
    name,
    label,
    description,
    show_on_media,
    show_on_stories
)
    SELECT
        tag_sets_id::BIGINT,
        name::TEXT,
        label::TEXT,
        description,
        show_on_media,
        show_on_stories
    FROM unsharded_public.tag_sets
-- Previous migration pre-inserted a bunch of color sets that are already
-- present in the unsharded table
ON CONFLICT (name) DO NOTHING;

SELECT setval(
    pg_get_serial_sequence('public.tag_sets', 'tag_sets_id'),
    nextval(pg_get_serial_sequence('unsharded_public.tag_sets', 'tag_sets_id')),
    false
);

-- Can't drop the unsharded table here because it's referenced in multiple
-- places, so let's just pretend it doesn't exist at this point







--
-- tags
--

-- Drop some indexes to speed up initial insert a little
DROP INDEX public.tags_tag_sets_id;
DROP INDEX public.tags_label;
DROP INDEX public.tags_fts;
DROP INDEX public.tags_show_on_media;
DROP INDEX public.tags_show_on_stories;

INSERT INTO public.tags (
    tags_id,
    tag_sets_id,
    tag,
    label,
    description,
    show_on_media,
    show_on_stories,
    is_static
)
    SELECT
        tags_id::BIGINT,
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

-- Can't drop the unsharded table here because it's referenced in multiple
-- places, so let's just pretend it doesn't exist at this point





--
-- feeds_tags_map
--

INSERT INTO public.feeds_tags_map (
    -- Primary key is not important
    feeds_id,
    tags_id
)
    SELECT
        feeds_id::BIGINT,
        tags_id::BIGINT
    FROM unsharded_public.feeds_tags_map;

-- "feeds" and "tags" are already copied so we no longer need the unsharded table
TRUNCATE unsharded_public.feeds_tags_map;
DROP TABLE unsharded_public.feeds_tags_map;




--
-- media_tags_map
--

INSERT INTO public.media_tags_map (
    -- Primary key is not important
    media_id,
    tags_id,
    tagged_date
)
    SELECT
        media_id::BIGINT,
        tags_id::BIGINT,
        tagged_date
    FROM unsharded_public.media_tags_map;

-- "media" and "tags" are already copied so we no longer need the unsharded table
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
    num_stories
)
    SELECT
        import_date,
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
    import_module
)
    SELECT
        feeds_id::BIGINT,
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

INSERT INTO public.auth_users (
    auth_users_id,
    email,
    password_hash,
    full_name,
    notes,
    active,
    password_reset_token_hash,
    last_unsuccessful_login_attempt,
    created_date,
    has_consented
)
    SELECT
        auth_users_id::BIGINT,
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

-- Can't drop the unsharded table here because it's referenced in multiple
-- places, so let's just pretend it doesn't exist at this point





--
-- auth_user_api_keys
--

INSERT INTO public.auth_user_api_keys (
    -- Primary key is not important
    auth_users_id,
    api_key,
    ip_address
)
    SELECT
        auth_users_id::BIGINT,
        api_key,
        ip_address
    FROM unsharded_public.auth_user_api_keys;

TRUNCATE unsharded_public.auth_user_api_keys;
DROP TABLE unsharded_public.auth_user_api_keys;






--
-- auth_users_roles_map
--

INSERT INTO public.auth_users_roles_map (
    -- Primary key is not important
    auth_users_id,
    auth_roles_id
)
    SELECT
        auth_users_id::BIGINT,
        auth_roles_id::BIGINT
    FROM unsharded_public.auth_users_roles_map;

TRUNCATE unsharded_public.auth_users_roles_map;
DROP TABLE unsharded_public.auth_users_roles_map;



--
-- auth_roles
--

-- Production has some weird non-standard auth_roles.auth_roles_id which we'll want to use
WITH all_auth_roles_ids AS (
    SELECT auth_roles_id
    FROM public.auth_roles
)
DELETE FROM public.auth_roles
WHERE public.auth_roles.auth_roles_id IN (
    SELECT auth_roles_id
    FROM all_auth_roles_ids
);

INSERT INTO public.auth_roles (
    auth_roles_id,
    role,
    description
)
    SELECT
        auth_roles_id::BIGINT,
        role,
        description
    FROM unsharded_public.auth_roles;

SELECT setval(
    pg_get_serial_sequence('public.auth_roles', 'auth_roles_id'),
    nextval(pg_get_serial_sequence('unsharded_public.auth_roles', 'auth_roles_id')),
    false
);

TRUNCATE unsharded_public.auth_roles;
DROP TABLE unsharded_public.auth_roles;




--
-- auth_user_limits
--

INSERT INTO public.auth_user_limits (
    -- Primary key is not important
    auth_users_id,
    weekly_requests_limit,
    weekly_requested_items_limit,
    max_topic_stories
)
    SELECT
        auth_users_id::BIGINT,
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
    edit_tag_descriptors
)
    SELECT
        auth_users_id::BIGINT,
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
    description
)
    SELECT
        name::TEXT,
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
    active
)
    SELECT
        feeds_id::BIGINT,
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

INSERT INTO public.api_links (
    api_links_id,
    path,
    params,
    next_link_id,
    previous_link_id
)
    SELECT
        api_links_id,
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
    tags_id
)
    SELECT
        media_suggestions_id::BIGINT,
        tags_id::BIGINT
    FROM unsharded_public.media_suggestions_tags_map;

TRUNCATE unsharded_public.media_suggestions_tags_map;
DROP TABLE unsharded_public.media_suggestions_tags_map;






--
-- media_suggestions
--

INSERT INTO public.media_suggestions (
    media_suggestions_id,
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
    status
)
    SELECT
        media_suggestions_id::BIGINT,
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
    total_sentences
)
    SELECT
        stats_date,
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
-- media_similarweb_domains_map
--

INSERT INTO public.media_similarweb_domains_map (
    -- Primary key is not important
    media_id,
    similarweb_domains_id
)
    SELECT
        media_id::BIGINT,
        similarweb_domains_id::BIGINT
    FROM unsharded_public.media_similarweb_domains_map;

TRUNCATE unsharded_public.media_similarweb_domains_map;
DROP TABLE unsharded_public.media_similarweb_domains_map;




--
-- similarweb_estimated_visits
--

INSERT INTO public.similarweb_estimated_visits (
    -- Primary key is not important
    similarweb_domains_id,
    month,
    main_domain_only,
    visits
)
    SELECT
        similarweb_domains_id::BIGINT,
        month,
        main_domain_only,
        visits
    FROM unsharded_public.similarweb_estimated_visits;

TRUNCATE unsharded_public.similarweb_estimated_visits;
DROP TABLE unsharded_public.similarweb_estimated_visits;






--
-- similarweb_domains
--

INSERT INTO public.similarweb_domains (
    similarweb_domains_id,
    domain
)
    SELECT
        similarweb_domains_id::BIGINT,
        domain
    FROM unsharded_public.similarweb_domains;

SELECT setval(
    pg_get_serial_sequence('public.similarweb_domains', 'similarweb_domains_id'),
    nextval(pg_get_serial_sequence('unsharded_public.similarweb_domains', 'similarweb_domains_id')),
    false
);

TRUNCATE unsharded_public.similarweb_domains;
DROP TABLE unsharded_public.similarweb_domains;








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
    stat_week
)
    SELECT
        media_id::BIGINT,
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
    expected_sentences
)
    SELECT
        media_id::BIGINT,
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
    coverage_gaps
)
    SELECT
        media_id::BIGINT,
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

DROP FUNCTION unsharded_public.story_sentences_view_insert_update_delete();

DROP FUNCTION unsharded_public.stories_tags_map_view_insert_update_delete();




--
-- DROP UNUSED TRIGGERS
--

DROP TRIGGER stories_tags_map_p_upsert_trigger ON unsharded_public.stories_tags_map_p;
DROP FUNCTION unsharded_public.stories_tags_map_p_upsert_trigger();

DROP TRIGGER story_sentences_p_insert_trigger ON unsharded_public.story_sentences_p;
DROP FUNCTION unsharded_public.story_sentences_p_insert_trigger();

DROP TRIGGER topic_stories_insert_live_story ON unsharded_public.topic_stories;
DROP FUNCTION unsharded_public.insert_live_story();

DROP TRIGGER stories_update_live_story ON unsharded_public.stories;
DROP FUNCTION unsharded_public.update_live_story();

DROP TRIGGER auth_user_api_keys_add_non_ip_limited_api_key ON unsharded_public.auth_users;
DROP FUNCTION unsharded_public.auth_user_api_keys_add_non_ip_limited_api_key();

DROP TRIGGER auth_users_set_default_limits ON unsharded_public.auth_users;
DROP FUNCTION unsharded_public.auth_users_set_default_limits();

DROP FUNCTION unsharded_cache.update_cache_db_row_last_updated();

DROP TRIGGER downloads_error_test_referenced_download_trigger ON unsharded_public.downloads_error;
DROP TRIGGER downloads_feed_error_test_referenced_download_trigger ON unsharded_public.downloads_feed_error;
DROP TRIGGER downloads_fetching_test_referenced_download_trigger ON unsharded_public.downloads_fetching;
DROP TRIGGER downloads_pending_test_referenced_download_trigger ON unsharded_public.downloads_pending;
DROP TRIGGER raw_downloads_test_referenced_download_trigger ON unsharded_public.raw_downloads;

DO $$
DECLARE

    tables CURSOR FOR
        SELECT tablename
        FROM pg_tables
        WHERE
            schemaname = 'unsharded_public' AND (
                tablename LIKE 'downloads_success_content_%' OR
                tablename LIKE 'downloads_success_feed_%' OR
                tablename LIKE 'download_texts_%'
            )

        ORDER BY tablename;

BEGIN
    FOR table_record IN tables LOOP

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

DROP TRIGGER stories_insert_solr_import_story ON unsharded_public.stories;
DROP TRIGGER stories_tags_map_p_insert_solr_import_story ON unsharded_public.stories_tags_map_p;
DROP TRIGGER ps_insert_solr_import_story ON unsharded_public.processed_stories;
DROP FUNCTION unsharded_public.insert_solr_import_story();
