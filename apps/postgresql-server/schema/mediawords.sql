--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Ubuntu 13.3-1.pgdg20.04+1)
-- Dumped by pg_dump version 13.3 (Ubuntu 13.3-1.pgdg20.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: cache; Type: SCHEMA; Schema: -; Owner: mediacloud
--

CREATE SCHEMA cache;


ALTER SCHEMA cache OWNER TO mediacloud;

--
-- Name: SCHEMA cache; Type: COMMENT; Schema: -; Owner: mediacloud
--

COMMENT ON SCHEMA cache IS 'schema to hold object caches';


--
-- Name: public_store; Type: SCHEMA; Schema: -; Owner: mediacloud
--

CREATE SCHEMA public_store;


ALTER SCHEMA public_store OWNER TO mediacloud;

--
-- Name: SCHEMA public_store; Type: COMMENT; Schema: -; Owner: mediacloud
--

COMMENT ON SCHEMA public_store IS 'table for object types used for mediawords.util.public_store';


--
-- Name: snap; Type: SCHEMA; Schema: -; Owner: mediacloud
--

CREATE SCHEMA snap;


ALTER SCHEMA snap OWNER TO mediacloud;

--
-- Name: SCHEMA snap; Type: COMMENT; Schema: -; Owner: mediacloud
--

COMMENT ON SCHEMA snap IS 'schema to hold the various snapshot snapshot tables';


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: bot_policy_type; Type: TYPE; Schema: public; Owner: mediacloud
--

CREATE TYPE public.bot_policy_type AS ENUM (
    'all',
    'no bots',
    'only bots'
);


ALTER TYPE public.bot_policy_type OWNER TO mediacloud;

--
-- Name: download_state; Type: TYPE; Schema: public; Owner: mediacloud
--

CREATE TYPE public.download_state AS ENUM (
    'error',
    'fetching',
    'pending',
    'success',
    'feed_error'
);


ALTER TYPE public.download_state OWNER TO mediacloud;

--
-- Name: download_type; Type: TYPE; Schema: public; Owner: mediacloud
--

CREATE TYPE public.download_type AS ENUM (
    'content',
    'feed'
);


ALTER TYPE public.download_type OWNER TO mediacloud;

--
-- Name: feed_type; Type: TYPE; Schema: public; Owner: mediacloud
--

CREATE TYPE public.feed_type AS ENUM (
    'syndicated',
    'web_page',
    'univision',
    'ap',
    'podcast'
);


ALTER TYPE public.feed_type OWNER TO mediacloud;

--
-- Name: focal_technique_type; Type: TYPE; Schema: public; Owner: mediacloud
--

CREATE TYPE public.focal_technique_type AS ENUM (
    'Boolean Query',
    'URL Sharing'
);


ALTER TYPE public.focal_technique_type OWNER TO mediacloud;

--
-- Name: media_sitemap_pages_change_frequency; Type: TYPE; Schema: public; Owner: mediacloud
--

CREATE TYPE public.media_sitemap_pages_change_frequency AS ENUM (
    'always',
    'hourly',
    'daily',
    'weekly',
    'monthly',
    'yearly',
    'never'
);


ALTER TYPE public.media_sitemap_pages_change_frequency OWNER TO mediacloud;

--
-- Name: media_suggestions_status; Type: TYPE; Schema: public; Owner: mediacloud
--

CREATE TYPE public.media_suggestions_status AS ENUM (
    'pending',
    'approved',
    'rejected'
);


ALTER TYPE public.media_suggestions_status OWNER TO mediacloud;

--
-- Name: retweeter_scores_match_type; Type: TYPE; Schema: public; Owner: mediacloud
--

CREATE TYPE public.retweeter_scores_match_type AS ENUM (
    'retweet',
    'regex'
);


ALTER TYPE public.retweeter_scores_match_type OWNER TO mediacloud;

--
-- Name: schema_version_type; Type: TYPE; Schema: public; Owner: mediacloud
--

CREATE TYPE public.schema_version_type AS ENUM (
    'auto',
    'manual'
);


ALTER TYPE public.schema_version_type OWNER TO mediacloud;

--
-- Name: snap_period_type; Type: TYPE; Schema: public; Owner: mediacloud
--

CREATE TYPE public.snap_period_type AS ENUM (
    'overall',
    'weekly',
    'monthly',
    'custom'
);


ALTER TYPE public.snap_period_type OWNER TO mediacloud;

--
-- Name: topic_permission; Type: TYPE; Schema: public; Owner: mediacloud
--

CREATE TYPE public.topic_permission AS ENUM (
    'read',
    'write',
    'admin'
);


ALTER TYPE public.topic_permission OWNER TO mediacloud;

--
-- Name: topics_job_queue_type; Type: TYPE; Schema: public; Owner: mediacloud
--

CREATE TYPE public.topics_job_queue_type AS ENUM (
    'mc',
    'public'
);


ALTER TYPE public.topics_job_queue_type OWNER TO mediacloud;

--
-- Name: purge_object_caches(); Type: FUNCTION; Schema: cache; Owner: mediacloud
--

CREATE FUNCTION cache.purge_object_caches() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

    RAISE NOTICE 'Purging "s3_raw_downloads_cache" table...';
    EXECUTE '
        DELETE FROM cache.s3_raw_downloads_cache
        WHERE db_row_last_updated <= NOW() - INTERVAL ''3 days'';
    ';

    RAISE NOTICE 'Purging "extractor_results_cache" table...';
    EXECUTE '
        DELETE FROM cache.extractor_results_cache
        WHERE db_row_last_updated <= NOW() - INTERVAL ''3 days'';
    ';

END;
$$;


ALTER FUNCTION cache.purge_object_caches() OWNER TO mediacloud;

--
-- Name: update_cache_db_row_last_updated(); Type: FUNCTION; Schema: cache; Owner: mediacloud
--

CREATE FUNCTION cache.update_cache_db_row_last_updated() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.db_row_last_updated = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION cache.update_cache_db_row_last_updated() OWNER TO mediacloud;

--
-- Name: FUNCTION update_cache_db_row_last_updated(); Type: COMMENT; Schema: cache; Owner: mediacloud
--

COMMENT ON FUNCTION cache.update_cache_db_row_last_updated() IS 'Trigger 
to update "db_row_last_updated" for cache tables';


--
-- Name: add_normalized_title_hash(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.add_normalized_title_hash() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    if ( TG_OP = 'update' ) then
        if ( OLD.title = NEW.title ) then
            return new;
        end if;
    end if;

    select into NEW.normalized_title_hash md5( get_normalized_title( NEW.title, NEW.media_id ) )::uuid;

    return new;

END

$$;


ALTER FUNCTION public.add_normalized_title_hash() OWNER TO mediacloud;

--
-- Name: auth_user_api_keys_add_non_ip_limited_api_key(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.auth_user_api_keys_add_non_ip_limited_api_key() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    INSERT INTO auth_user_api_keys (auth_users_id, api_key, ip_address)
    VALUES (
        NEW.auth_users_id,
        DEFAULT,  -- Autogenerated API key
        NULL      -- Not limited by IP address
    );
    RETURN NULL;

END;
$$;


ALTER FUNCTION public.auth_user_api_keys_add_non_ip_limited_api_key() OWNER TO mediacloud;

--
-- Name: auth_user_limits_weekly_usage(public.citext); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.auth_user_limits_weekly_usage(user_email public.citext) RETURNS TABLE(email public.citext, weekly_requests_sum bigint, weekly_requested_items_sum bigint)
    LANGUAGE sql
    AS $_$

    SELECT auth_users.email,
           COALESCE(SUM(auth_user_request_daily_counts.requests_count), 0) AS weekly_requests_sum,
           COALESCE(SUM(auth_user_request_daily_counts.requested_items_count), 0) AS weekly_requested_items_sum
    FROM auth_users
        LEFT JOIN auth_user_request_daily_counts
            ON auth_users.email = auth_user_request_daily_counts.email
            AND auth_user_request_daily_counts.day > DATE_TRUNC('day', NOW())::date - INTERVAL '1 week'
    WHERE auth_users.email = $1
    GROUP BY auth_users.email;

$_$;


ALTER FUNCTION public.auth_user_limits_weekly_usage(user_email public.citext) OWNER TO mediacloud;

--
-- Name: auth_users_set_default_limits(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.auth_users_set_default_limits() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    INSERT INTO auth_user_limits (auth_users_id) VALUES (NEW.auth_users_id);
    RETURN NULL;

END;
$$;


ALTER FUNCTION public.auth_users_set_default_limits() OWNER TO mediacloud;

--
-- Name: create_missing_partitions(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.create_missing_partitions() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

    -- We have to create "downloads" partitions before "download_texts" ones
    -- because "download_texts" will have a foreign key reference to
    -- "downloads_success_content"

    RAISE NOTICE 'Creating partitions in "downloads_success_content" table...';
    PERFORM downloads_success_content_create_partitions();

    RAISE NOTICE 'Creating partitions in "downloads_success_feed" table...';
    PERFORM downloads_success_feed_create_partitions();

    RAISE NOTICE 'Creating partitions in "download_texts" table...';
    PERFORM download_texts_create_partitions();

    RAISE NOTICE 'Creating partitions in "stories_tags_map_p" table...';
    PERFORM stories_tags_map_create_partitions();

    RAISE NOTICE 'Creating partitions in "story_sentences_p" table...';
    PERFORM story_sentences_create_partitions();

    RAISE NOTICE 'Creating partitions in "feeds_stories_map_p" table...';
    PERFORM feeds_stories_map_create_partitions();

END;
$$;


ALTER FUNCTION public.create_missing_partitions() OWNER TO mediacloud;

--
-- Name: download_texts_create_partitions(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.download_texts_create_partitions() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_downloads_id_create_partitions('download_texts'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Adding foreign key to created partition "%"...', partition;
        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || partition || '_downloads_id_fkey
                FOREIGN KEY (downloads_id)
                REFERENCES ' || REPLACE(partition, 'download_texts', 'downloads_success_content') || ' (downloads_id)
                ON DELETE CASCADE;
        ';

        RAISE NOTICE 'Adding trigger to created partition "%"...', partition;
        EXECUTE '
            CREATE TRIGGER ' || partition || '_test_referenced_download_trigger
                BEFORE INSERT OR UPDATE ON ' || partition || '
                FOR EACH ROW
                EXECUTE PROCEDURE test_referenced_download_trigger(''downloads_id'');
        ';

    END LOOP;

END;
$$;


ALTER FUNCTION public.download_texts_create_partitions() OWNER TO mediacloud;

--
-- Name: FUNCTION download_texts_create_partitions(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.download_texts_create_partitions() IS 'Create missing "download_texts" partitions';


--
-- Name: downloads_create_subpartitions(text); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.downloads_create_subpartitions(base_table_name text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_downloads_id_create_partitions(base_table_name));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;

        EXECUTE '
            CREATE TRIGGER ' || partition || '_test_referenced_download_trigger
                BEFORE INSERT OR UPDATE ON ' || partition || '
                FOR EACH ROW
                EXECUTE PROCEDURE test_referenced_download_trigger(''parent'');
        ';

    END LOOP;

END;
$$;


ALTER FUNCTION public.downloads_create_subpartitions(base_table_name text) OWNER TO mediacloud;

--
-- Name: FUNCTION downloads_create_subpartitions(base_table_name text); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.downloads_create_subpartitions(base_table_name text) IS 'Create 
subpartitions of "downloads_success_feed" or "downloads_success_content"';


--
-- Name: downloads_success_content_create_partitions(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.downloads_success_content_create_partitions() RETURNS void
    LANGUAGE sql
    AS $$

    SELECT downloads_create_subpartitions('downloads_success_content');

$$;


ALTER FUNCTION public.downloads_success_content_create_partitions() OWNER TO mediacloud;

--
-- Name: FUNCTION downloads_success_content_create_partitions(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.downloads_success_content_create_partitions() IS 'Create 
missing "downloads_success_content" partitions';


--
-- Name: downloads_success_feed_create_partitions(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.downloads_success_feed_create_partitions() RETURNS void
    LANGUAGE sql
    AS $$

    SELECT downloads_create_subpartitions('downloads_success_feed');

$$;


ALTER FUNCTION public.downloads_success_feed_create_partitions() OWNER TO mediacloud;

--
-- Name: FUNCTION downloads_success_feed_create_partitions(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.downloads_success_feed_create_partitions() IS 'Create missing 
"downloads_success_feed" partitions';


--
-- Name: feed_is_stale(integer); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.feed_is_stale(param_feeds_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN

    -- Check if feed exists at all
    IF NOT EXISTS (
        SELECT 1
        FROM feeds
        WHERE feeds.feeds_id = param_feeds_id
    ) THEN
        RAISE EXCEPTION 'Feed % does not exist.', param_feeds_id;
        RETURN FALSE;
    END IF;

    -- Check if feed is active
    IF EXISTS (
        SELECT 1
        FROM feeds
        WHERE feeds.feeds_id = param_feeds_id
          AND (
              feeds.last_new_story_time IS NULL
           OR feeds.last_new_story_time < NOW() - INTERVAL '6 months'
          )
    ) THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;

END;
$$;


ALTER FUNCTION public.feed_is_stale(param_feeds_id integer) OWNER TO mediacloud;

--
-- Name: FUNCTION feed_is_stale(param_feeds_id integer); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.feed_is_stale(param_feeds_id integer) IS '-- Feed is "stale" (has not provided a new story in some time)
-- Not to be confused with "stale feeds" in extractor!';


--
-- Name: feeds_stories_map_create_partitions(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.feeds_stories_map_create_partitions() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_stories_id_create_partitions('feeds_stories_map_p'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;

        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_feeds_id_fkey
                FOREIGN KEY (feeds_id) REFERENCES feeds (feeds_id) MATCH FULL ON DELETE CASCADE;

            CREATE UNIQUE INDEX ' || partition || '_feeds_id_stories_id
                ON ' || partition || ' (feeds_id, stories_id);

            CREATE INDEX ' || partition || '_stories_id
                ON ' || partition || ' (stories_id);
        ';

    END LOOP;

END;
$$;


ALTER FUNCTION public.feeds_stories_map_create_partitions() OWNER TO mediacloud;

--
-- Name: FUNCTION feeds_stories_map_create_partitions(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.feeds_stories_map_create_partitions() IS 'Create missing 
"feeds_stories_map_p" partitions';


--
-- Name: feeds_stories_map_p_insert_trigger(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.feeds_stories_map_p_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "feeds_stories_map_01")
BEGIN
    SELECT partition_by_stories_id_partition_name(
        base_table_name := 'feeds_stories_map_p',
        stories_id := NEW.stories_id
    ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ' USING NEW;
    RETURN NULL;
END;
$_$;


ALTER FUNCTION public.feeds_stories_map_p_insert_trigger() OWNER TO mediacloud;

--
-- Name: FUNCTION feeds_stories_map_p_insert_trigger(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.feeds_stories_map_p_insert_trigger() IS 'Note: "INSERT ... RETURNING *" does not 
work with the trigger, please use "feeds_stories_map" view instead. target_table_name 
= partition table name (e.g. "feeds_stories_map_01")';


--
-- Name: feeds_stories_map_view_insert_update_delete(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.feeds_stories_map_view_insert_update_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- By INSERTing into the master table, we're letting triggers choose
        -- the correct partition.
        INSERT INTO feeds_stories_map_p SELECT NEW.*;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE feeds_stories_map_p
            SET feeds_id = NEW.feeds_id,
                stories_id = NEW.stories_id
            WHERE feeds_id = OLD.feeds_id
              AND stories_id = OLD.stories_id;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        DELETE FROM feeds_stories_map_p
            WHERE feeds_id = OLD.feeds_id
              AND stories_id = OLD.stories_id;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$;


ALTER FUNCTION public.feeds_stories_map_view_insert_update_delete() OWNER TO mediacloud;

--
-- Name: FUNCTION feeds_stories_map_view_insert_update_delete(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.feeds_stories_map_view_insert_update_delete() IS 'Trigger that 
implements INSERT / UPDATE / DELETE behavior on "feeds_stories_map" view. By INSERTing 
into the master table (feeds_stories_map_p), we are letting triggers choose the correct partition.';


--
-- Name: generate_api_key(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.generate_api_key() RETURNS character varying
    LANGUAGE plpgsql
    AS $$
DECLARE
    api_key VARCHAR(64);
BEGIN
    -- pgcrypto's functions are being referred with public schema prefix to make pg_upgrade work
    SELECT encode(public.digest(public.gen_random_bytes(256), 'sha256'), 'hex') INTO api_key;
    RETURN api_key;
END;
$$;


ALTER FUNCTION public.generate_api_key() OWNER TO mediacloud;

--
-- Name: get_domain_web_requests_lock(text, double precision); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.get_domain_web_requests_lock(domain_arg text, domain_timeout_arg double precision) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
begin

-- we don't want this table to grow forever or to have to manage it externally, so just truncate about every
-- 1 million requests.  only do this if there are more than 1000 rows in the table so that unit tests will not
-- randomly fail.
if ( select random() * 1000000 ) <  1 then
    if exists ( select 1 from domain_web_requests offset 1000 ) then
        truncate table domain_web_requests;
    end if;
end if;

if exists (
    select *
        from domain_web_requests
        where
            domain = domain_arg and
            extract( epoch from now() - request_time ) < domain_timeout_arg
    ) then

    return false;
end if;

delete from domain_web_requests where domain = domain_arg;
insert into domain_web_requests (domain) select domain_arg;

return true;
end
$$;


ALTER FUNCTION public.get_domain_web_requests_lock(domain_arg text, domain_timeout_arg double precision) OWNER TO mediacloud;

--
-- Name: FUNCTION get_domain_web_requests_lock(domain_arg text, domain_timeout_arg double precision); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.get_domain_web_requests_lock(domain_arg text, domain_timeout_arg double precision) IS 'return 
false if there is a request for the given domain within the last domain_timeout_arg milliseconds.  otherwise
return true and insert a row into domain_web_request for the domain.  this function does not lock the table and
so may allow some parallel requests through. we do not want this table to grow forever or to have to manage 
it externally, so just truncate about every 1 million requests.  only do this if there are more than 1000 rows 
in the table so that unit tests will not randomly fail.';


--
-- Name: get_normalized_title(text, integer); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.get_normalized_title(title text, title_media_id integer) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
        title_part text;
        media_title text;
begin

        -- stupid simple html stripper to avoid html messing up title_parts
        select into title regexp_replace(title, '<[^\<]*>', '', 'gi');
        select into title regexp_replace(title, '\&#?[a-z0-9]*', '', 'gi');

        select into title lower(title);
        select into title regexp_replace(title,'(?:\- )|[:|]', 'SEPSEP', 'g');
        select into title regexp_replace(title, '[[:punct:]]', '', 'g');
        select into title regexp_replace(title, '\s+', ' ', 'g');
        select into title substr(title, 0, 1024);

        if title_media_id = 0 then
            return title;
        end if;

        select into title_part part
            from ( select regexp_split_to_table(title, ' *SEPSEP *') part ) parts
            order by length(part) desc limit 1;

        if title_part = title then
            return title;
        end if;

        if length(title_part) < 32 then
            return title;
        end if;

        select into media_title get_normalized_title(name, 0) from media where media_id = title_media_id;
        if media_title = title_part then
            return title;
        end if;

        return title_part;
end
$$;


ALTER FUNCTION public.get_normalized_title(title text, title_media_id integer) OWNER TO mediacloud;

--
-- Name: FUNCTION get_normalized_title(title text, title_media_id integer); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.get_normalized_title(title text, title_media_id integer) IS 'get normalized story title by breaking the title into parts by 
the separator characters :-| and  using the longest single part. longest part must be at least 32 characters, 
cannot be the same as the media source name.  also remove all html, punctuation and repeated spaces, 
lowecase, and limit to 1024 characters.';


--
-- Name: half_md5(text); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.half_md5(string text) RETURNS bytea
    LANGUAGE sql
    AS $$
    -- pgcrypto's functions are being referred with public schema prefix to make pg_upgrade work
    SELECT SUBSTRING(public.digest(string, 'md5'::text), 0, 9);
$$;


ALTER FUNCTION public.half_md5(string text) OWNER TO mediacloud;

--
-- Name: FUNCTION half_md5(string text); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.half_md5(string text) IS 'Returns first 64 bits (16 characters) of MD5 hash; 
useful for reducing index sizes (e.g. in story_sentences.sentence) where 64 bits of entropy is not enough
pgcrypto functions are being referred with public schema prefix to make pg_upgrade work';


--
-- Name: insert_live_story(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.insert_live_story() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    begin

        insert into snap.live_stories
            ( topics_id, topic_stories_id, stories_id, media_id, url, guid, title, normalized_title_hash, description,
                publish_date, collect_date, full_text_rss, language )
            select NEW.topics_id, NEW.topic_stories_id, NEW.stories_id, s.media_id, s.url, s.guid,
                    s.title, s.normalized_title_hash, s.description, s.publish_date, s.collect_date, s.full_text_rss,
                    s.language
                from topic_stories cs
                    join stories s on ( cs.stories_id = s.stories_id )
                where
                    cs.stories_id = NEW.stories_id and
                    cs.topics_id = NEW.topics_id;

        return NEW;
    END;
$$;


ALTER FUNCTION public.insert_live_story() OWNER TO mediacloud;

--
-- Name: insert_platform_source_pair(text, text); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.insert_platform_source_pair(text, text) RETURNS void
    LANGUAGE sql
    AS $_$
    insert into topic_platforms_sources_map ( topic_platforms_id, topic_sources_id )
        select
                tp.topic_platforms_id,
                ts.topic_sources_id
            from
                topic_platforms tp
                cross join topic_sources ts
            where
                tp.name = $1  and
                ts.name = $2
$_$;


ALTER FUNCTION public.insert_platform_source_pair(text, text) OWNER TO mediacloud;

--
-- Name: FUNCTION insert_platform_source_pair(text, text); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.insert_platform_source_pair(text, text) IS 'easily create platform source pairs';


--
-- Name: insert_solr_import_story(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.insert_solr_import_story() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE

    queue_stories_id INT;

BEGIN

    IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
        select NEW.stories_id into queue_stories_id;
    ELSE
        select OLD.stories_id into queue_stories_id;
	END IF;

    insert into solr_import_stories ( stories_id )
        select queue_stories_id
            where exists (
                select 1 from processed_stories where stories_id = queue_stories_id
         );

    IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
		RETURN NEW;
	ELSE
		RETURN OLD;
	END IF;

END;

$$;


ALTER FUNCTION public.insert_solr_import_story() OWNER TO mediacloud;

--
-- Name: media_has_active_syndicated_feeds(integer); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.media_has_active_syndicated_feeds(param_media_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN

    -- Check if media exists
    IF NOT EXISTS (

        SELECT 1
        FROM media
        WHERE media_id = param_media_id

    ) THEN
        RAISE EXCEPTION 'Media % does not exist.', param_media_id;
        RETURN FALSE;
    END IF;

    -- Check if media has feeds
    IF EXISTS (

        SELECT 1
        FROM feeds
        WHERE media_id = param_media_id
          AND active = 't'

          -- Website might introduce RSS feeds later
          AND "type" = 'syndicated'

    ) THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;

END;
$$;


ALTER FUNCTION public.media_has_active_syndicated_feeds(param_media_id integer) OWNER TO mediacloud;

--
-- Name: FUNCTION media_has_active_syndicated_feeds(param_media_id integer); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.media_has_active_syndicated_feeds(param_media_id integer) IS 'true if media has active rss feeds';


--
-- Name: media_rescraping_add_initial_state_trigger(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.media_rescraping_add_initial_state_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
        INSERT INTO media_rescraping (media_id, disable, last_rescrape_time)
        VALUES (NEW.media_id, 'f', NULL);
        RETURN NEW;
   END;
$$;


ALTER FUNCTION public.media_rescraping_add_initial_state_trigger() OWNER TO mediacloud;

--
-- Name: FUNCTION media_rescraping_add_initial_state_trigger(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.media_rescraping_add_initial_state_trigger() IS 'Insert new rows to "media_rescraping" 
for each new row in "media"';


--
-- Name: partition_by_downloads_id_chunk_size(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.partition_by_downloads_id_chunk_size() RETURNS bigint
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN 100 * 1000 * 1000;   -- 100m downloads in each partition
END; $$;


ALTER FUNCTION public.partition_by_downloads_id_chunk_size() OWNER TO mediacloud;

--
-- Name: FUNCTION partition_by_downloads_id_chunk_size(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.partition_by_downloads_id_chunk_size() IS 'Return partition size for every table that is partitioned by "downloads_id"';


--
-- Name: partition_by_downloads_id_create_partitions(text); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.partition_by_downloads_id_create_partitions(base_table_name text) RETURNS SETOF text
    LANGUAGE plpgsql
    AS $$
DECLARE
    chunk_size INT;
    max_downloads_id BIGINT;
    partition_downloads_id BIGINT;

    -- Partition table name (e.g. "downloads_success_content_01")
    target_table_name TEXT;

    -- Partition table owner (e.g. "mediaclouduser")
    target_table_owner TEXT;

    -- "downloads_id" chunk lower limit, inclusive (e.g. 30,000,000)
    downloads_id_start BIGINT;

    -- "downloads_id" chunk upper limit, exclusive (e.g. 31,000,000)
    downloads_id_end BIGINT;
BEGIN

    SELECT partition_by_downloads_id_chunk_size() INTO chunk_size;

    -- Create +1 partition for future insertions
    SELECT COALESCE(MAX(downloads_id), 0) + chunk_size FROM downloads INTO max_downloads_id;

    SELECT 1 INTO partition_downloads_id;
    WHILE partition_downloads_id <= max_downloads_id LOOP
        SELECT partition_by_downloads_id_partition_name(
            base_table_name := base_table_name,
            downloads_id := partition_downloads_id
        ) INTO target_table_name;
        IF table_exists(target_table_name) THEN
            RAISE NOTICE 'Partition "%" for download ID % already exists.', target_table_name, partition_downloads_id;
        ELSE
            RAISE NOTICE 'Creating partition "%" for download ID %', target_table_name, partition_downloads_id;

            SELECT (partition_downloads_id / chunk_size) * chunk_size INTO downloads_id_start;
            SELECT ((partition_downloads_id / chunk_size) + 1) * chunk_size INTO downloads_id_end;

            -- Kill all autovacuums before proceeding with DDL changes
            PERFORM pid
            FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
            WHERE backend_type = 'autovacuum worker'
              AND query ~ 'downloads';

            EXECUTE '
                CREATE TABLE ' || target_table_name || '
                    PARTITION OF ' || base_table_name || '
                    FOR VALUES FROM (' || downloads_id_start || ')
                               TO   (' || downloads_id_end   || ');
            ';

            -- Update owner
            SELECT u.usename AS owner
            FROM information_schema.tables AS t
                JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
                JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
            WHERE t.table_name = base_table_name
              AND t.table_schema = 'public'
            INTO target_table_owner;

            EXECUTE '
                ALTER TABLE ' || target_table_name || '
                    OWNER TO ' || target_table_owner || ';
            ';

            -- Add created partition name to the list of returned partition names
            RETURN NEXT target_table_name;

        END IF;

        SELECT partition_downloads_id + chunk_size INTO partition_downloads_id;
    END LOOP;

    RETURN;

END;
$$;


ALTER FUNCTION public.partition_by_downloads_id_create_partitions(base_table_name text) OWNER TO mediacloud;

--
-- Name: FUNCTION partition_by_downloads_id_create_partitions(base_table_name text); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.partition_by_downloads_id_create_partitions(base_table_name text) IS 'Create 
missing partitions for tables partitioned by "downloads_id", returning a list of 
created partition tables';


--
-- Name: partition_by_downloads_id_partition_name(text, bigint); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.partition_by_downloads_id_partition_name(base_table_name text, downloads_id bigint) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN

    RETURN partition_name(
        base_table_name := base_table_name,
        chunk_size := partition_by_downloads_id_chunk_size(),
        object_id := downloads_id
    );

END;
$$;


ALTER FUNCTION public.partition_by_downloads_id_partition_name(base_table_name text, downloads_id bigint) OWNER TO mediacloud;

--
-- Name: FUNCTION partition_by_downloads_id_partition_name(base_table_name text, downloads_id bigint); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.partition_by_downloads_id_partition_name(base_table_name text, downloads_id bigint) IS 'Return 
partition table name for a given base table name and "downloads_id"';


--
-- Name: partition_by_stories_id_chunk_size(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.partition_by_stories_id_chunk_size() RETURNS bigint
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN 100 * 1000 * 1000;   -- 100m stories in each partition
END; $$;


ALTER FUNCTION public.partition_by_stories_id_chunk_size() OWNER TO mediacloud;

--
-- Name: FUNCTION partition_by_stories_id_chunk_size(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.partition_by_stories_id_chunk_size() IS 'Return partition size for every table 
that is partitioned by "stories_id"';


--
-- Name: partition_by_stories_id_create_partitions(text); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.partition_by_stories_id_create_partitions(base_table_name text) RETURNS SETOF text
    LANGUAGE plpgsql
    AS $$
DECLARE
    chunk_size INT;
    max_stories_id INT;
    partition_stories_id INT;

    -- Partition table name (e.g. "stories_tags_map_01")
    target_table_name TEXT;

    -- Partition table owner (e.g. "mediaclouduser")
    target_table_owner TEXT;

    -- "stories_id" chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_start BIGINT;

    -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
    stories_id_end BIGINT;
BEGIN

    SELECT partition_by_stories_id_chunk_size() INTO chunk_size;

    -- Create +1 partition for future insertions
    SELECT COALESCE(MAX(stories_id), 0) + chunk_size FROM stories INTO max_stories_id;

    SELECT 1 INTO partition_stories_id;
    WHILE partition_stories_id <= max_stories_id LOOP
        SELECT partition_by_stories_id_partition_name(
            base_table_name := base_table_name,
            stories_id := partition_stories_id
        ) INTO target_table_name;
        IF table_exists(target_table_name) THEN
            RAISE NOTICE 'Partition "%" for story ID % already exists.', target_table_name, partition_stories_id;
        ELSE
            RAISE NOTICE 'Creating partition "%" for story ID %', target_table_name, partition_stories_id;

            SELECT (partition_stories_id / chunk_size) * chunk_size INTO stories_id_start;
            SELECT ((partition_stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

            -- Kill all autovacuums before proceeding with DDL changes
            PERFORM pid
            FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
            WHERE backend_type = 'autovacuum worker'
              AND query ~ 'stories';

            EXECUTE '
                CREATE TABLE ' || target_table_name || ' (

                    PRIMARY KEY (' || base_table_name || '_id),

                    -- Partition by stories_id
                    CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id CHECK (
                        stories_id >= ''' || stories_id_start || '''
                    AND stories_id <  ''' || stories_id_end   || '''),

                    -- Foreign key to stories.stories_id
                    CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id_fkey
                        FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL ON DELETE CASCADE

                ) INHERITS (' || base_table_name || ');
            ';

            -- Update owner
            SELECT u.usename AS owner
            FROM information_schema.tables AS t
                JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
                JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
            WHERE t.table_name = base_table_name
              AND t.table_schema = 'public'
            INTO target_table_owner;

            EXECUTE 'ALTER TABLE ' || target_table_name || ' OWNER TO ' || target_table_owner || ';';

            -- Add created partition name to the list of returned partition names
            RETURN NEXT target_table_name;

        END IF;

        SELECT partition_stories_id + chunk_size INTO partition_stories_id;
    END LOOP;

    RETURN;

END;
$$;


ALTER FUNCTION public.partition_by_stories_id_create_partitions(base_table_name text) OWNER TO mediacloud;

--
-- Name: FUNCTION partition_by_stories_id_create_partitions(base_table_name text); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.partition_by_stories_id_create_partitions(base_table_name text) IS 'Create missing partitions for 
tables partitioned by "stories_id", returning a list of created partition tables';


--
-- Name: partition_by_stories_id_partition_name(text, bigint); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.partition_by_stories_id_partition_name(base_table_name text, stories_id bigint) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN

    RETURN partition_name(
        base_table_name := base_table_name,
        chunk_size := partition_by_stories_id_chunk_size(),
        object_id := stories_id
    );

END;
$$;


ALTER FUNCTION public.partition_by_stories_id_partition_name(base_table_name text, stories_id bigint) OWNER TO mediacloud;

--
-- Name: FUNCTION partition_by_stories_id_partition_name(base_table_name text, stories_id bigint); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.partition_by_stories_id_partition_name(base_table_name text, stories_id bigint) IS 'Return 
partition table name for a given base table name and "stories_id"';


--
-- Name: partition_name(text, bigint, bigint); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.partition_name(base_table_name text, chunk_size bigint, object_id bigint) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE

    -- Up to 100 partitions, suffixed as "_00", "_01" ..., "_99"
    -- (having more of them is not feasible)
    to_char_format CONSTANT TEXT := '00';

    -- Partition table name (e.g. "stories_tags_map_01")
    table_name TEXT;

    chunk_number INT;

BEGIN
    SELECT object_id / chunk_size INTO chunk_number;

    SELECT base_table_name || '_' || TRIM(leading ' ' FROM TO_CHAR(chunk_number, to_char_format))
        INTO table_name;

    RETURN table_name;
END;
$$;


ALTER FUNCTION public.partition_name(base_table_name text, chunk_size bigint, object_id bigint) OWNER TO mediacloud;

--
-- Name: pop_queued_download(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.pop_queued_download() RETURNS bigint
    LANGUAGE plpgsql
    AS $$

declare

    pop_downloads_id bigint;

begin

    select into pop_downloads_id downloads_id
        from queued_downloads
        order by downloads_id desc
        limit 1 for
        update skip locked;

    delete from queued_downloads where downloads_id = pop_downloads_id;

    return pop_downloads_id;
end;

$$;


ALTER FUNCTION public.pop_queued_download() OWNER TO mediacloud;

--
-- Name: FUNCTION pop_queued_download(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.pop_queued_download() IS 'do this as a plpgsql function 
because it wraps it in the necessary transaction without having to know whether 
the calling context is in a transaction';


--
-- Name: rescraping_changes(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.rescraping_changes() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    r_count RECORD;
    r_media RECORD;
    r_feed RECORD;
BEGIN

    -- Check if media exists
    IF NOT EXISTS (
        SELECT 1
        FROM feeds_from_yesterday
    ) THEN
        RAISE EXCEPTION '"feeds_from_yesterday" table is empty.';
    END IF;

    -- Fill temp. tables with changes to print out later
    CREATE TEMPORARY TABLE rescraping_changes_media ON COMMIT DROP AS
        SELECT *
        FROM media
        WHERE media_id IN (
            SELECT DISTINCT media_id
            FROM (
                -- Don't compare "name" because it's insignificant
                (
                    SELECT feeds_id, media_id, type, active, url FROM feeds_from_yesterday
                    EXCEPT
                    SELECT feeds_id, media_id, type, active, url FROM feeds
                ) UNION ALL (
                    SELECT feeds_id, media_id, type, active, url FROM feeds
                    EXCEPT
                    SELECT feeds_id, media_id, type, active, url FROM feeds_from_yesterday
                )
            ) AS modified_feeds
        );

    CREATE TEMPORARY TABLE rescraping_changes_feeds_added ON COMMIT DROP AS
        SELECT *
        FROM feeds
        WHERE media_id IN (
            SELECT media_id
            FROM rescraping_changes_media
          )
          AND feeds_id NOT IN (
            SELECT feeds_id
            FROM feeds_from_yesterday
        );

    CREATE TEMPORARY TABLE rescraping_changes_feeds_deleted ON COMMIT DROP AS
        SELECT *
        FROM feeds_from_yesterday
        WHERE media_id IN (
            SELECT media_id
            FROM rescraping_changes_media
          )
          AND feeds_id NOT IN (
            SELECT feeds_id
            FROM feeds
        );

    CREATE TEMPORARY TABLE rescraping_changes_feeds_modified ON COMMIT DROP AS
        SELECT feeds_before.media_id,
               feeds_before.feeds_id,

               feeds_before.name AS before_name,
               feeds_before.url AS before_url,
               feeds_before.type AS before_type,
               feeds_before.active AS before_active,

               feeds_after.name AS after_name,
               feeds_after.url AS after_url,
               feeds_after.type AS after_type,
               feeds_after.active AS after_active

        FROM feeds_from_yesterday AS feeds_before
            INNER JOIN feeds AS feeds_after ON (
                feeds_before.feeds_id = feeds_after.feeds_id
                AND (
                    -- Don't compare "name" because it's insignificant
                    feeds_before.url != feeds_after.url
                 OR feeds_before.type != feeds_after.type
                 OR feeds_before.active != feeds_after.active
                )
            )

        WHERE feeds_before.media_id IN (
            SELECT media_id
            FROM rescraping_changes_media
        );

    -- Print out changes
    RAISE NOTICE 'Changes between "feeds" and "feeds_from_yesterday":';
    RAISE NOTICE '';

    SELECT COUNT(1) AS media_count INTO r_count FROM rescraping_changes_media;
    RAISE NOTICE '* Modified media: %', r_count.media_count;
    SELECT COUNT(1) AS feeds_added_count INTO r_count FROM rescraping_changes_feeds_added;
    RAISE NOTICE '* Added feeds: %', r_count.feeds_added_count;
    SELECT COUNT(1) AS feeds_deleted_count INTO r_count FROM rescraping_changes_feeds_deleted;
    RAISE NOTICE '* Deleted feeds: %', r_count.feeds_deleted_count;
    SELECT COUNT(1) AS feeds_modified_count INTO r_count FROM rescraping_changes_feeds_modified;
    RAISE NOTICE '* Modified feeds: %', r_count.feeds_modified_count;
    RAISE NOTICE '';

    FOR r_media IN
        SELECT *,

        -- Prioritize US MSM media
        EXISTS (
            SELECT 1
            FROM tags AS tags
                INNER JOIN media_tags_map
                    ON tags.tags_id = media_tags_map.tags_id
                INNER JOIN tag_sets
                    ON tags.tag_sets_id = tag_sets.tag_sets_id
            WHERE media_tags_map.media_id = rescraping_changes_media.media_id
              AND tag_sets.name = 'collection'
              AND tags.tag = 'ap_english_us_top25_20100110'
        ) AS belongs_to_us_msm,

        -- Prioritize media with "show_on_media"
        EXISTS (
            SELECT 1
            FROM tags AS tags
                INNER JOIN media_tags_map
                    ON tags.tags_id = media_tags_map.tags_id
                INNER JOIN tag_sets
                    ON tags.tag_sets_id = tag_sets.tag_sets_id
            WHERE media_tags_map.media_id = rescraping_changes_media.media_id
              AND (
                tag_sets.show_on_media
                OR tags.show_on_media
              )
        ) AS show_on_media

        FROM rescraping_changes_media

        ORDER BY belongs_to_us_msm DESC,
                 show_on_media DESC,
                 media_id
    LOOP
        RAISE NOTICE 'MODIFIED media: media_id=%, name="%", url="%"',
            r_media.media_id,
            r_media.name,
            r_media.url;

        FOR r_feed IN
            SELECT *
            FROM rescraping_changes_feeds_added
            WHERE media_id = r_media.media_id
            ORDER BY feeds_id
        LOOP
            RAISE NOTICE '    ADDED feed: feeds_id=%, type=%, active=%, name="%", url="%"',
                r_feed.feeds_id,
                r_feed.type,
                r_feed.active,
                r_feed.name,
                r_feed.url;
        END LOOP;

        -- Feeds shouldn't get deleted but we're checking anyways
        FOR r_feed IN
            SELECT *
            FROM rescraping_changes_feeds_deleted
            WHERE media_id = r_media.media_id
            ORDER BY feeds_id
        LOOP
            RAISE NOTICE '    DELETED feed: feeds_id=%, type=%, active=%, name="%", url="%"',
                r_feed.feeds_id,
                r_feed.type,
                r_feed.active,
                r_feed.name,
                r_feed.url;
        END LOOP;

        FOR r_feed IN
            SELECT *
            FROM rescraping_changes_feeds_modified
            WHERE media_id = r_media.media_id
            ORDER BY feeds_id
        LOOP
            RAISE NOTICE '    MODIFIED feed: feeds_id=%', r_feed.feeds_id;
            RAISE NOTICE '        BEFORE: type=%, active=%, name="%", url="%"',
                r_feed.before_type,
                r_feed.before_active,
                r_feed.before_name,
                r_feed.before_url;
            RAISE NOTICE '        AFTER:  type=%, active=%, name="%", url="%"',
                r_feed.after_type,
                r_feed.after_active,
                r_feed.after_name,
                r_feed.after_url;
        END LOOP;

        RAISE NOTICE '';

    END LOOP;

END;
$$;


ALTER FUNCTION public.rescraping_changes() OWNER TO mediacloud;

--
-- Name: FUNCTION rescraping_changes(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.rescraping_changes() IS 'Print out a diff between "feeds" and "feeds_from_yesterday"';


--
-- Name: stories_tags_map_create_partitions(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.stories_tags_map_create_partitions() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_stories_id_create_partitions('stories_tags_map_p'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;

        -- Add extra foreign keys / constraints to the newly created partitions
        EXECUTE '
            ALTER TABLE ' || partition || '

                -- Foreign key to tags.tags_id
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_tags_id_fkey
                    FOREIGN KEY (tags_id) REFERENCES tags (tags_id) MATCH FULL ON DELETE CASCADE,

                -- Unique duplets
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_stories_id_tags_id_unique
                    UNIQUE (stories_id, tags_id);
        ';

    END LOOP;

END;
$$;


ALTER FUNCTION public.stories_tags_map_create_partitions() OWNER TO mediacloud;

--
-- Name: FUNCTION stories_tags_map_create_partitions(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.stories_tags_map_create_partitions() IS 'Create missing "stories_tags_map" 
partitions, add extra foreign keys / constraints to the newly created partitions';


--
-- Name: stories_tags_map_p_upsert_trigger(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.stories_tags_map_p_upsert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "stories_tags_map_01")
BEGIN
    SELECT partition_by_stories_id_partition_name(
        base_table_name := 'stories_tags_map_p',
        stories_id := NEW.stories_id
    ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ON CONFLICT (stories_id, tags_id) DO NOTHING
        ' USING NEW;
    RETURN NULL;
END;
$_$;


ALTER FUNCTION public.stories_tags_map_p_upsert_trigger() OWNER TO mediacloud;

--
-- Name: FUNCTION stories_tags_map_p_upsert_trigger(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.stories_tags_map_p_upsert_trigger() IS 'Upsert row into correct partition';


--
-- Name: stories_tags_map_view_insert_update_delete(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.stories_tags_map_view_insert_update_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- By INSERTing into the master table, we're letting triggers choose
        -- the correct partition.
        INSERT INTO stories_tags_map_p SELECT NEW.*;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE stories_tags_map_p
            SET stories_id = NEW.stories_id,
                tags_id = NEW.tags_id
            WHERE stories_id = OLD.stories_id
              AND tags_id = OLD.tags_id;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        DELETE FROM stories_tags_map_p
            WHERE stories_id = OLD.stories_id
              AND tags_id = OLD.tags_id;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$;


ALTER FUNCTION public.stories_tags_map_view_insert_update_delete() OWNER TO mediacloud;

--
-- Name: FUNCTION stories_tags_map_view_insert_update_delete(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.stories_tags_map_view_insert_update_delete() IS 'Trigger 
that implements INSERT / UPDATE / DELETE behavior on "stories_tags_map" view. By 
INSERTing into the master table, we are letting triggers choose the correct partition.';


--
-- Name: story_is_english_and_has_sentences(integer); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.story_is_english_and_has_sentences(param_stories_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    story record;
BEGIN

    SELECT stories_id, media_id, language INTO story from stories where stories_id = param_stories_id;

    IF NOT ( story.language = 'en' or story.language is null ) THEN
        RETURN FALSE;

    ELSEIF NOT EXISTS ( SELECT 1 FROM story_sentences WHERE stories_id = param_stories_id ) THEN
        RETURN FALSE;

    END IF;

    RETURN TRUE;

END;
$$;


ALTER FUNCTION public.story_is_english_and_has_sentences(param_stories_id integer) OWNER TO mediacloud;

--
-- Name: story_sentences_create_partitions(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.story_sentences_create_partitions() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT partition_by_stories_id_create_partitions('story_sentences_p'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;

        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_media_id_fkey
                FOREIGN KEY (media_id) REFERENCES media (media_id) MATCH FULL ON DELETE CASCADE;

            CREATE UNIQUE INDEX ' || partition || '_stories_id_sentence_number
                ON ' || partition || ' (stories_id, sentence_number);

            CREATE INDEX ' || partition || '_sentence_media_week
                ON ' || partition || ' (half_md5(sentence), media_id, week_start_date(publish_date::date));
        ';

    END LOOP;

END;
$$;


ALTER FUNCTION public.story_sentences_create_partitions() OWNER TO mediacloud;

--
-- Name: FUNCTION story_sentences_create_partitions(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.story_sentences_create_partitions() IS 'Create missing "story_sentences_p" partitions';


--
-- Name: story_sentences_p_insert_trigger(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.story_sentences_p_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "stories_tags_map_01")
BEGIN
    SELECT partition_by_stories_id_partition_name(
        base_table_name := 'story_sentences_p',
        stories_id := NEW.stories_id
    ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ' USING NEW;
    RETURN NULL;
END;
$_$;


ALTER FUNCTION public.story_sentences_p_insert_trigger() OWNER TO mediacloud;

--
-- Name: FUNCTION story_sentences_p_insert_trigger(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.story_sentences_p_insert_trigger() IS 'Note: "INSERT ... RETURNING *" 
does not work with the trigger, please use "story_sentences" view instead';


--
-- Name: story_sentences_view_insert_update_delete(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.story_sentences_view_insert_update_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- By INSERTing into the master table, we're letting triggers choose
        -- the correct partition.
        INSERT INTO story_sentences_p SELECT NEW.*;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        UPDATE story_sentences_p
            SET stories_id = NEW.stories_id,
                sentence_number = NEW.sentence_number,
                sentence = NEW.sentence,
                media_id = NEW.media_id,
                publish_date = NEW.publish_date,
                language = NEW.language,
                is_dup = NEW.is_dup
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        DELETE FROM story_sentences_p
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$;


ALTER FUNCTION public.story_sentences_view_insert_update_delete() OWNER TO mediacloud;

--
-- Name: FUNCTION story_sentences_view_insert_update_delete(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.story_sentences_view_insert_update_delete() IS 'Trigger that 
implements INSERT / UPDATE / DELETE behavior on "story_sentences" view. By INSERTing 
into the master table, we are letting triggers choose the correct partition.';


--
-- Name: table_exists(character varying); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.table_exists(target_table_name character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    schema_position INT;
    schema VARCHAR;
BEGIN

    SELECT POSITION('.' IN target_table_name) INTO schema_position;

    -- "." at string index 0 would return position 1
    IF schema_position = 0 THEN
        schema := CURRENT_SCHEMA();
    ELSE
        schema := SUBSTRING(target_table_name FROM 1 FOR schema_position - 1);
        target_table_name := SUBSTRING(target_table_name FROM schema_position + 1);
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = schema
          AND table_name = target_table_name
    );

END;
$$;


ALTER FUNCTION public.table_exists(target_table_name character varying) OWNER TO mediacloud;

--
-- Name: FUNCTION table_exists(target_table_name character varying); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.table_exists(target_table_name character varying) IS 'Returns true if table exists 
(and user has access to it). Table name might be with ("public.stories") or without ("stories") schema.';


--
-- Name: test_referenced_download_trigger(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.test_referenced_download_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    param_column_name TEXT;
    param_downloads_id BIGINT;
BEGIN

    IF TG_NARGS != 1 THEN
        RAISE EXCEPTION 'Trigger should be called with an column name argument.';
    END IF;

    SELECT TG_ARGV[0] INTO param_column_name;
    SELECT to_json(NEW) ->> param_column_name INTO param_downloads_id;

    -- Might be NULL, e.g. downloads.parent
    IF (param_downloads_id IS NOT NULL) THEN

        IF NOT EXISTS (
            SELECT 1
            FROM downloads
            WHERE downloads_id = param_downloads_id
        ) THEN
            RAISE EXCEPTION 'Referenced download ID % from column "%" does not exist in "downloads".', param_downloads_id, param_column_name;
        END IF;

    END IF;

    RETURN NEW;

END;
$$;


ALTER FUNCTION public.test_referenced_download_trigger() OWNER TO mediacloud;

--
-- Name: FUNCTION test_referenced_download_trigger(); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.test_referenced_download_trigger() IS 'Imitate a foreign key by testing if a download 
with an INSERTed / UPDATEd "downloads_id" exists in "downloads." Partitioned tables do not support foreign 
keys being pointed to them, so this trigger achieves the same referential integrity for tables that point 
to "downloads". Column name from NEW (NEW.<column_name>) that contains the INSERTed / UPDATEd "downloads_id" 
should be passed as an trigger argument.';


--
-- Name: update_feeds_from_yesterday(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.update_feeds_from_yesterday() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

    DELETE FROM feeds_from_yesterday;
    INSERT INTO feeds_from_yesterday (feeds_id, media_id, name, url, type, active)
        SELECT feeds_id, media_id, name, url, type, active
        FROM feeds;

END;
$$;


ALTER FUNCTION public.update_feeds_from_yesterday() OWNER TO mediacloud;

--
-- Name: update_live_story(); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.update_live_story() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    begin

        update snap.live_stories set
                media_id = NEW.media_id,
                url = NEW.url,
                guid = NEW.guid,
                title = NEW.title,
                normalized_title_hash = NEW.normalized_title_hash,
                description = NEW.description,
                publish_date = NEW.publish_date,
                collect_date = NEW.collect_date,
                full_text_rss = NEW.full_text_rss,
                language = NEW.language
            where
                stories_id = NEW.stories_id;

        return NEW;
    END;
$$;


ALTER FUNCTION public.update_live_story() OWNER TO mediacloud;

--
-- Name: week_start_date(date); Type: FUNCTION; Schema: public; Owner: mediacloud
--

CREATE FUNCTION public.week_start_date(day date) RETURNS date
    LANGUAGE plpgsql IMMUTABLE COST 10
    AS $$
DECLARE
    date_trunc_result date;
BEGIN
    date_trunc_result := date_trunc('week', day::timestamp);
    RETURN date_trunc_result;
END;
$$;


ALTER FUNCTION public.week_start_date(day date) OWNER TO mediacloud;

--
-- Name: FUNCTION week_start_date(day date); Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON FUNCTION public.week_start_date(day date) IS 'Need b/c date_trunc("week", date) is not immutable; 
see http://www.mentby.com/Group/pgsql-general/datetrunc-on-date-is-immutable.html';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: extractor_results_cache; Type: TABLE; Schema: cache; Owner: mediacloud
--

CREATE UNLOGGED TABLE cache.extractor_results_cache (
    extractor_results_cache_id integer NOT NULL,
    extracted_html text,
    extracted_text text,
    downloads_id bigint NOT NULL,
    db_row_last_updated timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE ONLY cache.extractor_results_cache ALTER COLUMN extracted_html SET STORAGE EXTERNAL;
ALTER TABLE ONLY cache.extractor_results_cache ALTER COLUMN extracted_text SET STORAGE EXTERNAL;


ALTER TABLE cache.extractor_results_cache OWNER TO mediacloud;

--
-- Name: TABLE extractor_results_cache; Type: COMMENT; Schema: cache; Owner: mediacloud
--

COMMENT ON TABLE cache.extractor_results_cache IS 'Cached extractor results for 
extraction jobs with use_cache set to true';


--
-- Name: COLUMN extractor_results_cache.db_row_last_updated; Type: COMMENT; Schema: cache; Owner: mediacloud
--

COMMENT ON COLUMN cache.extractor_results_cache.db_row_last_updated IS 'Will be used to purge old cache objects; 
do not forget to update cache.purge_object_caches()';


--
-- Name: extractor_results_cache_extractor_results_cache_id_seq; Type: SEQUENCE; Schema: cache; Owner: mediacloud
--

CREATE SEQUENCE cache.extractor_results_cache_extractor_results_cache_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE cache.extractor_results_cache_extractor_results_cache_id_seq OWNER TO mediacloud;

--
-- Name: extractor_results_cache_extractor_results_cache_id_seq; Type: SEQUENCE OWNED BY; Schema: cache; Owner: mediacloud
--

ALTER SEQUENCE cache.extractor_results_cache_extractor_results_cache_id_seq OWNED BY cache.extractor_results_cache.extractor_results_cache_id;


--
-- Name: s3_raw_downloads_cache; Type: TABLE; Schema: cache; Owner: mediacloud
--

CREATE UNLOGGED TABLE cache.s3_raw_downloads_cache (
    s3_raw_downloads_cache_id integer NOT NULL,
    object_id bigint NOT NULL,
    db_row_last_updated timestamp with time zone DEFAULT now() NOT NULL,
    raw_data bytea NOT NULL
);
ALTER TABLE ONLY cache.s3_raw_downloads_cache ALTER COLUMN raw_data SET STORAGE EXTERNAL;


ALTER TABLE cache.s3_raw_downloads_cache OWNER TO mediacloud;

--
-- Name: COLUMN s3_raw_downloads_cache.object_id; Type: COMMENT; Schema: cache; Owner: mediacloud
--

COMMENT ON COLUMN cache.s3_raw_downloads_cache.object_id IS '"downloads_id" from "downloads"';


--
-- Name: COLUMN s3_raw_downloads_cache.db_row_last_updated; Type: COMMENT; Schema: cache; Owner: mediacloud
--

COMMENT ON COLUMN cache.s3_raw_downloads_cache.db_row_last_updated IS 'Will be used to purge old cache objects; 
do not forget to update cache.purge_object_caches()';


--
-- Name: s3_raw_downloads_cache_s3_raw_downloads_cache_id_seq; Type: SEQUENCE; Schema: cache; Owner: mediacloud
--

CREATE SEQUENCE cache.s3_raw_downloads_cache_s3_raw_downloads_cache_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE cache.s3_raw_downloads_cache_s3_raw_downloads_cache_id_seq OWNER TO mediacloud;

--
-- Name: s3_raw_downloads_cache_s3_raw_downloads_cache_id_seq; Type: SEQUENCE OWNED BY; Schema: cache; Owner: mediacloud
--

ALTER SEQUENCE cache.s3_raw_downloads_cache_s3_raw_downloads_cache_id_seq OWNED BY cache.s3_raw_downloads_cache.s3_raw_downloads_cache_id;


--
-- Name: activities; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.activities (
    activities_id integer NOT NULL,
    name character varying(255) NOT NULL,
    creation_date timestamp without time zone DEFAULT LOCALTIMESTAMP NOT NULL,
    user_identifier public.citext NOT NULL,
    object_id bigint,
    reason text,
    description_json text DEFAULT '{ }'::text NOT NULL,
    CONSTRAINT activities_name_can_not_contain_spaces CHECK (((name)::text !~~ '% %'::text))
);


ALTER TABLE public.activities OWNER TO mediacloud;

--
-- Name: COLUMN activities.name; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.activities.name IS 'activity name, e.g. "tm_snapshot_topic"';


--
-- Name: COLUMN activities.object_id; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.activities.object_id IS 'Indexed ID of the object that was modified 
in some way by the activity';


--
-- Name: COLUMN activities.reason; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.activities.reason IS 'user-provided reason why the activity was made';


--
-- Name: COLUMN activities.description_json; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.activities.description_json IS 'Other free-form data describing the 
action in the JSON format (e.g.: { "field": "name", "old_value": "Foo.", "new_value": "Bar." }).
FIXME: has potential to use JSON type instead of TEXT in PostgreSQL 9.2+';


--
-- Name: activities_activities_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.activities_activities_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.activities_activities_id_seq OWNER TO mediacloud;

--
-- Name: activities_activities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.activities_activities_id_seq OWNED BY public.activities.activities_id;


--
-- Name: api_links; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.api_links (
    api_links_id bigint NOT NULL,
    path text NOT NULL,
    params_json text NOT NULL,
    next_link_id bigint,
    previous_link_id bigint
);


ALTER TABLE public.api_links OWNER TO mediacloud;

--
-- Name: TABLE api_links; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.api_links IS 'implements link_id as documented in the topics api spec';


--
-- Name: api_links_api_links_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.api_links_api_links_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.api_links_api_links_id_seq OWNER TO mediacloud;

--
-- Name: api_links_api_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.api_links_api_links_id_seq OWNED BY public.api_links.api_links_id;


--
-- Name: auth_roles; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.auth_roles (
    auth_roles_id integer NOT NULL,
    role text NOT NULL,
    description text NOT NULL,
    CONSTRAINT role_name_can_not_contain_spaces CHECK ((role !~~ '% %'::text))
);


ALTER TABLE public.auth_roles OWNER TO mediacloud;

--
-- Name: auth_roles_auth_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.auth_roles_auth_roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_roles_auth_roles_id_seq OWNER TO mediacloud;

--
-- Name: auth_roles_auth_roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.auth_roles_auth_roles_id_seq OWNED BY public.auth_roles.auth_roles_id;


--
-- Name: auth_user_api_keys; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.auth_user_api_keys (
    auth_user_api_keys_id integer NOT NULL,
    auth_users_id integer NOT NULL,
    api_key character varying(64) DEFAULT public.generate_api_key() NOT NULL,
    ip_address inet,
    CONSTRAINT api_key_64_characters CHECK ((length((api_key)::text) = 64))
);


ALTER TABLE public.auth_user_api_keys OWNER TO mediacloud;

--
-- Name: COLUMN auth_user_api_keys.api_key; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.auth_user_api_keys.api_key IS 'must  be 64 bytes in order to prevent someone 
from resetting it to empty string somehow';


--
-- Name: auth_user_api_keys_auth_user_api_keys_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.auth_user_api_keys_auth_user_api_keys_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_user_api_keys_auth_user_api_keys_id_seq OWNER TO mediacloud;

--
-- Name: auth_user_api_keys_auth_user_api_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.auth_user_api_keys_auth_user_api_keys_id_seq OWNED BY public.auth_user_api_keys.auth_user_api_keys_id;


--
-- Name: auth_user_limits; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.auth_user_limits (
    auth_user_limits_id integer NOT NULL,
    auth_users_id integer NOT NULL,
    weekly_requests_limit integer DEFAULT 10000 NOT NULL,
    weekly_requested_items_limit integer DEFAULT 100000 NOT NULL,
    max_topic_stories integer DEFAULT 100000 NOT NULL
);


ALTER TABLE public.auth_user_limits OWNER TO mediacloud;

--
-- Name: TABLE auth_user_limits; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.auth_user_limits IS 'User limits for logged + throttled controller actions';


--
-- Name: COLUMN auth_user_limits.weekly_requests_limit; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.auth_user_limits.weekly_requests_limit IS 'Request limit (0 or belonging to 
"admin"/"admin-readonly" group = no limit)';


--
-- Name: auth_user_limits_auth_user_limits_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.auth_user_limits_auth_user_limits_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_user_limits_auth_user_limits_id_seq OWNER TO mediacloud;

--
-- Name: auth_user_limits_auth_user_limits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.auth_user_limits_auth_user_limits_id_seq OWNED BY public.auth_user_limits.auth_user_limits_id;


--
-- Name: auth_user_request_daily_counts; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.auth_user_request_daily_counts (
    auth_user_request_daily_counts_id integer NOT NULL,
    email public.citext NOT NULL,
    day date NOT NULL,
    requests_count integer NOT NULL,
    requested_items_count integer NOT NULL
);


ALTER TABLE public.auth_user_request_daily_counts OWNER TO mediacloud;

--
-- Name: auth_user_request_daily_count_auth_user_request_daily_count_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.auth_user_request_daily_count_auth_user_request_daily_count_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_user_request_daily_count_auth_user_request_daily_count_seq OWNER TO mediacloud;

--
-- Name: auth_user_request_daily_count_auth_user_request_daily_count_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.auth_user_request_daily_count_auth_user_request_daily_count_seq OWNED BY public.auth_user_request_daily_counts.auth_user_request_daily_counts_id;


--
-- Name: auth_users; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.auth_users (
    auth_users_id integer NOT NULL,
    email public.citext NOT NULL,
    password_hash text NOT NULL,
    full_name text NOT NULL,
    notes text,
    active boolean DEFAULT true NOT NULL,
    password_reset_token_hash text,
    last_unsuccessful_login_attempt timestamp without time zone DEFAULT '1970-01-01 00:00:00'::timestamp without time zone NOT NULL,
    created_date timestamp without time zone DEFAULT now() NOT NULL,
    has_consented boolean DEFAULT false NOT NULL,
    CONSTRAINT password_hash_sha256 CHECK ((length(password_hash) = 137)),
    CONSTRAINT password_reset_token_hash_sha256 CHECK (((length(password_reset_token_hash) = 137) OR (password_reset_token_hash IS NULL)))
);


ALTER TABLE public.auth_users OWNER TO mediacloud;

--
-- Name: COLUMN auth_users.email; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.auth_users.email IS 'Emails are case-insensitive';


--
-- Name: COLUMN auth_users.password_hash; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.auth_users.password_hash IS 'salted hash of a password';


--
-- Name: COLUMN auth_users.password_reset_token_hash; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.auth_users.password_reset_token_hash IS 'Salted hash of a 
password reset token (with Crypt::SaltedHash, algorithm => "SHA-256", salt_len=>64) or NULL';


--
-- Name: COLUMN auth_users.has_consented; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.auth_users.has_consented IS 'Whether user has consented to the privacy policy';


--
-- Name: auth_users_auth_users_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.auth_users_auth_users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_users_auth_users_id_seq OWNER TO mediacloud;

--
-- Name: auth_users_auth_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.auth_users_auth_users_id_seq OWNED BY public.auth_users.auth_users_id;


--
-- Name: auth_users_roles_map; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.auth_users_roles_map (
    auth_users_roles_map_id integer NOT NULL,
    auth_users_id integer NOT NULL,
    auth_roles_id integer NOT NULL
);


ALTER TABLE public.auth_users_roles_map OWNER TO mediacloud;

--
-- Name: auth_users_roles_map_auth_users_roles_map_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.auth_users_roles_map_auth_users_roles_map_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_users_roles_map_auth_users_roles_map_id_seq OWNER TO mediacloud;

--
-- Name: auth_users_roles_map_auth_users_roles_map_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.auth_users_roles_map_auth_users_roles_map_id_seq OWNED BY public.auth_users_roles_map.auth_users_roles_map_id;


--
-- Name: auth_users_tag_sets_permissions; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.auth_users_tag_sets_permissions (
    auth_users_tag_sets_permissions_id integer NOT NULL,
    auth_users_id integer NOT NULL,
    tag_sets_id integer NOT NULL,
    apply_tags boolean NOT NULL,
    create_tags boolean NOT NULL,
    edit_tag_set_descriptors boolean NOT NULL,
    edit_tag_descriptors boolean NOT NULL
);


ALTER TABLE public.auth_users_tag_sets_permissions OWNER TO mediacloud;

--
-- Name: auth_users_tag_sets_permissio_auth_users_tag_sets_permissio_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.auth_users_tag_sets_permissio_auth_users_tag_sets_permissio_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_users_tag_sets_permissio_auth_users_tag_sets_permissio_seq OWNER TO mediacloud;

--
-- Name: auth_users_tag_sets_permissio_auth_users_tag_sets_permissio_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.auth_users_tag_sets_permissio_auth_users_tag_sets_permissio_seq OWNED BY public.auth_users_tag_sets_permissions.auth_users_tag_sets_permissions_id;


--
-- Name: celery_groups; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.celery_groups (
    id bigint NOT NULL,
    taskset_id character varying(155),
    result bytea,
    date_done timestamp without time zone
);


ALTER TABLE public.celery_groups OWNER TO mediacloud;

--
-- Name: TABLE celery_groups; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.celery_groups IS 'Celery job results (configured as self.__app.conf.database_table_names; 
schema is dictated by Celery + SQLAlchemy)';


--
-- Name: celery_tasks; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.celery_tasks (
    id bigint NOT NULL,
    task_id character varying(155),
    status character varying(50),
    result bytea,
    date_done timestamp without time zone,
    traceback text
);


ALTER TABLE public.celery_tasks OWNER TO mediacloud;

--
-- Name: cliff_annotations; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.cliff_annotations (
    cliff_annotations_id integer NOT NULL,
    object_id integer NOT NULL,
    raw_data bytea NOT NULL
);
ALTER TABLE ONLY public.cliff_annotations ALTER COLUMN raw_data SET STORAGE EXTERNAL;


ALTER TABLE public.cliff_annotations OWNER TO mediacloud;

--
-- Name: cliff_annotations_cliff_annotations_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.cliff_annotations_cliff_annotations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.cliff_annotations_cliff_annotations_id_seq OWNER TO mediacloud;

--
-- Name: cliff_annotations_cliff_annotations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.cliff_annotations_cliff_annotations_id_seq OWNED BY public.cliff_annotations.cliff_annotations_id;


--
-- Name: color_sets; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.color_sets (
    color_sets_id integer NOT NULL,
    color character varying(256) NOT NULL,
    color_set character varying(256) NOT NULL,
    id character varying(256) NOT NULL
);


ALTER TABLE public.color_sets OWNER TO mediacloud;

--
-- Name: color_sets_color_sets_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.color_sets_color_sets_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.color_sets_color_sets_id_seq OWNER TO mediacloud;

--
-- Name: color_sets_color_sets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.color_sets_color_sets_id_seq OWNED BY public.color_sets.color_sets_id;


--
-- Name: topics; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topics (
    topics_id integer NOT NULL,
    name character varying(1024) NOT NULL,
    pattern text,
    solr_seed_query text,
    solr_seed_query_run boolean DEFAULT false NOT NULL,
    description text NOT NULL,
    media_type_tag_sets_id integer,
    max_iterations integer DEFAULT 15 NOT NULL,
    state text DEFAULT 'created but not queued'::text NOT NULL,
    message text,
    is_public boolean DEFAULT false NOT NULL,
    is_logogram boolean DEFAULT false NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    respider_stories boolean DEFAULT false NOT NULL,
    respider_start_date date,
    respider_end_date date,
    snapshot_periods text,
    platform character varying(1024) NOT NULL,
    mode character varying(1024) DEFAULT 'web'::character varying NOT NULL,
    job_queue public.topics_job_queue_type NOT NULL,
    max_stories integer NOT NULL,
    is_story_index_ready boolean DEFAULT true NOT NULL,
    only_snapshot_engaged_stories boolean DEFAULT false NOT NULL
);


ALTER TABLE public.topics OWNER TO mediacloud;

--
-- Name: COLUMN topics.respider_stories; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.topics.respider_stories IS 'if true, the topic_stories 
associated with this topic wilbe set to link_mined = "f" on the next mining job';


--
-- Name: COLUMN topics.snapshot_periods; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.topics.snapshot_periods IS 'space-separated list of periods to snapshot';


--
-- Name: COLUMN topics.platform; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.topics.platform IS 'platform that topic is analyzing';


--
-- Name: COLUMN topics.mode; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.topics.mode IS 'mode of analysis';


--
-- Name: COLUMN topics.job_queue; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.topics.job_queue IS 'job queue to use for spider and snapshot jobs for this topic';


--
-- Name: COLUMN topics.is_story_index_ready; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.topics.is_story_index_ready IS 'if false, we should refuse to spider 
this topic because the use has not confirmed the new story query syntax';


--
-- Name: COLUMN topics.only_snapshot_engaged_stories; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.topics.only_snapshot_engaged_stories IS 'if true, snapshots 
are pruned to only stories with a minimum level of engagements (links, shares, etc)';


--
-- Name: controversies; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.controversies AS
 SELECT topics.topics_id AS controversies_id,
    topics.topics_id,
    topics.name,
    topics.pattern,
    topics.solr_seed_query,
    topics.solr_seed_query_run,
    topics.description,
    topics.media_type_tag_sets_id,
    topics.max_iterations,
    topics.state,
    topics.message,
    topics.is_public,
    topics.is_logogram,
    topics.start_date,
    topics.end_date,
    topics.respider_stories,
    topics.respider_start_date,
    topics.respider_end_date,
    topics.snapshot_periods,
    topics.platform,
    topics.mode,
    topics.job_queue,
    topics.max_stories,
    topics.is_story_index_ready,
    topics.only_snapshot_engaged_stories
   FROM public.topics;


ALTER TABLE public.controversies OWNER TO mediacloud;

--
-- Name: timespans; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.timespans (
    timespans_id integer NOT NULL,
    snapshots_id integer,
    archive_snapshots_id integer,
    foci_id integer,
    start_date timestamp without time zone NOT NULL,
    end_date timestamp without time zone NOT NULL,
    period public.snap_period_type NOT NULL,
    model_r2_mean double precision,
    model_r2_stddev double precision,
    model_num_media integer,
    story_count integer NOT NULL,
    story_link_count integer NOT NULL,
    medium_count integer NOT NULL,
    medium_link_count integer NOT NULL,
    post_count integer NOT NULL,
    tags_id integer,
    CONSTRAINT timespans_check CHECK ((((snapshots_id IS NULL) AND (archive_snapshots_id IS NOT NULL)) OR ((snapshots_id IS NOT NULL) AND (archive_snapshots_id IS NULL))))
);


ALTER TABLE public.timespans OWNER TO mediacloud;

--
-- Name: COLUMN timespans.snapshots_id; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.timespans.snapshots_id IS 'individual timespans within a snapshot';


--
-- Name: COLUMN timespans.archive_snapshots_id; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.timespans.archive_snapshots_id IS 'timespan is an archived part of 
this snapshot (and thus mostly not visible)';


--
-- Name: COLUMN timespans.tags_id; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.timespans.tags_id IS 'keep on cascade to avoid accidental deletion';


--
-- Name: controversy_dump_time_slices; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.controversy_dump_time_slices AS
 SELECT timespans.timespans_id AS controversy_dump_time_slices_id,
    timespans.snapshots_id AS controversy_dumps_id,
    timespans.foci_id AS controversy_query_slices_id,
    timespans.timespans_id,
    timespans.snapshots_id,
    timespans.archive_snapshots_id,
    timespans.foci_id,
    timespans.start_date,
    timespans.end_date,
    timespans.period,
    timespans.model_r2_mean,
    timespans.model_r2_stddev,
    timespans.model_num_media,
    timespans.story_count,
    timespans.story_link_count,
    timespans.medium_count,
    timespans.medium_link_count,
    timespans.post_count,
    timespans.tags_id
   FROM public.timespans;


ALTER TABLE public.controversy_dump_time_slices OWNER TO mediacloud;

--
-- Name: snapshots; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.snapshots (
    snapshots_id integer NOT NULL,
    topics_id integer NOT NULL,
    snapshot_date timestamp without time zone NOT NULL,
    start_date timestamp without time zone NOT NULL,
    end_date timestamp without time zone NOT NULL,
    note text,
    state text DEFAULT 'queued'::text NOT NULL,
    message text,
    searchable boolean DEFAULT false NOT NULL,
    bot_policy public.bot_policy_type,
    seed_queries jsonb
);


ALTER TABLE public.snapshots OWNER TO mediacloud;

--
-- Name: controversy_dumps; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.controversy_dumps AS
 SELECT snapshots.snapshots_id AS controversy_dumps_id,
    snapshots.topics_id AS controversies_id,
    snapshots.snapshot_date AS dump_date,
    snapshots.snapshots_id,
    snapshots.topics_id,
    snapshots.snapshot_date,
    snapshots.start_date,
    snapshots.end_date,
    snapshots.note,
    snapshots.state,
    snapshots.message,
    snapshots.searchable,
    snapshots.bot_policy,
    snapshots.seed_queries
   FROM public.snapshots;


ALTER TABLE public.controversy_dumps OWNER TO mediacloud;

--
-- Name: downloads; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.downloads (
    downloads_id bigint NOT NULL,
    feeds_id integer NOT NULL,
    stories_id integer,
    parent bigint,
    url text NOT NULL,
    host text NOT NULL,
    download_time timestamp without time zone DEFAULT now() NOT NULL,
    type public.download_type NOT NULL,
    state public.download_state NOT NULL,
    path text,
    error_message text,
    priority smallint NOT NULL,
    sequence smallint NOT NULL,
    extracted boolean DEFAULT false NOT NULL
)
PARTITION BY LIST (state);


ALTER TABLE public.downloads OWNER TO mediacloud;

--
-- Name: downloads_in_past_day; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.downloads_in_past_day AS
 SELECT downloads.downloads_id,
    downloads.feeds_id,
    downloads.stories_id,
    downloads.parent,
    downloads.url,
    downloads.host,
    downloads.download_time,
    downloads.type,
    downloads.state,
    downloads.path,
    downloads.error_message,
    downloads.priority,
    downloads.sequence,
    downloads.extracted
   FROM public.downloads
  WHERE (downloads.download_time > (now() - '1 day'::interval));


ALTER TABLE public.downloads_in_past_day OWNER TO mediacloud;

--
-- Name: downloads_to_be_extracted; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.downloads_to_be_extracted AS
 SELECT downloads.downloads_id,
    downloads.feeds_id,
    downloads.stories_id,
    downloads.parent,
    downloads.url,
    downloads.host,
    downloads.download_time,
    downloads.type,
    downloads.state,
    downloads.path,
    downloads.error_message,
    downloads.priority,
    downloads.sequence,
    downloads.extracted
   FROM public.downloads
  WHERE ((downloads.extracted = false) AND (downloads.state = 'success'::public.download_state) AND (downloads.type = 'content'::public.download_type));


ALTER TABLE public.downloads_to_be_extracted OWNER TO mediacloud;

--
-- Name: downloads_with_error_in_past_day; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.downloads_with_error_in_past_day AS
 SELECT downloads_in_past_day.downloads_id,
    downloads_in_past_day.feeds_id,
    downloads_in_past_day.stories_id,
    downloads_in_past_day.parent,
    downloads_in_past_day.url,
    downloads_in_past_day.host,
    downloads_in_past_day.download_time,
    downloads_in_past_day.type,
    downloads_in_past_day.state,
    downloads_in_past_day.path,
    downloads_in_past_day.error_message,
    downloads_in_past_day.priority,
    downloads_in_past_day.sequence,
    downloads_in_past_day.extracted
   FROM public.downloads_in_past_day
  WHERE (downloads_in_past_day.state = 'error'::public.download_state);


ALTER TABLE public.downloads_with_error_in_past_day OWNER TO mediacloud;

--
-- Name: solr_imports; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.solr_imports (
    solr_imports_id integer NOT NULL,
    import_date timestamp without time zone NOT NULL,
    full_import boolean DEFAULT false NOT NULL,
    num_stories bigint
);


ALTER TABLE public.solr_imports OWNER TO mediacloud;

--
-- Name: stories; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.stories (
    stories_id integer NOT NULL,
    media_id integer NOT NULL,
    url character varying(1024) NOT NULL,
    guid character varying(1024) NOT NULL,
    title text NOT NULL,
    normalized_title_hash uuid,
    description text,
    publish_date timestamp without time zone,
    collect_date timestamp without time zone DEFAULT now() NOT NULL,
    full_text_rss boolean DEFAULT false NOT NULL,
    language character varying(3)
);


ALTER TABLE public.stories OWNER TO mediacloud;

--
-- Name: TABLE stories; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.stories IS 'stories (news articles)';


--
-- Name: COLUMN stories.language; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.stories.language IS '2- or 3-character ISO 690 
language code; empty if unknown, NULL if unset';


--
-- Name: stories_collected_in_past_day; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.stories_collected_in_past_day AS
 SELECT stories.stories_id,
    stories.media_id,
    stories.url,
    stories.guid,
    stories.title,
    stories.normalized_title_hash,
    stories.description,
    stories.publish_date,
    stories.collect_date,
    stories.full_text_rss,
    stories.language
   FROM public.stories
  WHERE (stories.collect_date > (now() - '1 day'::interval));


ALTER TABLE public.stories_collected_in_past_day OWNER TO mediacloud;

--
-- Name: daily_stats; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.daily_stats AS
 SELECT dd.daily_downloads,
    ds.daily_stories,
    dex.downloads_to_be_extracted,
    er.download_errors,
    si.solr_stories
   FROM ( SELECT count(*) AS daily_downloads
           FROM public.downloads_in_past_day) dd,
    ( SELECT count(*) AS daily_stories
           FROM public.stories_collected_in_past_day) ds,
    ( SELECT count(*) AS downloads_to_be_extracted
           FROM public.downloads_to_be_extracted) dex,
    ( SELECT count(*) AS download_errors
           FROM public.downloads_with_error_in_past_day) er,
    ( SELECT COALESCE(sum(solr_imports.num_stories), (0)::numeric) AS solr_stories
           FROM public.solr_imports
          WHERE (solr_imports.import_date > (now() - '1 day'::interval))) si;


ALTER TABLE public.daily_stats OWNER TO mediacloud;

--
-- Name: database_variables; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.database_variables (
    database_variables_id integer NOT NULL,
    name character varying(512) NOT NULL,
    value character varying(1024) NOT NULL
);


ALTER TABLE public.database_variables OWNER TO mediacloud;

--
-- Name: database_variables_database_variables_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.database_variables_database_variables_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.database_variables_database_variables_id_seq OWNER TO mediacloud;

--
-- Name: database_variables_database_variables_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.database_variables_database_variables_id_seq OWNED BY public.database_variables.database_variables_id;


--
-- Name: domain_web_requests; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE UNLOGGED TABLE public.domain_web_requests (
    domain text NOT NULL,
    request_time timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.domain_web_requests OWNER TO mediacloud;

--
-- Name: TABLE domain_web_requests; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.domain_web_requests IS 'keep track of per domain web requests so that we can throttle them 
using mediawords.util.web.user_agent.throttled. this is unlogged because we do not care about anything more 
than about 10 seconds old.  we do not have a primary key because we want it just to be a fast table for 
temporary storage.';


--
-- Name: download_texts; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.download_texts (
    download_texts_id bigint NOT NULL,
    downloads_id bigint NOT NULL,
    download_text text NOT NULL,
    download_text_length integer NOT NULL,
    CONSTRAINT download_texts_length_is_correct CHECK ((length(download_text) = download_text_length))
)
PARTITION BY RANGE (downloads_id);


ALTER TABLE public.download_texts OWNER TO mediacloud;

--
-- Name: download_texts_download_texts_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.download_texts_download_texts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.download_texts_download_texts_id_seq OWNER TO mediacloud;

--
-- Name: download_texts_download_texts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.download_texts_download_texts_id_seq OWNED BY public.download_texts.download_texts_id;


--
-- Name: download_texts_00; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.download_texts_00 (
    download_texts_id bigint DEFAULT nextval('public.download_texts_download_texts_id_seq'::regclass) NOT NULL,
    downloads_id bigint NOT NULL,
    download_text text NOT NULL,
    download_text_length integer NOT NULL,
    CONSTRAINT download_texts_length_is_correct CHECK ((length(download_text) = download_text_length))
);
ALTER TABLE ONLY public.download_texts ATTACH PARTITION public.download_texts_00 FOR VALUES FROM ('0') TO ('100000000');


ALTER TABLE public.download_texts_00 OWNER TO mediacloud;

--
-- Name: downloads_downloads_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.downloads_downloads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.downloads_downloads_id_seq OWNER TO mediacloud;

--
-- Name: downloads_downloads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.downloads_downloads_id_seq OWNED BY public.downloads.downloads_id;


--
-- Name: downloads_error; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.downloads_error (
    downloads_id bigint DEFAULT nextval('public.downloads_downloads_id_seq'::regclass) NOT NULL,
    feeds_id integer NOT NULL,
    stories_id integer,
    parent bigint,
    url text NOT NULL,
    host text NOT NULL,
    download_time timestamp without time zone DEFAULT now() NOT NULL,
    type public.download_type NOT NULL,
    state public.download_state NOT NULL,
    path text,
    error_message text,
    priority smallint NOT NULL,
    sequence smallint NOT NULL,
    extracted boolean DEFAULT false NOT NULL
);
ALTER TABLE ONLY public.downloads ATTACH PARTITION public.downloads_error FOR VALUES IN ('error');


ALTER TABLE public.downloads_error OWNER TO mediacloud;

--
-- Name: downloads_feed_error; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.downloads_feed_error (
    downloads_id bigint DEFAULT nextval('public.downloads_downloads_id_seq'::regclass) NOT NULL,
    feeds_id integer NOT NULL,
    stories_id integer,
    parent bigint,
    url text NOT NULL,
    host text NOT NULL,
    download_time timestamp without time zone DEFAULT now() NOT NULL,
    type public.download_type NOT NULL,
    state public.download_state NOT NULL,
    path text,
    error_message text,
    priority smallint NOT NULL,
    sequence smallint NOT NULL,
    extracted boolean DEFAULT false NOT NULL
);
ALTER TABLE ONLY public.downloads ATTACH PARTITION public.downloads_feed_error FOR VALUES IN ('feed_error');


ALTER TABLE public.downloads_feed_error OWNER TO mediacloud;

--
-- Name: downloads_fetching; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.downloads_fetching (
    downloads_id bigint DEFAULT nextval('public.downloads_downloads_id_seq'::regclass) NOT NULL,
    feeds_id integer NOT NULL,
    stories_id integer,
    parent bigint,
    url text NOT NULL,
    host text NOT NULL,
    download_time timestamp without time zone DEFAULT now() NOT NULL,
    type public.download_type NOT NULL,
    state public.download_state NOT NULL,
    path text,
    error_message text,
    priority smallint NOT NULL,
    sequence smallint NOT NULL,
    extracted boolean DEFAULT false NOT NULL
);
ALTER TABLE ONLY public.downloads ATTACH PARTITION public.downloads_fetching FOR VALUES IN ('fetching');


ALTER TABLE public.downloads_fetching OWNER TO mediacloud;

--
-- Name: feeds; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.feeds (
    feeds_id integer NOT NULL,
    media_id integer NOT NULL,
    name character varying(512) NOT NULL,
    url character varying(1024) NOT NULL,
    type public.feed_type DEFAULT 'syndicated'::public.feed_type NOT NULL,
    active boolean DEFAULT true NOT NULL,
    last_checksum text,
    last_attempted_download_time timestamp with time zone,
    last_successful_download_time timestamp with time zone,
    last_new_story_time timestamp with time zone
);


ALTER TABLE public.feeds OWNER TO mediacloud;

--
-- Name: downloads_media; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.downloads_media AS
 SELECT d.downloads_id,
    d.feeds_id,
    d.stories_id,
    d.parent,
    d.url,
    d.host,
    d.download_time,
    d.type,
    d.state,
    d.path,
    d.error_message,
    d.priority,
    d.sequence,
    d.extracted,
    f.media_id AS _media_id
   FROM public.downloads d,
    public.feeds f
  WHERE (d.feeds_id = f.feeds_id);


ALTER TABLE public.downloads_media OWNER TO mediacloud;

--
-- Name: downloads_non_media; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.downloads_non_media AS
 SELECT d.downloads_id,
    d.feeds_id,
    d.stories_id,
    d.parent,
    d.url,
    d.host,
    d.download_time,
    d.type,
    d.state,
    d.path,
    d.error_message,
    d.priority,
    d.sequence,
    d.extracted
   FROM public.downloads d
  WHERE (d.feeds_id IS NULL);


ALTER TABLE public.downloads_non_media OWNER TO mediacloud;

--
-- Name: downloads_pending; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.downloads_pending (
    downloads_id bigint DEFAULT nextval('public.downloads_downloads_id_seq'::regclass) NOT NULL,
    feeds_id integer NOT NULL,
    stories_id integer,
    parent bigint,
    url text NOT NULL,
    host text NOT NULL,
    download_time timestamp without time zone DEFAULT now() NOT NULL,
    type public.download_type NOT NULL,
    state public.download_state NOT NULL,
    path text,
    error_message text,
    priority smallint NOT NULL,
    sequence smallint NOT NULL,
    extracted boolean DEFAULT false NOT NULL
);
ALTER TABLE ONLY public.downloads ATTACH PARTITION public.downloads_pending FOR VALUES IN ('pending');


ALTER TABLE public.downloads_pending OWNER TO mediacloud;

--
-- Name: downloads_success; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.downloads_success (
    downloads_id bigint DEFAULT nextval('public.downloads_downloads_id_seq'::regclass) NOT NULL,
    feeds_id integer NOT NULL,
    stories_id integer,
    parent bigint,
    url text NOT NULL,
    host text NOT NULL,
    download_time timestamp without time zone DEFAULT now() NOT NULL,
    type public.download_type NOT NULL,
    state public.download_state NOT NULL,
    path text,
    error_message text,
    priority smallint NOT NULL,
    sequence smallint NOT NULL,
    extracted boolean DEFAULT false NOT NULL,
    CONSTRAINT downloads_success_path_not_null CHECK ((path IS NOT NULL))
)
PARTITION BY LIST (type);
ALTER TABLE ONLY public.downloads ATTACH PARTITION public.downloads_success FOR VALUES IN ('success');


ALTER TABLE public.downloads_success OWNER TO mediacloud;

--
-- Name: downloads_success_content; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.downloads_success_content (
    downloads_id bigint DEFAULT nextval('public.downloads_downloads_id_seq'::regclass) NOT NULL,
    feeds_id integer NOT NULL,
    stories_id integer,
    parent bigint,
    url text NOT NULL,
    host text NOT NULL,
    download_time timestamp without time zone DEFAULT now() NOT NULL,
    type public.download_type NOT NULL,
    state public.download_state NOT NULL,
    path text,
    error_message text,
    priority smallint NOT NULL,
    sequence smallint NOT NULL,
    extracted boolean DEFAULT false NOT NULL,
    CONSTRAINT downloads_success_content_stories_id_not_null CHECK ((stories_id IS NOT NULL)),
    CONSTRAINT downloads_success_path_not_null CHECK ((path IS NOT NULL))
)
PARTITION BY RANGE (downloads_id);
ALTER TABLE ONLY public.downloads_success ATTACH PARTITION public.downloads_success_content FOR VALUES IN ('content');


ALTER TABLE public.downloads_success_content OWNER TO mediacloud;

--
-- Name: downloads_success_content_00; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.downloads_success_content_00 (
    downloads_id bigint DEFAULT nextval('public.downloads_downloads_id_seq'::regclass) NOT NULL,
    feeds_id integer NOT NULL,
    stories_id integer,
    parent bigint,
    url text NOT NULL,
    host text NOT NULL,
    download_time timestamp without time zone DEFAULT now() NOT NULL,
    type public.download_type NOT NULL,
    state public.download_state NOT NULL,
    path text,
    error_message text,
    priority smallint NOT NULL,
    sequence smallint NOT NULL,
    extracted boolean DEFAULT false NOT NULL,
    CONSTRAINT downloads_success_content_stories_id_not_null CHECK ((stories_id IS NOT NULL)),
    CONSTRAINT downloads_success_path_not_null CHECK ((path IS NOT NULL))
);
ALTER TABLE ONLY public.downloads_success_content ATTACH PARTITION public.downloads_success_content_00 FOR VALUES FROM ('0') TO ('100000000');


ALTER TABLE public.downloads_success_content_00 OWNER TO mediacloud;

--
-- Name: downloads_success_feed; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.downloads_success_feed (
    downloads_id bigint DEFAULT nextval('public.downloads_downloads_id_seq'::regclass) NOT NULL,
    feeds_id integer NOT NULL,
    stories_id integer,
    parent bigint,
    url text NOT NULL,
    host text NOT NULL,
    download_time timestamp without time zone DEFAULT now() NOT NULL,
    type public.download_type NOT NULL,
    state public.download_state NOT NULL,
    path text,
    error_message text,
    priority smallint NOT NULL,
    sequence smallint NOT NULL,
    extracted boolean DEFAULT false NOT NULL,
    CONSTRAINT downloads_success_feed_stories_id_null CHECK ((stories_id IS NULL)),
    CONSTRAINT downloads_success_path_not_null CHECK ((path IS NOT NULL))
)
PARTITION BY RANGE (downloads_id);
ALTER TABLE ONLY public.downloads_success ATTACH PARTITION public.downloads_success_feed FOR VALUES IN ('feed');


ALTER TABLE public.downloads_success_feed OWNER TO mediacloud;

--
-- Name: downloads_success_feed_00; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.downloads_success_feed_00 (
    downloads_id bigint DEFAULT nextval('public.downloads_downloads_id_seq'::regclass) NOT NULL,
    feeds_id integer NOT NULL,
    stories_id integer,
    parent bigint,
    url text NOT NULL,
    host text NOT NULL,
    download_time timestamp without time zone DEFAULT now() NOT NULL,
    type public.download_type NOT NULL,
    state public.download_state NOT NULL,
    path text,
    error_message text,
    priority smallint NOT NULL,
    sequence smallint NOT NULL,
    extracted boolean DEFAULT false NOT NULL,
    CONSTRAINT downloads_success_feed_stories_id_null CHECK ((stories_id IS NULL)),
    CONSTRAINT downloads_success_path_not_null CHECK ((path IS NOT NULL))
);
ALTER TABLE ONLY public.downloads_success_feed ATTACH PARTITION public.downloads_success_feed_00 FOR VALUES FROM ('0') TO ('100000000');


ALTER TABLE public.downloads_success_feed_00 OWNER TO mediacloud;

--
-- Name: scraped_feeds; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.scraped_feeds (
    feed_scrapes_id integer NOT NULL,
    feeds_id integer NOT NULL,
    scrape_date timestamp without time zone DEFAULT now() NOT NULL,
    import_module text NOT NULL
);


ALTER TABLE public.scraped_feeds OWNER TO mediacloud;

--
-- Name: TABLE scraped_feeds; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.scraped_feeds IS 'dates on which feeds have been scraped with MediaWords::ImportStories 
and the module used for scraping';


--
-- Name: feedly_unscraped_feeds; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.feedly_unscraped_feeds AS
 SELECT f.feeds_id,
    f.media_id,
    f.name,
    f.url,
    f.type,
    f.active,
    f.last_checksum,
    f.last_attempted_download_time,
    f.last_successful_download_time,
    f.last_new_story_time
   FROM (public.feeds f
     LEFT JOIN public.scraped_feeds sf ON (((f.feeds_id = sf.feeds_id) AND (sf.import_module = 'MediaWords::ImportStories::Feedly'::text))))
  WHERE ((f.type = 'syndicated'::public.feed_type) AND (f.active = true) AND (sf.feeds_id IS NULL));


ALTER TABLE public.feedly_unscraped_feeds OWNER TO mediacloud;

--
-- Name: feeds_after_rescraping; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.feeds_after_rescraping (
    feeds_after_rescraping_id integer NOT NULL,
    media_id integer NOT NULL,
    name character varying(512) NOT NULL,
    url character varying(1024) NOT NULL,
    type public.feed_type DEFAULT 'syndicated'::public.feed_type NOT NULL
);


ALTER TABLE public.feeds_after_rescraping OWNER TO mediacloud;

--
-- Name: TABLE feeds_after_rescraping; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.feeds_after_rescraping IS 'feeds for media item discovered after (re)scraping';


--
-- Name: feeds_after_rescraping_feeds_after_rescraping_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.feeds_after_rescraping_feeds_after_rescraping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.feeds_after_rescraping_feeds_after_rescraping_id_seq OWNER TO mediacloud;

--
-- Name: feeds_after_rescraping_feeds_after_rescraping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.feeds_after_rescraping_feeds_after_rescraping_id_seq OWNED BY public.feeds_after_rescraping.feeds_after_rescraping_id;


--
-- Name: feeds_feeds_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.feeds_feeds_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.feeds_feeds_id_seq OWNER TO mediacloud;

--
-- Name: feeds_feeds_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.feeds_feeds_id_seq OWNED BY public.feeds.feeds_id;


--
-- Name: feeds_from_yesterday; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.feeds_from_yesterday (
    feeds_id integer NOT NULL,
    media_id integer NOT NULL,
    name character varying(512) NOT NULL,
    url character varying(1024) NOT NULL,
    type public.feed_type NOT NULL,
    active boolean NOT NULL
);


ALTER TABLE public.feeds_from_yesterday OWNER TO mediacloud;

--
-- Name: TABLE feeds_from_yesterday; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.feeds_from_yesterday IS 'Copy of "feeds" table from yesterday; 
used for generating reports for rescraping efforts';


--
-- Name: feeds_stories_map_p; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.feeds_stories_map_p (
    feeds_stories_map_p_id bigint NOT NULL,
    feeds_id integer NOT NULL,
    stories_id integer NOT NULL
);


ALTER TABLE public.feeds_stories_map_p OWNER TO mediacloud;

--
-- Name: TABLE feeds_stories_map_p; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.feeds_stories_map_p IS '"Master" table (no indexes, no foreign keys as 
they will be ineffective)';


--
-- Name: COLUMN feeds_stories_map_p.feeds_stories_map_p_id; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.feeds_stories_map_p.feeds_stories_map_p_id IS 'PRIMARY KEY on master table 
needed for database handler primary_key_column() method to work';


--
-- Name: feeds_stories_map; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.feeds_stories_map AS
 SELECT feeds_stories_map_p.feeds_stories_map_p_id AS feeds_stories_map_id,
    feeds_stories_map_p.feeds_id,
    feeds_stories_map_p.stories_id
   FROM public.feeds_stories_map_p;


ALTER TABLE public.feeds_stories_map OWNER TO mediacloud;

--
-- Name: VIEW feeds_stories_map; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON VIEW public.feeds_stories_map IS 'Proxy view to "feeds_stories_map_p" 
to make RETURNING work with partitioned tables
 (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)';


--
-- Name: feeds_stories_map_p_00; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.feeds_stories_map_p_00 (
    CONSTRAINT feeds_stories_map_p_00_stories_id CHECK (((stories_id >= 0) AND (stories_id < 100000000)))
)
INHERITS (public.feeds_stories_map_p);


ALTER TABLE public.feeds_stories_map_p_00 OWNER TO mediacloud;

--
-- Name: feeds_stories_map_p_feeds_stories_map_p_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.feeds_stories_map_p_feeds_stories_map_p_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.feeds_stories_map_p_feeds_stories_map_p_id_seq OWNER TO mediacloud;

--
-- Name: feeds_stories_map_p_feeds_stories_map_p_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.feeds_stories_map_p_feeds_stories_map_p_id_seq OWNED BY public.feeds_stories_map_p.feeds_stories_map_p_id;


--
-- Name: feeds_tags_map; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.feeds_tags_map (
    feeds_tags_map_id integer NOT NULL,
    feeds_id integer NOT NULL,
    tags_id integer NOT NULL
);


ALTER TABLE public.feeds_tags_map OWNER TO mediacloud;

--
-- Name: feeds_tags_map_feeds_tags_map_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.feeds_tags_map_feeds_tags_map_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.feeds_tags_map_feeds_tags_map_id_seq OWNER TO mediacloud;

--
-- Name: feeds_tags_map_feeds_tags_map_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.feeds_tags_map_feeds_tags_map_id_seq OWNED BY public.feeds_tags_map.feeds_tags_map_id;


--
-- Name: focal_set_definitions; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.focal_set_definitions (
    focal_set_definitions_id integer NOT NULL,
    topics_id integer NOT NULL,
    name text NOT NULL,
    description text,
    focal_technique public.focal_technique_type NOT NULL
);


ALTER TABLE public.focal_set_definitions OWNER TO mediacloud;

--
-- Name: focal_set_definitions_focal_set_definitions_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.focal_set_definitions_focal_set_definitions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.focal_set_definitions_focal_set_definitions_id_seq OWNER TO mediacloud;

--
-- Name: focal_set_definitions_focal_set_definitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.focal_set_definitions_focal_set_definitions_id_seq OWNED BY public.focal_set_definitions.focal_set_definitions_id;


--
-- Name: focal_sets; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.focal_sets (
    focal_sets_id integer NOT NULL,
    snapshots_id integer NOT NULL,
    name text NOT NULL,
    description text,
    focal_technique public.focal_technique_type NOT NULL
);


ALTER TABLE public.focal_sets OWNER TO mediacloud;

--
-- Name: focal_sets_focal_sets_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.focal_sets_focal_sets_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.focal_sets_focal_sets_id_seq OWNER TO mediacloud;

--
-- Name: focal_sets_focal_sets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.focal_sets_focal_sets_id_seq OWNED BY public.focal_sets.focal_sets_id;


--
-- Name: foci; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.foci (
    foci_id integer NOT NULL,
    focal_sets_id integer NOT NULL,
    name text NOT NULL,
    description text,
    arguments json NOT NULL
);


ALTER TABLE public.foci OWNER TO mediacloud;

--
-- Name: foci_foci_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.foci_foci_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.foci_foci_id_seq OWNER TO mediacloud;

--
-- Name: foci_foci_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.foci_foci_id_seq OWNED BY public.foci.foci_id;


--
-- Name: focus_definitions; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.focus_definitions (
    focus_definitions_id integer NOT NULL,
    focal_set_definitions_id integer NOT NULL,
    name text NOT NULL,
    description text,
    arguments json NOT NULL
);


ALTER TABLE public.focus_definitions OWNER TO mediacloud;

--
-- Name: focus_definitions_focus_definitions_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.focus_definitions_focus_definitions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.focus_definitions_focus_definitions_id_seq OWNER TO mediacloud;

--
-- Name: focus_definitions_focus_definitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.focus_definitions_focus_definitions_id_seq OWNED BY public.focus_definitions.focus_definitions_id;


--
-- Name: job_states; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.job_states (
    job_states_id integer NOT NULL,
    class character varying(1024) NOT NULL,
    state character varying(1024) NOT NULL,
    message text,
    last_updated timestamp without time zone DEFAULT now() NOT NULL,
    args json NOT NULL,
    priority text NOT NULL,
    hostname text NOT NULL,
    process_id integer NOT NULL
);


ALTER TABLE public.job_states OWNER TO mediacloud;

--
-- Name: TABLE job_states; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.job_states IS 'job states as implemented in mediawords.job.StatefulJobBroker';


--
-- Name: COLUMN job_states.class; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.job_states.class IS 'MediaWords::Job::* class implementing the job';


--
-- Name: COLUMN job_states.state; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.job_states.state IS 'short class-specific state';


--
-- Name: COLUMN job_states.message; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.job_states.message IS 'optional longer message describing the state, such 
as a stack trace for an error';


--
-- Name: job_states_job_states_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.job_states_job_states_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.job_states_job_states_id_seq OWNER TO mediacloud;

--
-- Name: job_states_job_states_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.job_states_job_states_id_seq OWNED BY public.job_states.job_states_id;


--
-- Name: media; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.media (
    media_id integer NOT NULL,
    url character varying(1024) NOT NULL,
    normalized_url character varying(1024),
    name character varying(128) NOT NULL,
    full_text_rss boolean,
    foreign_rss_links boolean DEFAULT false NOT NULL,
    dup_media_id integer,
    is_not_dup boolean,
    content_delay integer,
    editor_notes text,
    public_notes text,
    is_monitored boolean DEFAULT false NOT NULL,
    CONSTRAINT media_name_not_empty CHECK (((name)::text <> ''::text)),
    CONSTRAINT media_self_dup CHECK (((dup_media_id IS NULL) OR (dup_media_id <> media_id)))
);


ALTER TABLE public.media OWNER TO mediacloud;

--
-- Name: COLUMN media.foreign_rss_links; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.media.foreign_rss_links IS 'ndicates that the media source includes a substantial 
number of links in its feeds that are not its own. These media sources cause problems for the 
topic mapper spider, which finds those foreign rss links an thinks that the urls belong to the 
parent media source.';


--
-- Name: COLUMN media.content_delay; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.media.content_delay IS 'Delay content downloads for this media source for (int) hours';


--
-- Name: COLUMN media.editor_notes; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.media.editor_notes IS 'notes for internal MC consumption (e.g. "added this for yochai")';


--
-- Name: COLUMN media.public_notes; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.media.public_notes IS 'notes for public consumption (e.g. "leading dissident paper in antarctica")';


--
-- Name: COLUMN media.is_monitored; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.media.is_monitored IS 'if true, indicates that MC closely monitors health of this source';


--
-- Name: media_coverage_gaps; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.media_coverage_gaps (
    media_id integer NOT NULL,
    stat_week date NOT NULL,
    num_stories numeric NOT NULL,
    expected_stories numeric NOT NULL,
    num_sentences numeric NOT NULL,
    expected_sentences numeric NOT NULL
);


ALTER TABLE public.media_coverage_gaps OWNER TO mediacloud;

--
-- Name: media_expected_volume; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.media_expected_volume (
    media_id integer NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    expected_stories numeric NOT NULL,
    expected_sentences numeric NOT NULL
);


ALTER TABLE public.media_expected_volume OWNER TO mediacloud;

--
-- Name: media_health; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.media_health (
    media_health_id integer NOT NULL,
    media_id integer NOT NULL,
    num_stories numeric NOT NULL,
    num_stories_y numeric NOT NULL,
    num_stories_w numeric NOT NULL,
    num_stories_90 numeric NOT NULL,
    num_sentences numeric NOT NULL,
    num_sentences_y numeric NOT NULL,
    num_sentences_w numeric NOT NULL,
    num_sentences_90 numeric NOT NULL,
    is_healthy boolean DEFAULT false NOT NULL,
    has_active_feed boolean DEFAULT true NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    expected_sentences numeric NOT NULL,
    expected_stories numeric NOT NULL,
    coverage_gaps integer NOT NULL
);


ALTER TABLE public.media_health OWNER TO mediacloud;

--
-- Name: media_health_media_health_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.media_health_media_health_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.media_health_media_health_id_seq OWNER TO mediacloud;

--
-- Name: media_health_media_health_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.media_health_media_health_id_seq OWNED BY public.media_health.media_health_id;


--
-- Name: media_media_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.media_media_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.media_media_id_seq OWNER TO mediacloud;

--
-- Name: media_media_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.media_media_id_seq OWNED BY public.media.media_id;


--
-- Name: media_rescraping; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.media_rescraping (
    media_id integer NOT NULL,
    disable boolean DEFAULT false NOT NULL,
    last_rescrape_time timestamp with time zone
);


ALTER TABLE public.media_rescraping OWNER TO mediacloud;

--
-- Name: media_similarweb_domains_map; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.media_similarweb_domains_map (
    media_similarweb_domains_map_id integer NOT NULL,
    media_id integer NOT NULL,
    similarweb_domains_id integer NOT NULL
);


ALTER TABLE public.media_similarweb_domains_map OWNER TO mediacloud;

--
-- Name: TABLE media_similarweb_domains_map; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.media_similarweb_domains_map IS 'Media - SimilarWeb domain map. A few media sources 
might be pointing to one or more domains due to code differences in how domain was extracted from media 
source URL between various implementations.';


--
-- Name: media_similarweb_domains_map_media_similarweb_domains_map_i_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.media_similarweb_domains_map_media_similarweb_domains_map_i_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.media_similarweb_domains_map_media_similarweb_domains_map_i_seq OWNER TO mediacloud;

--
-- Name: media_similarweb_domains_map_media_similarweb_domains_map_i_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.media_similarweb_domains_map_media_similarweb_domains_map_i_seq OWNED BY public.media_similarweb_domains_map.media_similarweb_domains_map_id;


--
-- Name: media_sitemap_pages; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.media_sitemap_pages (
    media_sitemap_pages_id bigint NOT NULL,
    media_id integer NOT NULL,
    url text NOT NULL,
    last_modified timestamp with time zone,
    change_frequency public.media_sitemap_pages_change_frequency,
    priority numeric(2,1) DEFAULT 0.5 NOT NULL,
    news_title text,
    news_publish_date timestamp with time zone,
    CONSTRAINT media_sitemap_pages_priority_within_bounds CHECK (((priority IS NULL) OR ((priority >= 0.0) AND (priority <= 1.0))))
);


ALTER TABLE public.media_sitemap_pages OWNER TO mediacloud;

--
-- Name: TABLE media_sitemap_pages; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.media_sitemap_pages IS 'Pages derived from XML sitemaps (stories or not)';


--
-- Name: media_sitemap_pages_media_sitemap_pages_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.media_sitemap_pages_media_sitemap_pages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.media_sitemap_pages_media_sitemap_pages_id_seq OWNER TO mediacloud;

--
-- Name: media_sitemap_pages_media_sitemap_pages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.media_sitemap_pages_media_sitemap_pages_id_seq OWNED BY public.media_sitemap_pages.media_sitemap_pages_id;


--
-- Name: media_stats; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.media_stats (
    media_stats_id integer NOT NULL,
    media_id integer NOT NULL,
    num_stories integer NOT NULL,
    num_sentences integer NOT NULL,
    stat_date date NOT NULL
);


ALTER TABLE public.media_stats OWNER TO mediacloud;

--
-- Name: media_stats_media_stats_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.media_stats_media_stats_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.media_stats_media_stats_id_seq OWNER TO mediacloud;

--
-- Name: media_stats_media_stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.media_stats_media_stats_id_seq OWNED BY public.media_stats.media_stats_id;


--
-- Name: media_stats_weekly; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.media_stats_weekly (
    media_id integer NOT NULL,
    stories_rank integer NOT NULL,
    num_stories numeric NOT NULL,
    sentences_rank integer NOT NULL,
    num_sentences numeric NOT NULL,
    stat_week date NOT NULL
);


ALTER TABLE public.media_stats_weekly OWNER TO mediacloud;

--
-- Name: media_suggestions; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.media_suggestions (
    media_suggestions_id integer NOT NULL,
    name text,
    url text NOT NULL,
    feed_url text,
    reason text,
    auth_users_id integer,
    mark_auth_users_id integer,
    date_submitted timestamp without time zone DEFAULT now() NOT NULL,
    media_id integer,
    date_marked timestamp without time zone DEFAULT now() NOT NULL,
    mark_reason text,
    status public.media_suggestions_status DEFAULT 'pending'::public.media_suggestions_status NOT NULL,
    CONSTRAINT media_suggestions_media_id CHECK (((status = ANY (ARRAY['pending'::public.media_suggestions_status, 'rejected'::public.media_suggestions_status])) OR (media_id IS NOT NULL)))
);


ALTER TABLE public.media_suggestions OWNER TO mediacloud;

--
-- Name: media_suggestions_media_suggestions_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.media_suggestions_media_suggestions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.media_suggestions_media_suggestions_id_seq OWNER TO mediacloud;

--
-- Name: media_suggestions_media_suggestions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.media_suggestions_media_suggestions_id_seq OWNED BY public.media_suggestions.media_suggestions_id;


--
-- Name: media_suggestions_tags_map; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.media_suggestions_tags_map (
    media_suggestions_id integer,
    tags_id integer
);


ALTER TABLE public.media_suggestions_tags_map OWNER TO mediacloud;

--
-- Name: media_tags_map; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.media_tags_map (
    media_tags_map_id integer NOT NULL,
    media_id integer NOT NULL,
    tags_id integer NOT NULL,
    tagged_date date DEFAULT now()
);


ALTER TABLE public.media_tags_map OWNER TO mediacloud;

--
-- Name: media_tags_map_media_tags_map_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.media_tags_map_media_tags_map_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.media_tags_map_media_tags_map_id_seq OWNER TO mediacloud;

--
-- Name: media_tags_map_media_tags_map_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.media_tags_map_media_tags_map_id_seq OWNED BY public.media_tags_map.media_tags_map_id;


--
-- Name: tag_sets; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.tag_sets (
    tag_sets_id integer NOT NULL,
    name character varying(512) NOT NULL,
    label character varying(512),
    description text,
    show_on_media boolean,
    show_on_stories boolean,
    CONSTRAINT tag_sets_name_not_empty CHECK (((name)::text <> ''::text))
);


ALTER TABLE public.tag_sets OWNER TO mediacloud;

--
-- Name: COLUMN tag_sets.show_on_media; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.tag_sets.show_on_media IS 'should public interfaces show this as an option for
searching media sources?';


--
-- Name: COLUMN tag_sets.show_on_stories; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.tag_sets.show_on_stories IS 'should public interfaces show this as an option 
for search stories?';


--
-- Name: tags; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.tags (
    tags_id integer NOT NULL,
    tag_sets_id integer NOT NULL,
    tag character varying(512) NOT NULL,
    label character varying(512),
    description text,
    show_on_media boolean,
    show_on_stories boolean,
    is_static boolean DEFAULT false NOT NULL,
    CONSTRAINT no_line_feed CHECK (((NOT ((tag)::text ~~ '%
%'::text)) AND (NOT ((tag)::text ~~ '%
%'::text)))),
    CONSTRAINT tag_not_empty CHECK (((tag)::text <> ''::text))
);


ALTER TABLE public.tags OWNER TO mediacloud;

--
-- Name: COLUMN tags.show_on_media; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.tags.show_on_media IS 'should public interfaces show this as an option for
searching media sources?';


--
-- Name: COLUMN tags.show_on_stories; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.tags.show_on_stories IS 'should public interfaces show this as an option 
for search stories?';


--
-- Name: COLUMN tags.is_static; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.tags.is_static IS 'if true, users can expect this tag and its associations 
not to change in major ways';


--
-- Name: media_with_media_types; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.media_with_media_types AS
 SELECT m.media_id,
    m.url,
    m.normalized_url,
    m.name,
    m.full_text_rss,
    m.foreign_rss_links,
    m.dup_media_id,
    m.is_not_dup,
    m.content_delay,
    m.editor_notes,
    m.public_notes,
    m.is_monitored,
    mtm.tags_id AS media_type_tags_id,
    t.label AS media_type
   FROM (public.media m
     LEFT JOIN ((public.tags t
     JOIN public.tag_sets ts ON (((ts.tag_sets_id = t.tag_sets_id) AND ((ts.name)::text = 'media_type'::text))))
     JOIN public.media_tags_map mtm ON ((mtm.tags_id = t.tags_id))) ON ((m.media_id = mtm.media_id)));


ALTER TABLE public.media_with_media_types OWNER TO mediacloud;

--
-- Name: mediacloud_stats; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.mediacloud_stats (
    mediacloud_stats_id integer NOT NULL,
    stats_date date DEFAULT now() NOT NULL,
    daily_downloads bigint NOT NULL,
    daily_stories bigint NOT NULL,
    active_crawled_media bigint NOT NULL,
    active_crawled_feeds bigint NOT NULL,
    total_stories bigint NOT NULL,
    total_downloads bigint NOT NULL,
    total_sentences bigint NOT NULL
);


ALTER TABLE public.mediacloud_stats OWNER TO mediacloud;

--
-- Name: TABLE mediacloud_stats; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.mediacloud_stats IS 'keep track of basic high level stats for mediacloud for access through api';


--
-- Name: mediacloud_stats_mediacloud_stats_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.mediacloud_stats_mediacloud_stats_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.mediacloud_stats_mediacloud_stats_id_seq OWNER TO mediacloud;

--
-- Name: mediacloud_stats_mediacloud_stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.mediacloud_stats_mediacloud_stats_id_seq OWNED BY public.mediacloud_stats.mediacloud_stats_id;


--
-- Name: nytlabels_annotations; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.nytlabels_annotations (
    nytlabels_annotations_id integer NOT NULL,
    object_id integer NOT NULL,
    raw_data bytea NOT NULL
);
ALTER TABLE ONLY public.nytlabels_annotations ALTER COLUMN raw_data SET STORAGE EXTERNAL;


ALTER TABLE public.nytlabels_annotations OWNER TO mediacloud;

--
-- Name: nytlabels_annotations_nytlabels_annotations_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.nytlabels_annotations_nytlabels_annotations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.nytlabels_annotations_nytlabels_annotations_id_seq OWNER TO mediacloud;

--
-- Name: nytlabels_annotations_nytlabels_annotations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.nytlabels_annotations_nytlabels_annotations_id_seq OWNED BY public.nytlabels_annotations.nytlabels_annotations_id;


--
-- Name: pending_job_states; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.pending_job_states AS
 SELECT job_states.job_states_id,
    job_states.class,
    job_states.state,
    job_states.message,
    job_states.last_updated,
    job_states.args,
    job_states.priority,
    job_states.hostname,
    job_states.process_id
   FROM public.job_states
  WHERE ((job_states.state)::text = ANY ((ARRAY['running'::character varying, 'queued'::character varying])::text[]));


ALTER TABLE public.pending_job_states OWNER TO mediacloud;

--
-- Name: processed_stories; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.processed_stories (
    processed_stories_id bigint NOT NULL,
    stories_id integer NOT NULL
);


ALTER TABLE public.processed_stories OWNER TO mediacloud;

--
-- Name: processed_stories_processed_stories_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.processed_stories_processed_stories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.processed_stories_processed_stories_id_seq OWNER TO mediacloud;

--
-- Name: processed_stories_processed_stories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.processed_stories_processed_stories_id_seq OWNED BY public.processed_stories.processed_stories_id;


--
-- Name: queued_downloads; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.queued_downloads (
    queued_downloads_id bigint NOT NULL,
    downloads_id bigint NOT NULL
);


ALTER TABLE public.queued_downloads OWNER TO mediacloud;

--
-- Name: queued_downloads_queued_downloads_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.queued_downloads_queued_downloads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.queued_downloads_queued_downloads_id_seq OWNER TO mediacloud;

--
-- Name: queued_downloads_queued_downloads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.queued_downloads_queued_downloads_id_seq OWNED BY public.queued_downloads.queued_downloads_id;


--
-- Name: raw_downloads; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.raw_downloads (
    raw_downloads_id bigint NOT NULL,
    object_id bigint NOT NULL,
    raw_data bytea NOT NULL
);
ALTER TABLE ONLY public.raw_downloads ALTER COLUMN raw_data SET STORAGE EXTERNAL;


ALTER TABLE public.raw_downloads OWNER TO mediacloud;

--
-- Name: TABLE raw_downloads; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.raw_downloads IS 'Raw downloads stored in the database (if 
the "postgresql" download storage method is enabled)';


--
-- Name: COLUMN raw_downloads.object_id; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.raw_downloads.object_id IS '"downloads_id" from "downloads"';


--
-- Name: COLUMN raw_downloads.raw_data; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.raw_downloads.raw_data IS 'Do not attempt to compress BLOBs in 
"raw_data" because they are going to becompressed already';


--
-- Name: raw_downloads_raw_downloads_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.raw_downloads_raw_downloads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.raw_downloads_raw_downloads_id_seq OWNER TO mediacloud;

--
-- Name: raw_downloads_raw_downloads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.raw_downloads_raw_downloads_id_seq OWNED BY public.raw_downloads.raw_downloads_id;


--
-- Name: retweeter_groups; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.retweeter_groups (
    retweeter_groups_id integer NOT NULL,
    retweeter_scores_id integer NOT NULL,
    name text NOT NULL
);


ALTER TABLE public.retweeter_groups OWNER TO mediacloud;

--
-- Name: TABLE retweeter_groups; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.retweeter_groups IS 'group retweeters together so that we 
can compare, for example, sanders/warren retweeters to cruz/kasich retweeters';


--
-- Name: retweeter_groups_retweeter_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.retweeter_groups_retweeter_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.retweeter_groups_retweeter_groups_id_seq OWNER TO mediacloud;

--
-- Name: retweeter_groups_retweeter_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.retweeter_groups_retweeter_groups_id_seq OWNED BY public.retweeter_groups.retweeter_groups_id;


--
-- Name: retweeter_groups_users_map; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.retweeter_groups_users_map (
    retweeter_groups_id integer NOT NULL,
    retweeter_scores_id integer NOT NULL,
    retweeted_user character varying(1024) NOT NULL
);


ALTER TABLE public.retweeter_groups_users_map OWNER TO mediacloud;

--
-- Name: retweeter_media; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.retweeter_media (
    retweeter_media_id integer NOT NULL,
    retweeter_scores_id integer NOT NULL,
    media_id integer NOT NULL,
    group_a_count integer NOT NULL,
    group_b_count integer NOT NULL,
    group_a_count_n double precision NOT NULL,
    score double precision NOT NULL,
    partition integer NOT NULL
);


ALTER TABLE public.retweeter_media OWNER TO mediacloud;

--
-- Name: TABLE retweeter_media; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.retweeter_media IS 'polarization scores for media within a topic for the given 
retweeter_scores definition';


--
-- Name: retweeter_media_retweeter_media_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.retweeter_media_retweeter_media_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.retweeter_media_retweeter_media_id_seq OWNER TO mediacloud;

--
-- Name: retweeter_media_retweeter_media_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.retweeter_media_retweeter_media_id_seq OWNED BY public.retweeter_media.retweeter_media_id;


--
-- Name: retweeter_partition_matrix; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.retweeter_partition_matrix (
    retweeter_partition_matrix_id integer NOT NULL,
    retweeter_scores_id integer NOT NULL,
    retweeter_groups_id integer NOT NULL,
    group_name text NOT NULL,
    share_count integer NOT NULL,
    group_proportion double precision NOT NULL,
    partition integer NOT NULL
);


ALTER TABLE public.retweeter_partition_matrix OWNER TO mediacloud;

--
-- Name: retweeter_partition_matrix_retweeter_partition_matrix_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.retweeter_partition_matrix_retweeter_partition_matrix_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.retweeter_partition_matrix_retweeter_partition_matrix_id_seq OWNER TO mediacloud;

--
-- Name: retweeter_partition_matrix_retweeter_partition_matrix_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.retweeter_partition_matrix_retweeter_partition_matrix_id_seq OWNED BY public.retweeter_partition_matrix.retweeter_partition_matrix_id;


--
-- Name: retweeter_scores; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.retweeter_scores (
    retweeter_scores_id integer NOT NULL,
    topics_id integer NOT NULL,
    group_a_id integer,
    group_b_id integer,
    name text NOT NULL,
    state text DEFAULT 'created but not queued'::text NOT NULL,
    message text,
    num_partitions integer NOT NULL,
    match_type public.retweeter_scores_match_type DEFAULT 'retweet'::public.retweeter_scores_match_type NOT NULL
);


ALTER TABLE public.retweeter_scores OWNER TO mediacloud;

--
-- Name: TABLE retweeter_scores; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.retweeter_scores IS 'definition of bipolar comparisons for retweeter polarization scores';


--
-- Name: retweeter_scores_retweeter_scores_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.retweeter_scores_retweeter_scores_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.retweeter_scores_retweeter_scores_id_seq OWNER TO mediacloud;

--
-- Name: retweeter_scores_retweeter_scores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.retweeter_scores_retweeter_scores_id_seq OWNED BY public.retweeter_scores.retweeter_scores_id;


--
-- Name: retweeter_stories; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.retweeter_stories (
    retweeter_shares_id integer NOT NULL,
    retweeter_scores_id integer NOT NULL,
    stories_id integer NOT NULL,
    retweeted_user character varying(1024) NOT NULL,
    share_count integer NOT NULL
);


ALTER TABLE public.retweeter_stories OWNER TO mediacloud;

--
-- Name: TABLE retweeter_stories; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.retweeter_stories IS 'count of shares by retweeters for each retweeted_user in retweeters';


--
-- Name: retweeter_stories_retweeter_shares_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.retweeter_stories_retweeter_shares_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.retweeter_stories_retweeter_shares_id_seq OWNER TO mediacloud;

--
-- Name: retweeter_stories_retweeter_shares_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.retweeter_stories_retweeter_shares_id_seq OWNED BY public.retweeter_stories.retweeter_shares_id;


--
-- Name: retweeters; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.retweeters (
    retweeters_id integer NOT NULL,
    retweeter_scores_id integer NOT NULL,
    twitter_user character varying(1024) NOT NULL,
    retweeted_user character varying(1024) NOT NULL
);


ALTER TABLE public.retweeters OWNER TO mediacloud;

--
-- Name: TABLE retweeters; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.retweeters IS 'list of twitter users within a given topic that have retweeted the given user';


--
-- Name: retweeters_retweeters_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.retweeters_retweeters_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.retweeters_retweeters_id_seq OWNER TO mediacloud;

--
-- Name: retweeters_retweeters_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.retweeters_retweeters_id_seq OWNED BY public.retweeters.retweeters_id;


--
-- Name: schema_version; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.schema_version (
    version bigint NOT NULL,
    description text NOT NULL,
    type public.schema_version_type DEFAULT 'auto'::public.schema_version_type NOT NULL,
    installed_by text NOT NULL,
    installed_on timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.schema_version OWNER TO mediacloud;

--
-- Name: scraped_feeds_feed_scrapes_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.scraped_feeds_feed_scrapes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.scraped_feeds_feed_scrapes_id_seq OWNER TO mediacloud;

--
-- Name: scraped_feeds_feed_scrapes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.scraped_feeds_feed_scrapes_id_seq OWNED BY public.scraped_feeds.feed_scrapes_id;


--
-- Name: scraped_stories; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.scraped_stories (
    scraped_stories_id integer NOT NULL,
    stories_id integer NOT NULL,
    import_module text NOT NULL
);


ALTER TABLE public.scraped_stories OWNER TO mediacloud;

--
-- Name: TABLE scraped_stories; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.scraped_stories IS 'list of stories that have been scraped and the source';


--
-- Name: scraped_stories_scraped_stories_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.scraped_stories_scraped_stories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.scraped_stories_scraped_stories_id_seq OWNER TO mediacloud;

--
-- Name: scraped_stories_scraped_stories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.scraped_stories_scraped_stories_id_seq OWNED BY public.scraped_stories.scraped_stories_id;


--
-- Name: similarweb_domains; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.similarweb_domains (
    similarweb_domains_id integer NOT NULL,
    domain text NOT NULL
);


ALTER TABLE public.similarweb_domains OWNER TO mediacloud;

--
-- Name: TABLE similarweb_domains; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.similarweb_domains IS 'Domains for which we have tried to fetch SimilarWeb stats.
Every media source domain for which we have tried to fetch estimated visits from SimilarWeb gets 
stored here. The domain might have been invalid or unpopular enough so "similarweb_estimated_visits" 
might not necessarily store stats for every domain in this table.';


--
-- Name: COLUMN similarweb_domains.domain; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.similarweb_domains.domain IS 'Top-level (e.g. cnn.com) or second-level 
(e.g. edition.cnn.com) domain';


--
-- Name: similarweb_domains_similarweb_domains_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.similarweb_domains_similarweb_domains_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.similarweb_domains_similarweb_domains_id_seq OWNER TO mediacloud;

--
-- Name: similarweb_domains_similarweb_domains_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.similarweb_domains_similarweb_domains_id_seq OWNED BY public.similarweb_domains.similarweb_domains_id;


--
-- Name: similarweb_estimated_visits; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.similarweb_estimated_visits (
    similarweb_estimated_visits_id integer NOT NULL,
    similarweb_domains_id integer NOT NULL,
    month date NOT NULL,
    main_domain_only boolean NOT NULL,
    visits bigint NOT NULL
);


ALTER TABLE public.similarweb_estimated_visits OWNER TO mediacloud;

--
-- Name: TABLE similarweb_estimated_visits; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.similarweb_estimated_visits IS 'https://www.similarweb.com/corp/developer/estimated_visits_api';


--
-- Name: similarweb_estimated_visits_similarweb_estimated_visits_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.similarweb_estimated_visits_similarweb_estimated_visits_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.similarweb_estimated_visits_similarweb_estimated_visits_id_seq OWNER TO mediacloud;

--
-- Name: similarweb_estimated_visits_similarweb_estimated_visits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.similarweb_estimated_visits_similarweb_estimated_visits_id_seq OWNED BY public.similarweb_estimated_visits.similarweb_estimated_visits_id;


--
-- Name: snapshot_files; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.snapshot_files (
    snapshot_files_id integer NOT NULL,
    snapshots_id integer NOT NULL,
    name text,
    url text
);


ALTER TABLE public.snapshot_files OWNER TO mediacloud;

--
-- Name: snapshot_files_snapshot_files_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.snapshot_files_snapshot_files_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.snapshot_files_snapshot_files_id_seq OWNER TO mediacloud;

--
-- Name: snapshot_files_snapshot_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.snapshot_files_snapshot_files_id_seq OWNED BY public.snapshot_files.snapshot_files_id;


--
-- Name: snapshots_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.snapshots_snapshots_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.snapshots_snapshots_id_seq OWNER TO mediacloud;

--
-- Name: snapshots_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.snapshots_snapshots_id_seq OWNED BY public.snapshots.snapshots_id;


--
-- Name: solr_import_stories; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.solr_import_stories (
    stories_id integer NOT NULL
);


ALTER TABLE public.solr_import_stories OWNER TO mediacloud;

--
-- Name: TABLE solr_import_stories; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.solr_import_stories IS 'Extra stories to import into';


--
-- Name: solr_imported_stories; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.solr_imported_stories (
    stories_id integer NOT NULL,
    import_date timestamp without time zone NOT NULL
);


ALTER TABLE public.solr_imported_stories OWNER TO mediacloud;

--
-- Name: TABLE solr_imported_stories; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.solr_imported_stories IS 'log of all stories import into solr, with the import date';


--
-- Name: solr_imports_solr_imports_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.solr_imports_solr_imports_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.solr_imports_solr_imports_id_seq OWNER TO mediacloud;

--
-- Name: solr_imports_solr_imports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.solr_imports_solr_imports_id_seq OWNED BY public.solr_imports.solr_imports_id;


--
-- Name: stories_ap_syndicated; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.stories_ap_syndicated (
    stories_ap_syndicated_id integer NOT NULL,
    stories_id integer NOT NULL,
    ap_syndicated boolean NOT NULL
);


ALTER TABLE public.stories_ap_syndicated OWNER TO mediacloud;

--
-- Name: stories_ap_syndicated_stories_ap_syndicated_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.stories_ap_syndicated_stories_ap_syndicated_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.stories_ap_syndicated_stories_ap_syndicated_id_seq OWNER TO mediacloud;

--
-- Name: stories_ap_syndicated_stories_ap_syndicated_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.stories_ap_syndicated_stories_ap_syndicated_id_seq OWNED BY public.stories_ap_syndicated.stories_ap_syndicated_id;


--
-- Name: stories_stories_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.stories_stories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.stories_stories_id_seq OWNER TO mediacloud;

--
-- Name: stories_stories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.stories_stories_id_seq OWNED BY public.stories.stories_id;


--
-- Name: stories_tags_map_p; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.stories_tags_map_p (
    stories_tags_map_p_id bigint NOT NULL,
    stories_id integer NOT NULL,
    tags_id integer NOT NULL
);


ALTER TABLE public.stories_tags_map_p OWNER TO mediacloud;

--
-- Name: TABLE stories_tags_map_p; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.stories_tags_map_p IS '"Master" table (no indexes, 
no foreign keys as they will be ineffective)';


--
-- Name: COLUMN stories_tags_map_p.stories_tags_map_p_id; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.stories_tags_map_p.stories_tags_map_p_id IS 'PRIMARY KEY on 
master table needed for database handler primary_key_column() method to work';


--
-- Name: stories_tags_map; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.stories_tags_map AS
 SELECT stories_tags_map_p.stories_tags_map_p_id AS stories_tags_map_id,
    stories_tags_map_p.stories_id,
    stories_tags_map_p.tags_id
   FROM public.stories_tags_map_p;


ALTER TABLE public.stories_tags_map OWNER TO mediacloud;

--
-- Name: VIEW stories_tags_map; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON VIEW public.stories_tags_map IS 'Proxy view to "stories_tags_map_p" to make RETURNING work
with partitioned tables';


--
-- Name: stories_tags_map_p_00; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.stories_tags_map_p_00 (
    CONSTRAINT stories_tags_map_p_00_stories_id CHECK (((stories_id >= 0) AND (stories_id < 100000000)))
)
INHERITS (public.stories_tags_map_p);


ALTER TABLE public.stories_tags_map_p_00 OWNER TO mediacloud;

--
-- Name: stories_tags_map_p_stories_tags_map_p_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.stories_tags_map_p_stories_tags_map_p_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.stories_tags_map_p_stories_tags_map_p_id_seq OWNER TO mediacloud;

--
-- Name: stories_tags_map_p_stories_tags_map_p_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.stories_tags_map_p_stories_tags_map_p_id_seq OWNED BY public.stories_tags_map_p.stories_tags_map_p_id;


--
-- Name: story_enclosures; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.story_enclosures (
    story_enclosures_id bigint NOT NULL,
    stories_id integer NOT NULL,
    url text NOT NULL,
    mime_type public.citext,
    length bigint
);


ALTER TABLE public.story_enclosures OWNER TO mediacloud;

--
-- Name: TABLE story_enclosures; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.story_enclosures IS 'Enclosures added to feed item of the story';


--
-- Name: story_enclosures_story_enclosures_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.story_enclosures_story_enclosures_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.story_enclosures_story_enclosures_id_seq OWNER TO mediacloud;

--
-- Name: story_enclosures_story_enclosures_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.story_enclosures_story_enclosures_id_seq OWNED BY public.story_enclosures.story_enclosures_id;


--
-- Name: story_sentences_p; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.story_sentences_p (
    story_sentences_p_id bigint NOT NULL,
    stories_id integer NOT NULL,
    sentence_number integer NOT NULL,
    sentence text NOT NULL,
    media_id integer NOT NULL,
    publish_date timestamp without time zone,
    language character varying(3),
    is_dup boolean
);


ALTER TABLE public.story_sentences_p OWNER TO mediacloud;

--
-- Name: TABLE story_sentences_p; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.story_sentences_p IS 'Master table for individual sentences of stories
(no indexes, no foreign keys as they will be ineffective)';


--
-- Name: COLUMN story_sentences_p.language; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.story_sentences_p.language IS '2- or 3-character ISO 690 
language code; empty if unknown, NULL if unset';


--
-- Name: COLUMN story_sentences_p.is_dup; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON COLUMN public.story_sentences_p.is_dup IS 'Set to true for every sentence for 
which a duplicate sentence was found in a future story (even though that duplicate sentence 
was not added to the table). We only use is_dup in the topic spidering, but I think it is critical
there. It is there because the first time I tried to run a spider on a broadly popular topic, 
it was unusable because of the amount of irrelevant content. When I dug in, I found that stories 
were getting included because of matches on boilerplate content that was getting duped out of 
most stories but not the first time it appeared. So I added the check to remove stories that match 
on a dup sentence, even if it is the dup sentence, and things cleaned up.';


--
-- Name: story_sentences; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.story_sentences AS
 SELECT story_sentences_p.story_sentences_p_id AS story_sentences_id,
    story_sentences_p.stories_id,
    story_sentences_p.sentence_number,
    story_sentences_p.sentence,
    story_sentences_p.media_id,
    story_sentences_p.publish_date,
    story_sentences_p.language,
    story_sentences_p.is_dup
   FROM public.story_sentences_p;


ALTER TABLE public.story_sentences OWNER TO mediacloud;

--
-- Name: VIEW story_sentences; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON VIEW public.story_sentences IS 'Proxy view to "story_sentences_p" to make RETURNING work 
with partitioned tables';


--
-- Name: story_sentences_p_00; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.story_sentences_p_00 (
    CONSTRAINT story_sentences_p_00_stories_id CHECK (((stories_id >= 0) AND (stories_id < 100000000)))
)
INHERITS (public.story_sentences_p);


ALTER TABLE public.story_sentences_p_00 OWNER TO mediacloud;

--
-- Name: story_sentences_p_story_sentences_p_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.story_sentences_p_story_sentences_p_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.story_sentences_p_story_sentences_p_id_seq OWNER TO mediacloud;

--
-- Name: story_sentences_p_story_sentences_p_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.story_sentences_p_story_sentences_p_id_seq OWNED BY public.story_sentences_p.story_sentences_p_id;


--
-- Name: story_statistics; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.story_statistics (
    story_statistics_id integer NOT NULL,
    stories_id integer NOT NULL,
    facebook_share_count integer,
    facebook_comment_count integer,
    facebook_reaction_count integer,
    facebook_api_collect_date timestamp without time zone,
    facebook_api_error text
);


ALTER TABLE public.story_statistics OWNER TO mediacloud;

--
-- Name: TABLE story_statistics; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.story_statistics IS 'stats for various externally dervied statistics about a story.';


--
-- Name: story_statistics_story_statistics_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.story_statistics_story_statistics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.story_statistics_story_statistics_id_seq OWNER TO mediacloud;

--
-- Name: story_statistics_story_statistics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.story_statistics_story_statistics_id_seq OWNED BY public.story_statistics.story_statistics_id;


--
-- Name: story_statistics_twitter; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.story_statistics_twitter (
    story_statistics_id integer NOT NULL,
    stories_id integer NOT NULL,
    twitter_url_tweet_count integer,
    twitter_api_collect_date timestamp without time zone,
    twitter_api_error text
);


ALTER TABLE public.story_statistics_twitter OWNER TO mediacloud;

--
-- Name: TABLE story_statistics_twitter; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.story_statistics_twitter IS 'stats for deprecated Twitter share counts';


--
-- Name: story_statistics_twitter_story_statistics_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.story_statistics_twitter_story_statistics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.story_statistics_twitter_story_statistics_id_seq OWNER TO mediacloud;

--
-- Name: story_statistics_twitter_story_statistics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.story_statistics_twitter_story_statistics_id_seq OWNED BY public.story_statistics_twitter.story_statistics_id;


--
-- Name: story_urls; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.story_urls (
    story_urls_id bigint NOT NULL,
    stories_id integer,
    url character varying(1024) NOT NULL
);


ALTER TABLE public.story_urls OWNER TO mediacloud;

--
-- Name: TABLE story_urls; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.story_urls IS 'list of all url or guid identifiers for each story';


--
-- Name: story_urls_story_urls_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.story_urls_story_urls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.story_urls_story_urls_id_seq OWNER TO mediacloud;

--
-- Name: story_urls_story_urls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.story_urls_story_urls_id_seq OWNED BY public.story_urls.story_urls_id;


--
-- Name: tag_sets_tag_sets_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.tag_sets_tag_sets_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tag_sets_tag_sets_id_seq OWNER TO mediacloud;

--
-- Name: tag_sets_tag_sets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.tag_sets_tag_sets_id_seq OWNED BY public.tag_sets.tag_sets_id;


--
-- Name: tags_tags_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.tags_tags_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tags_tags_id_seq OWNER TO mediacloud;

--
-- Name: tags_tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.tags_tags_id_seq OWNED BY public.tags.tags_id;


--
-- Name: tags_with_sets; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.tags_with_sets AS
 SELECT t.tags_id,
    t.tag_sets_id,
    t.tag,
    t.label,
    t.description,
    t.show_on_media,
    t.show_on_stories,
    t.is_static,
    ts.name AS tag_set_name
   FROM public.tags t,
    public.tag_sets ts
  WHERE (t.tag_sets_id = ts.tag_sets_id);


ALTER TABLE public.tags_with_sets OWNER TO mediacloud;

--
-- Name: task_id_sequence; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.task_id_sequence
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.task_id_sequence OWNER TO mediacloud;

--
-- Name: timespan_files; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.timespan_files (
    timespan_files_id integer NOT NULL,
    timespans_id integer NOT NULL,
    name text,
    url text
);


ALTER TABLE public.timespan_files OWNER TO mediacloud;

--
-- Name: timespan_files_timespan_files_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.timespan_files_timespan_files_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.timespan_files_timespan_files_id_seq OWNER TO mediacloud;

--
-- Name: timespan_files_timespan_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.timespan_files_timespan_files_id_seq OWNED BY public.timespan_files.timespan_files_id;


--
-- Name: timespan_maps; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.timespan_maps (
    timespan_maps_id integer NOT NULL,
    timespans_id integer NOT NULL,
    options jsonb NOT NULL,
    content bytea,
    url text,
    format character varying(1024) NOT NULL
);


ALTER TABLE public.timespan_maps OWNER TO mediacloud;

--
-- Name: timespan_maps_timespan_maps_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.timespan_maps_timespan_maps_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.timespan_maps_timespan_maps_id_seq OWNER TO mediacloud;

--
-- Name: timespan_maps_timespan_maps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.timespan_maps_timespan_maps_id_seq OWNED BY public.timespan_maps.timespan_maps_id;


--
-- Name: timespans_timespans_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.timespans_timespans_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.timespans_timespans_id_seq OWNER TO mediacloud;

--
-- Name: timespans_timespans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.timespans_timespans_id_seq OWNED BY public.timespans.timespans_id;


--
-- Name: topic_dates; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_dates (
    topic_dates_id integer NOT NULL,
    topics_id integer NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    boundary boolean DEFAULT false NOT NULL
);


ALTER TABLE public.topic_dates OWNER TO mediacloud;

--
-- Name: topic_dates_topic_dates_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_dates_topic_dates_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_dates_topic_dates_id_seq OWNER TO mediacloud;

--
-- Name: topic_dates_topic_dates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_dates_topic_dates_id_seq OWNED BY public.topic_dates.topic_dates_id;


--
-- Name: topic_dead_links; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_dead_links (
    topic_dead_links_id integer NOT NULL,
    topics_id integer NOT NULL,
    stories_id integer,
    url text NOT NULL
);


ALTER TABLE public.topic_dead_links OWNER TO mediacloud;

--
-- Name: TABLE topic_dead_links; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.topic_dead_links IS 'topic links for which the http request failed';


--
-- Name: topic_dead_links_topic_dead_links_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_dead_links_topic_dead_links_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_dead_links_topic_dead_links_id_seq OWNER TO mediacloud;

--
-- Name: topic_dead_links_topic_dead_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_dead_links_topic_dead_links_id_seq OWNED BY public.topic_dead_links.topic_dead_links_id;


--
-- Name: topic_domains; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_domains (
    topic_domains_id integer NOT NULL,
    topics_id integer NOT NULL,
    domain text NOT NULL,
    self_links integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.topic_domains OWNER TO mediacloud;

--
-- Name: TABLE topic_domains; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.topic_domains IS 'track self liks and all links for a given domain within a given topic';


--
-- Name: topic_domains_topic_domains_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_domains_topic_domains_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_domains_topic_domains_id_seq OWNER TO mediacloud;

--
-- Name: topic_domains_topic_domains_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_domains_topic_domains_id_seq OWNED BY public.topic_domains.topic_domains_id;


--
-- Name: topic_fetch_urls; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_fetch_urls (
    topic_fetch_urls_id bigint NOT NULL,
    topics_id integer NOT NULL,
    url text NOT NULL,
    code integer,
    fetch_date timestamp without time zone,
    state text NOT NULL,
    message text,
    stories_id integer,
    assume_match boolean DEFAULT false NOT NULL,
    topic_links_id integer
);


ALTER TABLE public.topic_fetch_urls OWNER TO mediacloud;

--
-- Name: topic_fetch_urls_topic_fetch_urls_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_fetch_urls_topic_fetch_urls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_fetch_urls_topic_fetch_urls_id_seq OWNER TO mediacloud;

--
-- Name: topic_fetch_urls_topic_fetch_urls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_fetch_urls_topic_fetch_urls_id_seq OWNED BY public.topic_fetch_urls.topic_fetch_urls_id;


--
-- Name: topic_ignore_redirects; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_ignore_redirects (
    topic_ignore_redirects_id integer NOT NULL,
    url character varying(1024)
);


ALTER TABLE public.topic_ignore_redirects OWNER TO mediacloud;

--
-- Name: topic_ignore_redirects_topic_ignore_redirects_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_ignore_redirects_topic_ignore_redirects_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_ignore_redirects_topic_ignore_redirects_id_seq OWNER TO mediacloud;

--
-- Name: topic_ignore_redirects_topic_ignore_redirects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_ignore_redirects_topic_ignore_redirects_id_seq OWNED BY public.topic_ignore_redirects.topic_ignore_redirects_id;


--
-- Name: topic_links; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_links (
    topic_links_id integer NOT NULL,
    topics_id integer NOT NULL,
    stories_id integer NOT NULL,
    url text NOT NULL,
    redirect_url text,
    ref_stories_id integer,
    link_spidered boolean DEFAULT false
);


ALTER TABLE public.topic_links OWNER TO mediacloud;

--
-- Name: TABLE topic_links; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.topic_links IS 'no foreign key constraints on topics_id and stories_id 
because we have the combined foreign key constraint pointing to topic_stories below';


--
-- Name: topic_stories; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_stories (
    topic_stories_id integer NOT NULL,
    topics_id integer NOT NULL,
    stories_id integer NOT NULL,
    link_mined boolean DEFAULT false,
    iteration integer DEFAULT 0,
    link_weight real,
    redirect_url text,
    valid_foreign_rss_story boolean DEFAULT false,
    link_mine_error text
);


ALTER TABLE public.topic_stories OWNER TO mediacloud;

--
-- Name: topic_links_cross_media; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.topic_links_cross_media AS
 SELECT s.stories_id,
    sm.name AS media_name,
    r.stories_id AS ref_stories_id,
    rm.name AS ref_media_name,
    cl.url,
    cs.topics_id,
    cl.topic_links_id
   FROM public.media sm,
    public.media rm,
    public.topic_links cl,
    public.stories s,
    public.stories r,
    public.topic_stories cs
  WHERE ((cl.ref_stories_id <> cl.stories_id) AND (s.stories_id = cl.stories_id) AND (cl.ref_stories_id = r.stories_id) AND (s.media_id <> r.media_id) AND (sm.media_id = s.media_id) AND (rm.media_id = r.media_id) AND (cs.stories_id = cl.ref_stories_id) AND (cs.topics_id = cl.topics_id));


ALTER TABLE public.topic_links_cross_media OWNER TO mediacloud;

--
-- Name: topic_links_topic_links_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_links_topic_links_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_links_topic_links_id_seq OWNER TO mediacloud;

--
-- Name: topic_links_topic_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_links_topic_links_id_seq OWNED BY public.topic_links.topic_links_id;


--
-- Name: topic_media_codes; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_media_codes (
    topics_id integer NOT NULL,
    media_id integer NOT NULL,
    code_type text,
    code text
);


ALTER TABLE public.topic_media_codes OWNER TO mediacloud;

--
-- Name: topic_merged_stories_map; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_merged_stories_map (
    source_stories_id integer NOT NULL,
    target_stories_id integer NOT NULL
);


ALTER TABLE public.topic_merged_stories_map OWNER TO mediacloud;

--
-- Name: topic_modes; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_modes (
    topic_modes_id integer NOT NULL,
    name character varying(1024) NOT NULL,
    description text NOT NULL
);


ALTER TABLE public.topic_modes OWNER TO mediacloud;

--
-- Name: TABLE topic_modes; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.topic_modes IS 'the mode is how we analyze the data from the platform 
(as web pages, social media posts, url sharing posts, etc)';


--
-- Name: topic_modes_topic_modes_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_modes_topic_modes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_modes_topic_modes_id_seq OWNER TO mediacloud;

--
-- Name: topic_modes_topic_modes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_modes_topic_modes_id_seq OWNED BY public.topic_modes.topic_modes_id;


--
-- Name: topic_permissions; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_permissions (
    topic_permissions_id integer NOT NULL,
    topics_id integer NOT NULL,
    auth_users_id integer NOT NULL,
    permission public.topic_permission NOT NULL
);


ALTER TABLE public.topic_permissions OWNER TO mediacloud;

--
-- Name: topic_permissions_topic_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_permissions_topic_permissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_permissions_topic_permissions_id_seq OWNER TO mediacloud;

--
-- Name: topic_permissions_topic_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_permissions_topic_permissions_id_seq OWNED BY public.topic_permissions.topic_permissions_id;


--
-- Name: topic_platforms; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_platforms (
    topic_platforms_id integer NOT NULL,
    name character varying(1024) NOT NULL,
    description text NOT NULL
);


ALTER TABLE public.topic_platforms OWNER TO mediacloud;

--
-- Name: TABLE topic_platforms; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.topic_platforms IS 'the platform is where the analyzed data lives (web, twitter, reddit, etc)';


--
-- Name: topic_platforms_sources_map; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_platforms_sources_map (
    topic_platforms_id integer NOT NULL,
    topic_sources_id integer NOT NULL
);


ALTER TABLE public.topic_platforms_sources_map OWNER TO mediacloud;

--
-- Name: TABLE topic_platforms_sources_map; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.topic_platforms_sources_map IS 'the pairs of platforms/sources 
for which the platform can fetch data';


--
-- Name: topic_platforms_topic_platforms_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_platforms_topic_platforms_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_platforms_topic_platforms_id_seq OWNER TO mediacloud;

--
-- Name: topic_platforms_topic_platforms_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_platforms_topic_platforms_id_seq OWNED BY public.topic_platforms.topic_platforms_id;


--
-- Name: topic_post_days; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_post_days (
    topic_post_days_id integer NOT NULL,
    topic_seed_queries_id integer NOT NULL,
    day date NOT NULL,
    num_posts_stored integer NOT NULL,
    num_posts_fetched integer NOT NULL,
    posts_fetched boolean DEFAULT false NOT NULL
);


ALTER TABLE public.topic_post_days OWNER TO mediacloud;

--
-- Name: TABLE topic_post_days; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.topic_post_days IS 'list of tweet counts and fetching statuses for each day of each topic';


--
-- Name: topic_post_days_topic_post_days_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_post_days_topic_post_days_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_post_days_topic_post_days_id_seq OWNER TO mediacloud;

--
-- Name: topic_post_days_topic_post_days_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_post_days_topic_post_days_id_seq OWNED BY public.topic_post_days.topic_post_days_id;


--
-- Name: topic_post_urls; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_post_urls (
    topic_post_urls_id integer NOT NULL,
    topic_posts_id integer NOT NULL,
    url character varying(1024) NOT NULL
);


ALTER TABLE public.topic_post_urls OWNER TO mediacloud;

--
-- Name: TABLE topic_post_urls; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.topic_post_urls IS 'urls parsed from topic tweets and imported into topic_seed_urls';


--
-- Name: topic_posts; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_posts (
    topic_posts_id integer NOT NULL,
    topic_post_days_id integer NOT NULL,
    data jsonb NOT NULL,
    post_id character varying(1024) NOT NULL,
    content text NOT NULL,
    publish_date timestamp without time zone NOT NULL,
    author character varying(1024) NOT NULL,
    channel character varying(1024) NOT NULL,
    url text
);


ALTER TABLE public.topic_posts OWNER TO mediacloud;

--
-- Name: TABLE topic_posts; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.topic_posts IS 'list of posts associated with a given topic';


--
-- Name: topic_seed_queries; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_seed_queries (
    topic_seed_queries_id integer NOT NULL,
    topics_id integer NOT NULL,
    source character varying(1024) NOT NULL,
    platform character varying(1024) NOT NULL,
    query text,
    imported_date timestamp without time zone,
    ignore_pattern text
);


ALTER TABLE public.topic_seed_queries OWNER TO mediacloud;

--
-- Name: topic_seed_urls; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_seed_urls (
    topic_seed_urls_id integer NOT NULL,
    topics_id integer NOT NULL,
    url text,
    source text,
    stories_id integer,
    processed boolean DEFAULT false NOT NULL,
    assume_match boolean DEFAULT false NOT NULL,
    content text,
    guid text,
    title text,
    publish_date text,
    topic_seed_queries_id integer,
    topic_post_urls_id integer
);


ALTER TABLE public.topic_seed_urls OWNER TO mediacloud;

--
-- Name: topic_post_stories; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.topic_post_stories AS
 SELECT tsq.topics_id,
    tp.topic_posts_id,
    tp.content,
    tp.publish_date,
    tp.author,
    tp.channel,
    tp.data,
    tpd.topic_seed_queries_id,
    ts.stories_id,
    tpu.url,
    tpu.topic_post_urls_id
   FROM (((((public.topic_seed_queries tsq
     JOIN public.topic_post_days tpd USING (topic_seed_queries_id))
     JOIN public.topic_posts tp USING (topic_post_days_id))
     JOIN public.topic_post_urls tpu USING (topic_posts_id))
     JOIN public.topic_seed_urls tsu USING (topic_post_urls_id))
     JOIN public.topic_stories ts ON (((ts.topics_id = tsq.topics_id) AND (ts.stories_id = tsu.stories_id))));


ALTER TABLE public.topic_post_stories OWNER TO mediacloud;

--
-- Name: VIEW topic_post_stories; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON VIEW public.topic_post_stories IS 'view that joins together the chain of tables from topic_seed_queries 
all the way through to topic_stories, so that you get back a topics_id, topic_posts_id stories_id, and 
topic_seed_queries_id in each row to track which stories came from which posts in which seed queries';


--
-- Name: topic_post_urls_topic_post_urls_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_post_urls_topic_post_urls_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_post_urls_topic_post_urls_id_seq OWNER TO mediacloud;

--
-- Name: topic_post_urls_topic_post_urls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_post_urls_topic_post_urls_id_seq OWNED BY public.topic_post_urls.topic_post_urls_id;


--
-- Name: topic_posts_topic_posts_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_posts_topic_posts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_posts_topic_posts_id_seq OWNER TO mediacloud;

--
-- Name: topic_posts_topic_posts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_posts_topic_posts_id_seq OWNED BY public.topic_posts.topic_posts_id;


--
-- Name: topic_query_story_searches_imported_stories_map; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_query_story_searches_imported_stories_map (
    topics_id integer NOT NULL,
    stories_id integer NOT NULL
);


ALTER TABLE public.topic_query_story_searches_imported_stories_map OWNER TO mediacloud;

--
-- Name: topic_seed_queries_topic_seed_queries_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_seed_queries_topic_seed_queries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_seed_queries_topic_seed_queries_id_seq OWNER TO mediacloud;

--
-- Name: topic_seed_queries_topic_seed_queries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_seed_queries_topic_seed_queries_id_seq OWNED BY public.topic_seed_queries.topic_seed_queries_id;


--
-- Name: topic_seed_urls_topic_seed_urls_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_seed_urls_topic_seed_urls_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_seed_urls_topic_seed_urls_id_seq OWNER TO mediacloud;

--
-- Name: topic_seed_urls_topic_seed_urls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_seed_urls_topic_seed_urls_id_seq OWNED BY public.topic_seed_urls.topic_seed_urls_id;


--
-- Name: topic_sources; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_sources (
    topic_sources_id integer NOT NULL,
    name character varying(1024) NOT NULL,
    description text NOT NULL
);


ALTER TABLE public.topic_sources OWNER TO mediacloud;

--
-- Name: TABLE topic_sources; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON TABLE public.topic_sources IS 'the source is where we get the 
platforn data from (a particular database, api, csv, etc)';


--
-- Name: topic_sources_topic_sources_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_sources_topic_sources_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_sources_topic_sources_id_seq OWNER TO mediacloud;

--
-- Name: topic_sources_topic_sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_sources_topic_sources_id_seq OWNED BY public.topic_sources.topic_sources_id;


--
-- Name: topic_spider_metrics; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topic_spider_metrics (
    topic_spider_metrics_id integer NOT NULL,
    topics_id integer,
    iteration integer NOT NULL,
    links_processed integer NOT NULL,
    elapsed_time integer NOT NULL,
    processed_date timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.topic_spider_metrics OWNER TO mediacloud;

--
-- Name: topic_spider_metrics_topic_spider_metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_spider_metrics_topic_spider_metrics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_spider_metrics_topic_spider_metrics_id_seq OWNER TO mediacloud;

--
-- Name: topic_spider_metrics_topic_spider_metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_spider_metrics_topic_spider_metrics_id_seq OWNED BY public.topic_spider_metrics.topic_spider_metrics_id;


--
-- Name: topic_stories_topic_stories_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topic_stories_topic_stories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topic_stories_topic_stories_id_seq OWNER TO mediacloud;

--
-- Name: topic_stories_topic_stories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topic_stories_topic_stories_id_seq OWNED BY public.topic_stories.topic_stories_id;


--
-- Name: topics_media_map; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topics_media_map (
    topics_id integer NOT NULL,
    media_id integer NOT NULL
);


ALTER TABLE public.topics_media_map OWNER TO mediacloud;

--
-- Name: topics_media_tags_map; Type: TABLE; Schema: public; Owner: mediacloud
--

CREATE TABLE public.topics_media_tags_map (
    topics_id integer NOT NULL,
    tags_id integer NOT NULL
);


ALTER TABLE public.topics_media_tags_map OWNER TO mediacloud;

--
-- Name: topics_topics_id_seq; Type: SEQUENCE; Schema: public; Owner: mediacloud
--

CREATE SEQUENCE public.topics_topics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.topics_topics_id_seq OWNER TO mediacloud;

--
-- Name: topics_topics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mediacloud
--

ALTER SEQUENCE public.topics_topics_id_seq OWNED BY public.topics.topics_id;


--
-- Name: topics_with_user_permission; Type: VIEW; Schema: public; Owner: mediacloud
--

CREATE VIEW public.topics_with_user_permission AS
 WITH admin_users AS (
         SELECT m.auth_users_id
           FROM (public.auth_roles r
             JOIN public.auth_users_roles_map m USING (auth_roles_id))
          WHERE (r.role = 'admin'::text)
        ), read_admin_users AS (
         SELECT m.auth_users_id
           FROM (public.auth_roles r
             JOIN public.auth_users_roles_map m USING (auth_roles_id))
          WHERE (r.role = 'admin-readonly'::text)
        )
 SELECT t.topics_id,
    t.name,
    t.pattern,
    t.solr_seed_query,
    t.solr_seed_query_run,
    t.description,
    t.media_type_tag_sets_id,
    t.max_iterations,
    t.state,
    t.message,
    t.is_public,
    t.is_logogram,
    t.start_date,
    t.end_date,
    t.respider_stories,
    t.respider_start_date,
    t.respider_end_date,
    t.snapshot_periods,
    t.platform,
    t.mode,
    t.job_queue,
    t.max_stories,
    t.is_story_index_ready,
    t.only_snapshot_engaged_stories,
    u.auth_users_id,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM admin_users a
              WHERE (a.auth_users_id = u.auth_users_id))) THEN 'admin'::text
            WHEN (tp.permission IS NOT NULL) THEN (tp.permission)::text
            WHEN t.is_public THEN 'read'::text
            WHEN (EXISTS ( SELECT 1
               FROM read_admin_users a
              WHERE (a.auth_users_id = u.auth_users_id))) THEN 'read'::text
            ELSE 'none'::text
        END AS user_permission
   FROM ((public.topics t
     JOIN public.auth_users u ON (true))
     LEFT JOIN public.topic_permissions tp USING (topics_id, auth_users_id));


ALTER TABLE public.topics_with_user_permission OWNER TO mediacloud;

--
-- Name: VIEW topics_with_user_permission; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON VIEW public.topics_with_user_permission IS 'topics table with auth_users_id and user_permission fields 
that indicate the permission level for the user for the topic.  permissions in decreasing order are admin, 
write, read, none.  users with the admin role have admin permission for every topic. users with admin-readonly 
role have at least read access to every topic.  all users have read access to every is_public topic. otherwise, 
the topic_permissions tableis used, with "none" for no topic_permission.';


--
-- Name: snapshot_files; Type: TABLE; Schema: public_store; Owner: mediacloud
--

CREATE TABLE public_store.snapshot_files (
    snapshot_files_id bigint NOT NULL,
    object_id bigint NOT NULL,
    raw_data bytea NOT NULL
);


ALTER TABLE public_store.snapshot_files OWNER TO mediacloud;

--
-- Name: snapshot_files_snapshot_files_id_seq; Type: SEQUENCE; Schema: public_store; Owner: mediacloud
--

CREATE SEQUENCE public_store.snapshot_files_snapshot_files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public_store.snapshot_files_snapshot_files_id_seq OWNER TO mediacloud;

--
-- Name: snapshot_files_snapshot_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public_store; Owner: mediacloud
--

ALTER SEQUENCE public_store.snapshot_files_snapshot_files_id_seq OWNED BY public_store.snapshot_files.snapshot_files_id;


--
-- Name: timespan_files; Type: TABLE; Schema: public_store; Owner: mediacloud
--

CREATE TABLE public_store.timespan_files (
    timespan_files_id bigint NOT NULL,
    object_id bigint NOT NULL,
    raw_data bytea NOT NULL
);


ALTER TABLE public_store.timespan_files OWNER TO mediacloud;

--
-- Name: timespan_files_timespan_files_id_seq; Type: SEQUENCE; Schema: public_store; Owner: mediacloud
--

CREATE SEQUENCE public_store.timespan_files_timespan_files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public_store.timespan_files_timespan_files_id_seq OWNER TO mediacloud;

--
-- Name: timespan_files_timespan_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public_store; Owner: mediacloud
--

ALTER SEQUENCE public_store.timespan_files_timespan_files_id_seq OWNED BY public_store.timespan_files.timespan_files_id;


--
-- Name: timespan_maps; Type: TABLE; Schema: public_store; Owner: mediacloud
--

CREATE TABLE public_store.timespan_maps (
    timespan_maps_id bigint NOT NULL,
    object_id bigint NOT NULL,
    raw_data bytea NOT NULL
);


ALTER TABLE public_store.timespan_maps OWNER TO mediacloud;

--
-- Name: timespan_maps_timespan_maps_id_seq; Type: SEQUENCE; Schema: public_store; Owner: mediacloud
--

CREATE SEQUENCE public_store.timespan_maps_timespan_maps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public_store.timespan_maps_timespan_maps_id_seq OWNER TO mediacloud;

--
-- Name: timespan_maps_timespan_maps_id_seq; Type: SEQUENCE OWNED BY; Schema: public_store; Owner: mediacloud
--

ALTER SEQUENCE public_store.timespan_maps_timespan_maps_id_seq OWNED BY public_store.timespan_maps.timespan_maps_id;


--
-- Name: live_stories; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.live_stories (
    topics_id integer NOT NULL,
    topic_stories_id integer NOT NULL,
    stories_id integer NOT NULL,
    media_id integer NOT NULL,
    url character varying(1024) NOT NULL,
    guid character varying(1024) NOT NULL,
    title text NOT NULL,
    normalized_title_hash uuid,
    description text,
    publish_date timestamp without time zone,
    collect_date timestamp without time zone NOT NULL,
    full_text_rss boolean DEFAULT false NOT NULL,
    language character varying(3)
);


ALTER TABLE snap.live_stories OWNER TO mediacloud;

--
-- Name: TABLE live_stories; Type: COMMENT; Schema: snap; Owner: mediacloud
--

COMMENT ON TABLE snap.live_stories IS 'create a mirror of the stories table with the stories 
for each topic. this is to make it much faster to query the stories associated with a given topic, 
rather than querying the contested and bloated stories table.  only inserts and updates on stories 
are triggered, because deleted cascading stories_id and topics_id fields take care of deletes.';


--
-- Name: COLUMN live_stories.language; Type: COMMENT; Schema: snap; Owner: mediacloud
--

COMMENT ON COLUMN snap.live_stories.language IS '2- or 3-character ISO 690 language code; 
empty if unknown, NULL if unset';


--
-- Name: media; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.media (
    snapshots_id integer NOT NULL,
    media_id integer,
    url character varying(1024) NOT NULL,
    name character varying(128) NOT NULL,
    full_text_rss boolean,
    foreign_rss_links boolean DEFAULT false NOT NULL,
    dup_media_id integer,
    is_not_dup boolean
);


ALTER TABLE snap.media OWNER TO mediacloud;

--
-- Name: media_tags_map; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.media_tags_map (
    snapshots_id integer NOT NULL,
    media_tags_map_id integer,
    media_id integer NOT NULL,
    tags_id integer NOT NULL
);


ALTER TABLE snap.media_tags_map OWNER TO mediacloud;

--
-- Name: medium_link_counts; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.medium_link_counts (
    timespans_id integer NOT NULL,
    media_id integer NOT NULL,
    sum_media_inlink_count integer NOT NULL,
    media_inlink_count integer NOT NULL,
    inlink_count integer NOT NULL,
    outlink_count integer NOT NULL,
    story_count integer NOT NULL,
    facebook_share_count integer,
    sum_post_count integer,
    sum_author_count integer,
    sum_channel_count integer
);


ALTER TABLE snap.medium_link_counts OWNER TO mediacloud;

--
-- Name: TABLE medium_link_counts; Type: COMMENT; Schema: snap; Owner: mediacloud
--

COMMENT ON TABLE snap.medium_link_counts IS 'links counts for media within a timespan';


--
-- Name: medium_links; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.medium_links (
    timespans_id integer NOT NULL,
    source_media_id integer NOT NULL,
    ref_media_id integer NOT NULL,
    link_count integer NOT NULL
);


ALTER TABLE snap.medium_links OWNER TO mediacloud;

--
-- Name: stories; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.stories (
    snapshots_id integer NOT NULL,
    stories_id integer,
    media_id integer NOT NULL,
    url character varying(1024) NOT NULL,
    guid character varying(1024) NOT NULL,
    title text NOT NULL,
    publish_date timestamp without time zone,
    collect_date timestamp without time zone NOT NULL,
    full_text_rss boolean DEFAULT false NOT NULL,
    language character varying(3)
);


ALTER TABLE snap.stories OWNER TO mediacloud;

--
-- Name: TABLE stories; Type: COMMENT; Schema: snap; Owner: mediacloud
--

COMMENT ON TABLE snap.stories IS 'create a table for each of these tables to hold a snapshot of stories 
relevant to a topic for each snapshot for that topic';


--
-- Name: COLUMN stories.language; Type: COMMENT; Schema: snap; Owner: mediacloud
--

COMMENT ON COLUMN snap.stories.language IS '2- or 3-character ISO 690 
language code; empty if unknown, NULL if unset';


--
-- Name: stories_tags_map; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.stories_tags_map (
    snapshots_id integer NOT NULL,
    stories_tags_map_id integer,
    stories_id integer,
    tags_id integer
);


ALTER TABLE snap.stories_tags_map OWNER TO mediacloud;

--
-- Name: story_link_counts; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.story_link_counts (
    timespans_id integer NOT NULL,
    stories_id integer NOT NULL,
    media_inlink_count integer NOT NULL,
    inlink_count integer NOT NULL,
    outlink_count integer NOT NULL,
    facebook_share_count integer,
    post_count integer,
    author_count integer,
    channel_count integer
);


ALTER TABLE snap.story_link_counts OWNER TO mediacloud;

--
-- Name: TABLE story_link_counts; Type: COMMENT; Schema: snap; Owner: mediacloud
--

COMMENT ON TABLE snap.story_link_counts IS 'link counts for stories within a timespan';


--
-- Name: story_links; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.story_links (
    timespans_id integer NOT NULL,
    source_stories_id integer NOT NULL,
    ref_stories_id integer NOT NULL
);


ALTER TABLE snap.story_links OWNER TO mediacloud;

--
-- Name: TABLE story_links; Type: COMMENT; Schema: snap; Owner: mediacloud
--

COMMENT ON TABLE snap.story_links IS 'story -> story links within a timespan';


--
-- Name: timespan_posts; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.timespan_posts (
    topic_posts_id integer NOT NULL,
    timespans_id integer NOT NULL
);


ALTER TABLE snap.timespan_posts OWNER TO mediacloud;

--
-- Name: topic_links_cross_media; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.topic_links_cross_media (
    snapshots_id integer NOT NULL,
    topic_links_id integer,
    topics_id integer NOT NULL,
    stories_id integer NOT NULL,
    url text NOT NULL,
    ref_stories_id integer
);


ALTER TABLE snap.topic_links_cross_media OWNER TO mediacloud;

--
-- Name: topic_media_codes; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.topic_media_codes (
    snapshots_id integer NOT NULL,
    topics_id integer NOT NULL,
    media_id integer NOT NULL,
    code_type text,
    code text
);


ALTER TABLE snap.topic_media_codes OWNER TO mediacloud;

--
-- Name: topic_stories; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.topic_stories (
    snapshots_id integer NOT NULL,
    topic_stories_id integer,
    topics_id integer NOT NULL,
    stories_id integer NOT NULL,
    link_mined boolean,
    iteration integer,
    link_weight real,
    redirect_url text,
    valid_foreign_rss_story boolean
);


ALTER TABLE snap.topic_stories OWNER TO mediacloud;

--
-- Name: word2vec_models; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.word2vec_models (
    word2vec_models_id integer NOT NULL,
    object_id integer NOT NULL,
    creation_date timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE snap.word2vec_models OWNER TO mediacloud;

--
-- Name: word2vec_models_data; Type: TABLE; Schema: snap; Owner: mediacloud
--

CREATE TABLE snap.word2vec_models_data (
    word2vec_models_data_id integer NOT NULL,
    object_id integer NOT NULL,
    raw_data bytea NOT NULL
);
ALTER TABLE ONLY snap.word2vec_models_data ALTER COLUMN raw_data SET STORAGE EXTERNAL;


ALTER TABLE snap.word2vec_models_data OWNER TO mediacloud;

--
-- Name: TABLE word2vec_models_data; Type: COMMENT; Schema: snap; Owner: mediacloud
--

COMMENT ON TABLE snap.word2vec_models_data IS 'Do not (attempt to) compress BLOBs in "raw_data" because 
they are going to be compressed already';


--
-- Name: word2vec_models_data_word2vec_models_data_id_seq; Type: SEQUENCE; Schema: snap; Owner: mediacloud
--

CREATE SEQUENCE snap.word2vec_models_data_word2vec_models_data_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE snap.word2vec_models_data_word2vec_models_data_id_seq OWNER TO mediacloud;

--
-- Name: word2vec_models_data_word2vec_models_data_id_seq; Type: SEQUENCE OWNED BY; Schema: snap; Owner: mediacloud
--

ALTER SEQUENCE snap.word2vec_models_data_word2vec_models_data_id_seq OWNED BY snap.word2vec_models_data.word2vec_models_data_id;


--
-- Name: word2vec_models_word2vec_models_id_seq; Type: SEQUENCE; Schema: snap; Owner: mediacloud
--

CREATE SEQUENCE snap.word2vec_models_word2vec_models_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE snap.word2vec_models_word2vec_models_id_seq OWNER TO mediacloud;

--
-- Name: word2vec_models_word2vec_models_id_seq; Type: SEQUENCE OWNED BY; Schema: snap; Owner: mediacloud
--

ALTER SEQUENCE snap.word2vec_models_word2vec_models_id_seq OWNED BY snap.word2vec_models.word2vec_models_id;


--
-- Name: extractor_results_cache extractor_results_cache_id; Type: DEFAULT; Schema: cache; Owner: mediacloud
--

ALTER TABLE ONLY cache.extractor_results_cache ALTER COLUMN extractor_results_cache_id SET DEFAULT nextval('cache.extractor_results_cache_extractor_results_cache_id_seq'::regclass);


--
-- Name: s3_raw_downloads_cache s3_raw_downloads_cache_id; Type: DEFAULT; Schema: cache; Owner: mediacloud
--

ALTER TABLE ONLY cache.s3_raw_downloads_cache ALTER COLUMN s3_raw_downloads_cache_id SET DEFAULT nextval('cache.s3_raw_downloads_cache_s3_raw_downloads_cache_id_seq'::regclass);


--
-- Name: activities activities_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.activities ALTER COLUMN activities_id SET DEFAULT nextval('public.activities_activities_id_seq'::regclass);


--
-- Name: api_links api_links_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.api_links ALTER COLUMN api_links_id SET DEFAULT nextval('public.api_links_api_links_id_seq'::regclass);


--
-- Name: auth_roles auth_roles_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_roles ALTER COLUMN auth_roles_id SET DEFAULT nextval('public.auth_roles_auth_roles_id_seq'::regclass);


--
-- Name: auth_user_api_keys auth_user_api_keys_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_user_api_keys ALTER COLUMN auth_user_api_keys_id SET DEFAULT nextval('public.auth_user_api_keys_auth_user_api_keys_id_seq'::regclass);


--
-- Name: auth_user_limits auth_user_limits_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_user_limits ALTER COLUMN auth_user_limits_id SET DEFAULT nextval('public.auth_user_limits_auth_user_limits_id_seq'::regclass);


--
-- Name: auth_user_request_daily_counts auth_user_request_daily_counts_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_user_request_daily_counts ALTER COLUMN auth_user_request_daily_counts_id SET DEFAULT nextval('public.auth_user_request_daily_count_auth_user_request_daily_count_seq'::regclass);


--
-- Name: auth_users auth_users_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_users ALTER COLUMN auth_users_id SET DEFAULT nextval('public.auth_users_auth_users_id_seq'::regclass);


--
-- Name: auth_users_roles_map auth_users_roles_map_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_users_roles_map ALTER COLUMN auth_users_roles_map_id SET DEFAULT nextval('public.auth_users_roles_map_auth_users_roles_map_id_seq'::regclass);


--
-- Name: auth_users_tag_sets_permissions auth_users_tag_sets_permissions_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_users_tag_sets_permissions ALTER COLUMN auth_users_tag_sets_permissions_id SET DEFAULT nextval('public.auth_users_tag_sets_permissio_auth_users_tag_sets_permissio_seq'::regclass);


--
-- Name: cliff_annotations cliff_annotations_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.cliff_annotations ALTER COLUMN cliff_annotations_id SET DEFAULT nextval('public.cliff_annotations_cliff_annotations_id_seq'::regclass);


--
-- Name: color_sets color_sets_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.color_sets ALTER COLUMN color_sets_id SET DEFAULT nextval('public.color_sets_color_sets_id_seq'::regclass);


--
-- Name: database_variables database_variables_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.database_variables ALTER COLUMN database_variables_id SET DEFAULT nextval('public.database_variables_database_variables_id_seq'::regclass);


--
-- Name: download_texts download_texts_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.download_texts ALTER COLUMN download_texts_id SET DEFAULT nextval('public.download_texts_download_texts_id_seq'::regclass);


--
-- Name: downloads downloads_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.downloads ALTER COLUMN downloads_id SET DEFAULT nextval('public.downloads_downloads_id_seq'::regclass);


--
-- Name: feeds feeds_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds ALTER COLUMN feeds_id SET DEFAULT nextval('public.feeds_feeds_id_seq'::regclass);


--
-- Name: feeds_after_rescraping feeds_after_rescraping_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_after_rescraping ALTER COLUMN feeds_after_rescraping_id SET DEFAULT nextval('public.feeds_after_rescraping_feeds_after_rescraping_id_seq'::regclass);


--
-- Name: feeds_stories_map feeds_stories_map_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_stories_map ALTER COLUMN feeds_stories_map_id SET DEFAULT nextval((pg_get_serial_sequence('feeds_stories_map_p'::text, 'feeds_stories_map_p_id'::text))::regclass);


--
-- Name: feeds_stories_map_p feeds_stories_map_p_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_stories_map_p ALTER COLUMN feeds_stories_map_p_id SET DEFAULT nextval('public.feeds_stories_map_p_feeds_stories_map_p_id_seq'::regclass);


--
-- Name: feeds_stories_map_p_00 feeds_stories_map_p_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_stories_map_p_00 ALTER COLUMN feeds_stories_map_p_id SET DEFAULT nextval('public.feeds_stories_map_p_feeds_stories_map_p_id_seq'::regclass);


--
-- Name: feeds_tags_map feeds_tags_map_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_tags_map ALTER COLUMN feeds_tags_map_id SET DEFAULT nextval('public.feeds_tags_map_feeds_tags_map_id_seq'::regclass);


--
-- Name: focal_set_definitions focal_set_definitions_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.focal_set_definitions ALTER COLUMN focal_set_definitions_id SET DEFAULT nextval('public.focal_set_definitions_focal_set_definitions_id_seq'::regclass);


--
-- Name: focal_sets focal_sets_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.focal_sets ALTER COLUMN focal_sets_id SET DEFAULT nextval('public.focal_sets_focal_sets_id_seq'::regclass);


--
-- Name: foci foci_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.foci ALTER COLUMN foci_id SET DEFAULT nextval('public.foci_foci_id_seq'::regclass);


--
-- Name: focus_definitions focus_definitions_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.focus_definitions ALTER COLUMN focus_definitions_id SET DEFAULT nextval('public.focus_definitions_focus_definitions_id_seq'::regclass);


--
-- Name: job_states job_states_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.job_states ALTER COLUMN job_states_id SET DEFAULT nextval('public.job_states_job_states_id_seq'::regclass);


--
-- Name: media media_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media ALTER COLUMN media_id SET DEFAULT nextval('public.media_media_id_seq'::regclass);


--
-- Name: media_health media_health_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_health ALTER COLUMN media_health_id SET DEFAULT nextval('public.media_health_media_health_id_seq'::regclass);


--
-- Name: media_similarweb_domains_map media_similarweb_domains_map_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_similarweb_domains_map ALTER COLUMN media_similarweb_domains_map_id SET DEFAULT nextval('public.media_similarweb_domains_map_media_similarweb_domains_map_i_seq'::regclass);


--
-- Name: media_sitemap_pages media_sitemap_pages_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_sitemap_pages ALTER COLUMN media_sitemap_pages_id SET DEFAULT nextval('public.media_sitemap_pages_media_sitemap_pages_id_seq'::regclass);


--
-- Name: media_stats media_stats_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_stats ALTER COLUMN media_stats_id SET DEFAULT nextval('public.media_stats_media_stats_id_seq'::regclass);


--
-- Name: media_suggestions media_suggestions_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_suggestions ALTER COLUMN media_suggestions_id SET DEFAULT nextval('public.media_suggestions_media_suggestions_id_seq'::regclass);


--
-- Name: media_tags_map media_tags_map_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_tags_map ALTER COLUMN media_tags_map_id SET DEFAULT nextval('public.media_tags_map_media_tags_map_id_seq'::regclass);


--
-- Name: mediacloud_stats mediacloud_stats_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.mediacloud_stats ALTER COLUMN mediacloud_stats_id SET DEFAULT nextval('public.mediacloud_stats_mediacloud_stats_id_seq'::regclass);


--
-- Name: nytlabels_annotations nytlabels_annotations_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.nytlabels_annotations ALTER COLUMN nytlabels_annotations_id SET DEFAULT nextval('public.nytlabels_annotations_nytlabels_annotations_id_seq'::regclass);


--
-- Name: processed_stories processed_stories_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.processed_stories ALTER COLUMN processed_stories_id SET DEFAULT nextval('public.processed_stories_processed_stories_id_seq'::regclass);


--
-- Name: queued_downloads queued_downloads_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.queued_downloads ALTER COLUMN queued_downloads_id SET DEFAULT nextval('public.queued_downloads_queued_downloads_id_seq'::regclass);


--
-- Name: raw_downloads raw_downloads_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.raw_downloads ALTER COLUMN raw_downloads_id SET DEFAULT nextval('public.raw_downloads_raw_downloads_id_seq'::regclass);


--
-- Name: retweeter_groups retweeter_groups_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_groups ALTER COLUMN retweeter_groups_id SET DEFAULT nextval('public.retweeter_groups_retweeter_groups_id_seq'::regclass);


--
-- Name: retweeter_media retweeter_media_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_media ALTER COLUMN retweeter_media_id SET DEFAULT nextval('public.retweeter_media_retweeter_media_id_seq'::regclass);


--
-- Name: retweeter_partition_matrix retweeter_partition_matrix_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_partition_matrix ALTER COLUMN retweeter_partition_matrix_id SET DEFAULT nextval('public.retweeter_partition_matrix_retweeter_partition_matrix_id_seq'::regclass);


--
-- Name: retweeter_scores retweeter_scores_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_scores ALTER COLUMN retweeter_scores_id SET DEFAULT nextval('public.retweeter_scores_retweeter_scores_id_seq'::regclass);


--
-- Name: retweeter_stories retweeter_shares_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_stories ALTER COLUMN retweeter_shares_id SET DEFAULT nextval('public.retweeter_stories_retweeter_shares_id_seq'::regclass);


--
-- Name: retweeters retweeters_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeters ALTER COLUMN retweeters_id SET DEFAULT nextval('public.retweeters_retweeters_id_seq'::regclass);


--
-- Name: scraped_feeds feed_scrapes_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.scraped_feeds ALTER COLUMN feed_scrapes_id SET DEFAULT nextval('public.scraped_feeds_feed_scrapes_id_seq'::regclass);


--
-- Name: scraped_stories scraped_stories_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.scraped_stories ALTER COLUMN scraped_stories_id SET DEFAULT nextval('public.scraped_stories_scraped_stories_id_seq'::regclass);


--
-- Name: similarweb_domains similarweb_domains_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.similarweb_domains ALTER COLUMN similarweb_domains_id SET DEFAULT nextval('public.similarweb_domains_similarweb_domains_id_seq'::regclass);


--
-- Name: similarweb_estimated_visits similarweb_estimated_visits_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.similarweb_estimated_visits ALTER COLUMN similarweb_estimated_visits_id SET DEFAULT nextval('public.similarweb_estimated_visits_similarweb_estimated_visits_id_seq'::regclass);


--
-- Name: snapshot_files snapshot_files_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.snapshot_files ALTER COLUMN snapshot_files_id SET DEFAULT nextval('public.snapshot_files_snapshot_files_id_seq'::regclass);


--
-- Name: snapshots snapshots_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.snapshots ALTER COLUMN snapshots_id SET DEFAULT nextval('public.snapshots_snapshots_id_seq'::regclass);


--
-- Name: solr_imports solr_imports_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.solr_imports ALTER COLUMN solr_imports_id SET DEFAULT nextval('public.solr_imports_solr_imports_id_seq'::regclass);


--
-- Name: stories stories_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories ALTER COLUMN stories_id SET DEFAULT nextval('public.stories_stories_id_seq'::regclass);


--
-- Name: stories_ap_syndicated stories_ap_syndicated_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories_ap_syndicated ALTER COLUMN stories_ap_syndicated_id SET DEFAULT nextval('public.stories_ap_syndicated_stories_ap_syndicated_id_seq'::regclass);


--
-- Name: stories_tags_map stories_tags_map_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories_tags_map ALTER COLUMN stories_tags_map_id SET DEFAULT nextval((pg_get_serial_sequence('stories_tags_map_p'::text, 'stories_tags_map_p_id'::text))::regclass);


--
-- Name: stories_tags_map_p stories_tags_map_p_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories_tags_map_p ALTER COLUMN stories_tags_map_p_id SET DEFAULT nextval('public.stories_tags_map_p_stories_tags_map_p_id_seq'::regclass);


--
-- Name: stories_tags_map_p_00 stories_tags_map_p_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories_tags_map_p_00 ALTER COLUMN stories_tags_map_p_id SET DEFAULT nextval('public.stories_tags_map_p_stories_tags_map_p_id_seq'::regclass);


--
-- Name: story_enclosures story_enclosures_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_enclosures ALTER COLUMN story_enclosures_id SET DEFAULT nextval('public.story_enclosures_story_enclosures_id_seq'::regclass);


--
-- Name: story_sentences story_sentences_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_sentences ALTER COLUMN story_sentences_id SET DEFAULT nextval((pg_get_serial_sequence('story_sentences_p'::text, 'story_sentences_p_id'::text))::regclass);


--
-- Name: story_sentences_p story_sentences_p_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_sentences_p ALTER COLUMN story_sentences_p_id SET DEFAULT nextval('public.story_sentences_p_story_sentences_p_id_seq'::regclass);


--
-- Name: story_sentences_p_00 story_sentences_p_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_sentences_p_00 ALTER COLUMN story_sentences_p_id SET DEFAULT nextval('public.story_sentences_p_story_sentences_p_id_seq'::regclass);


--
-- Name: story_statistics story_statistics_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_statistics ALTER COLUMN story_statistics_id SET DEFAULT nextval('public.story_statistics_story_statistics_id_seq'::regclass);


--
-- Name: story_statistics_twitter story_statistics_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_statistics_twitter ALTER COLUMN story_statistics_id SET DEFAULT nextval('public.story_statistics_twitter_story_statistics_id_seq'::regclass);


--
-- Name: story_urls story_urls_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_urls ALTER COLUMN story_urls_id SET DEFAULT nextval('public.story_urls_story_urls_id_seq'::regclass);


--
-- Name: tag_sets tag_sets_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.tag_sets ALTER COLUMN tag_sets_id SET DEFAULT nextval('public.tag_sets_tag_sets_id_seq'::regclass);


--
-- Name: tags tags_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.tags ALTER COLUMN tags_id SET DEFAULT nextval('public.tags_tags_id_seq'::regclass);


--
-- Name: timespan_files timespan_files_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.timespan_files ALTER COLUMN timespan_files_id SET DEFAULT nextval('public.timespan_files_timespan_files_id_seq'::regclass);


--
-- Name: timespan_maps timespan_maps_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.timespan_maps ALTER COLUMN timespan_maps_id SET DEFAULT nextval('public.timespan_maps_timespan_maps_id_seq'::regclass);


--
-- Name: timespans timespans_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.timespans ALTER COLUMN timespans_id SET DEFAULT nextval('public.timespans_timespans_id_seq'::regclass);


--
-- Name: topic_dates topic_dates_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_dates ALTER COLUMN topic_dates_id SET DEFAULT nextval('public.topic_dates_topic_dates_id_seq'::regclass);


--
-- Name: topic_dead_links topic_dead_links_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_dead_links ALTER COLUMN topic_dead_links_id SET DEFAULT nextval('public.topic_dead_links_topic_dead_links_id_seq'::regclass);


--
-- Name: topic_domains topic_domains_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_domains ALTER COLUMN topic_domains_id SET DEFAULT nextval('public.topic_domains_topic_domains_id_seq'::regclass);


--
-- Name: topic_fetch_urls topic_fetch_urls_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_fetch_urls ALTER COLUMN topic_fetch_urls_id SET DEFAULT nextval('public.topic_fetch_urls_topic_fetch_urls_id_seq'::regclass);


--
-- Name: topic_ignore_redirects topic_ignore_redirects_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_ignore_redirects ALTER COLUMN topic_ignore_redirects_id SET DEFAULT nextval('public.topic_ignore_redirects_topic_ignore_redirects_id_seq'::regclass);


--
-- Name: topic_links topic_links_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_links ALTER COLUMN topic_links_id SET DEFAULT nextval('public.topic_links_topic_links_id_seq'::regclass);


--
-- Name: topic_modes topic_modes_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_modes ALTER COLUMN topic_modes_id SET DEFAULT nextval('public.topic_modes_topic_modes_id_seq'::regclass);


--
-- Name: topic_permissions topic_permissions_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_permissions ALTER COLUMN topic_permissions_id SET DEFAULT nextval('public.topic_permissions_topic_permissions_id_seq'::regclass);


--
-- Name: topic_platforms topic_platforms_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_platforms ALTER COLUMN topic_platforms_id SET DEFAULT nextval('public.topic_platforms_topic_platforms_id_seq'::regclass);


--
-- Name: topic_post_days topic_post_days_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_post_days ALTER COLUMN topic_post_days_id SET DEFAULT nextval('public.topic_post_days_topic_post_days_id_seq'::regclass);


--
-- Name: topic_post_urls topic_post_urls_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_post_urls ALTER COLUMN topic_post_urls_id SET DEFAULT nextval('public.topic_post_urls_topic_post_urls_id_seq'::regclass);


--
-- Name: topic_posts topic_posts_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_posts ALTER COLUMN topic_posts_id SET DEFAULT nextval('public.topic_posts_topic_posts_id_seq'::regclass);


--
-- Name: topic_seed_queries topic_seed_queries_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_seed_queries ALTER COLUMN topic_seed_queries_id SET DEFAULT nextval('public.topic_seed_queries_topic_seed_queries_id_seq'::regclass);


--
-- Name: topic_seed_urls topic_seed_urls_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_seed_urls ALTER COLUMN topic_seed_urls_id SET DEFAULT nextval('public.topic_seed_urls_topic_seed_urls_id_seq'::regclass);


--
-- Name: topic_sources topic_sources_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_sources ALTER COLUMN topic_sources_id SET DEFAULT nextval('public.topic_sources_topic_sources_id_seq'::regclass);


--
-- Name: topic_spider_metrics topic_spider_metrics_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_spider_metrics ALTER COLUMN topic_spider_metrics_id SET DEFAULT nextval('public.topic_spider_metrics_topic_spider_metrics_id_seq'::regclass);


--
-- Name: topic_stories topic_stories_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_stories ALTER COLUMN topic_stories_id SET DEFAULT nextval('public.topic_stories_topic_stories_id_seq'::regclass);


--
-- Name: topics topics_id; Type: DEFAULT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topics ALTER COLUMN topics_id SET DEFAULT nextval('public.topics_topics_id_seq'::regclass);


--
-- Name: snapshot_files snapshot_files_id; Type: DEFAULT; Schema: public_store; Owner: mediacloud
--

ALTER TABLE ONLY public_store.snapshot_files ALTER COLUMN snapshot_files_id SET DEFAULT nextval('public_store.snapshot_files_snapshot_files_id_seq'::regclass);


--
-- Name: timespan_files timespan_files_id; Type: DEFAULT; Schema: public_store; Owner: mediacloud
--

ALTER TABLE ONLY public_store.timespan_files ALTER COLUMN timespan_files_id SET DEFAULT nextval('public_store.timespan_files_timespan_files_id_seq'::regclass);


--
-- Name: timespan_maps timespan_maps_id; Type: DEFAULT; Schema: public_store; Owner: mediacloud
--

ALTER TABLE ONLY public_store.timespan_maps ALTER COLUMN timespan_maps_id SET DEFAULT nextval('public_store.timespan_maps_timespan_maps_id_seq'::regclass);


--
-- Name: word2vec_models word2vec_models_id; Type: DEFAULT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.word2vec_models ALTER COLUMN word2vec_models_id SET DEFAULT nextval('snap.word2vec_models_word2vec_models_id_seq'::regclass);


--
-- Name: word2vec_models_data word2vec_models_data_id; Type: DEFAULT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.word2vec_models_data ALTER COLUMN word2vec_models_data_id SET DEFAULT nextval('snap.word2vec_models_data_word2vec_models_data_id_seq'::regclass);


--
-- Data for Name: extractor_results_cache; Type: TABLE DATA; Schema: cache; Owner: mediacloud
--

COPY cache.extractor_results_cache (extractor_results_cache_id, extracted_html, extracted_text, downloads_id, db_row_last_updated) FROM stdin;
\.


--
-- Data for Name: s3_raw_downloads_cache; Type: TABLE DATA; Schema: cache; Owner: mediacloud
--

COPY cache.s3_raw_downloads_cache (s3_raw_downloads_cache_id, object_id, db_row_last_updated, raw_data) FROM stdin;
\.


--
-- Data for Name: activities; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.activities (activities_id, name, creation_date, user_identifier, object_id, reason, description_json) FROM stdin;
\.


--
-- Data for Name: api_links; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.api_links (api_links_id, path, params_json, next_link_id, previous_link_id) FROM stdin;
\.


--
-- Data for Name: auth_roles; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.auth_roles (auth_roles_id, role, description) FROM stdin;
1	admin	Do everything, including editing users.
2	admin-readonly	Read access to admin interface.
3	media-edit	Add / edit media; includes feeds.
4	stories-edit	Add / edit stories.
5	tm	Topic mapper; includes media and story editing
6	tm-readonly	Topic mapper; excludes media and story editing
7	stories-api	Access to the stories api
\.


--
-- Data for Name: auth_user_api_keys; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.auth_user_api_keys (auth_user_api_keys_id, auth_users_id, api_key, ip_address) FROM stdin;
\.


--
-- Data for Name: auth_user_limits; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.auth_user_limits (auth_user_limits_id, auth_users_id, weekly_requests_limit, weekly_requested_items_limit, max_topic_stories) FROM stdin;
\.


--
-- Data for Name: auth_user_request_daily_counts; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.auth_user_request_daily_counts (auth_user_request_daily_counts_id, email, day, requests_count, requested_items_count) FROM stdin;
\.


--
-- Data for Name: auth_users; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.auth_users (auth_users_id, email, password_hash, full_name, notes, active, password_reset_token_hash, last_unsuccessful_login_attempt, created_date, has_consented) FROM stdin;
\.


--
-- Data for Name: auth_users_roles_map; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.auth_users_roles_map (auth_users_roles_map_id, auth_users_id, auth_roles_id) FROM stdin;
\.


--
-- Data for Name: auth_users_tag_sets_permissions; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.auth_users_tag_sets_permissions (auth_users_tag_sets_permissions_id, auth_users_id, tag_sets_id, apply_tags, create_tags, edit_tag_set_descriptors, edit_tag_descriptors) FROM stdin;
\.


--
-- Data for Name: celery_groups; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.celery_groups (id, taskset_id, result, date_done) FROM stdin;
\.


--
-- Data for Name: celery_tasks; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.celery_tasks (id, task_id, status, result, date_done, traceback) FROM stdin;
\.


--
-- Data for Name: cliff_annotations; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.cliff_annotations (cliff_annotations_id, object_id, raw_data) FROM stdin;
\.


--
-- Data for Name: color_sets; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.color_sets (color_sets_id, color, color_set, id) FROM stdin;
1	c10032	partisan_code	partisan_2012_conservative
2	00519b	partisan_code	partisan_2012_liberal
3	009543	partisan_code	partisan_2012_libertarian
\.


--
-- Data for Name: database_variables; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.database_variables (database_variables_id, name, value) FROM stdin;
\.


--
-- Data for Name: domain_web_requests; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.domain_web_requests (domain, request_time) FROM stdin;
\.


--
-- Data for Name: download_texts_00; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.download_texts_00 (download_texts_id, downloads_id, download_text, download_text_length) FROM stdin;
\.


--
-- Data for Name: downloads_error; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.downloads_error (downloads_id, feeds_id, stories_id, parent, url, host, download_time, type, state, path, error_message, priority, sequence, extracted) FROM stdin;
\.


--
-- Data for Name: downloads_feed_error; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.downloads_feed_error (downloads_id, feeds_id, stories_id, parent, url, host, download_time, type, state, path, error_message, priority, sequence, extracted) FROM stdin;
\.


--
-- Data for Name: downloads_fetching; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.downloads_fetching (downloads_id, feeds_id, stories_id, parent, url, host, download_time, type, state, path, error_message, priority, sequence, extracted) FROM stdin;
\.


--
-- Data for Name: downloads_pending; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.downloads_pending (downloads_id, feeds_id, stories_id, parent, url, host, download_time, type, state, path, error_message, priority, sequence, extracted) FROM stdin;
\.


--
-- Data for Name: downloads_success_content_00; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.downloads_success_content_00 (downloads_id, feeds_id, stories_id, parent, url, host, download_time, type, state, path, error_message, priority, sequence, extracted) FROM stdin;
\.


--
-- Data for Name: downloads_success_feed_00; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.downloads_success_feed_00 (downloads_id, feeds_id, stories_id, parent, url, host, download_time, type, state, path, error_message, priority, sequence, extracted) FROM stdin;
\.


--
-- Data for Name: feeds; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.feeds (feeds_id, media_id, name, url, type, active, last_checksum, last_attempted_download_time, last_successful_download_time, last_new_story_time) FROM stdin;
\.


--
-- Data for Name: feeds_after_rescraping; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.feeds_after_rescraping (feeds_after_rescraping_id, media_id, name, url, type) FROM stdin;
\.


--
-- Data for Name: feeds_from_yesterday; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.feeds_from_yesterday (feeds_id, media_id, name, url, type, active) FROM stdin;
\.


--
-- Data for Name: feeds_stories_map_p; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.feeds_stories_map_p (feeds_stories_map_p_id, feeds_id, stories_id) FROM stdin;
\.


--
-- Data for Name: feeds_stories_map_p_00; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.feeds_stories_map_p_00 (feeds_stories_map_p_id, feeds_id, stories_id) FROM stdin;
\.


--
-- Data for Name: feeds_tags_map; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.feeds_tags_map (feeds_tags_map_id, feeds_id, tags_id) FROM stdin;
\.


--
-- Data for Name: focal_set_definitions; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.focal_set_definitions (focal_set_definitions_id, topics_id, name, description, focal_technique) FROM stdin;
\.


--
-- Data for Name: focal_sets; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.focal_sets (focal_sets_id, snapshots_id, name, description, focal_technique) FROM stdin;
\.


--
-- Data for Name: foci; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.foci (foci_id, focal_sets_id, name, description, arguments) FROM stdin;
\.


--
-- Data for Name: focus_definitions; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.focus_definitions (focus_definitions_id, focal_set_definitions_id, name, description, arguments) FROM stdin;
\.


--
-- Data for Name: job_states; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.job_states (job_states_id, class, state, message, last_updated, args, priority, hostname, process_id) FROM stdin;
\.


--
-- Data for Name: media; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.media (media_id, url, normalized_url, name, full_text_rss, foreign_rss_links, dup_media_id, is_not_dup, content_delay, editor_notes, public_notes, is_monitored) FROM stdin;
\.


--
-- Data for Name: media_coverage_gaps; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.media_coverage_gaps (media_id, stat_week, num_stories, expected_stories, num_sentences, expected_sentences) FROM stdin;
\.


--
-- Data for Name: media_expected_volume; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.media_expected_volume (media_id, start_date, end_date, expected_stories, expected_sentences) FROM stdin;
\.


--
-- Data for Name: media_health; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.media_health (media_health_id, media_id, num_stories, num_stories_y, num_stories_w, num_stories_90, num_sentences, num_sentences_y, num_sentences_w, num_sentences_90, is_healthy, has_active_feed, start_date, end_date, expected_sentences, expected_stories, coverage_gaps) FROM stdin;
\.


--
-- Data for Name: media_rescraping; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.media_rescraping (media_id, disable, last_rescrape_time) FROM stdin;
\.


--
-- Data for Name: media_similarweb_domains_map; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.media_similarweb_domains_map (media_similarweb_domains_map_id, media_id, similarweb_domains_id) FROM stdin;
\.


--
-- Data for Name: media_sitemap_pages; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.media_sitemap_pages (media_sitemap_pages_id, media_id, url, last_modified, change_frequency, priority, news_title, news_publish_date) FROM stdin;
\.


--
-- Data for Name: media_stats; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.media_stats (media_stats_id, media_id, num_stories, num_sentences, stat_date) FROM stdin;
\.


--
-- Data for Name: media_stats_weekly; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.media_stats_weekly (media_id, stories_rank, num_stories, sentences_rank, num_sentences, stat_week) FROM stdin;
\.


--
-- Data for Name: media_suggestions; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.media_suggestions (media_suggestions_id, name, url, feed_url, reason, auth_users_id, mark_auth_users_id, date_submitted, media_id, date_marked, mark_reason, status) FROM stdin;
\.


--
-- Data for Name: media_suggestions_tags_map; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.media_suggestions_tags_map (media_suggestions_id, tags_id) FROM stdin;
\.


--
-- Data for Name: media_tags_map; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.media_tags_map (media_tags_map_id, media_id, tags_id, tagged_date) FROM stdin;
\.


--
-- Data for Name: mediacloud_stats; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.mediacloud_stats (mediacloud_stats_id, stats_date, daily_downloads, daily_stories, active_crawled_media, active_crawled_feeds, total_stories, total_downloads, total_sentences) FROM stdin;
\.


--
-- Data for Name: nytlabels_annotations; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.nytlabels_annotations (nytlabels_annotations_id, object_id, raw_data) FROM stdin;
\.


--
-- Data for Name: processed_stories; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.processed_stories (processed_stories_id, stories_id) FROM stdin;
\.


--
-- Data for Name: queued_downloads; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.queued_downloads (queued_downloads_id, downloads_id) FROM stdin;
\.


--
-- Data for Name: raw_downloads; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.raw_downloads (raw_downloads_id, object_id, raw_data) FROM stdin;
\.


--
-- Data for Name: retweeter_groups; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.retweeter_groups (retweeter_groups_id, retweeter_scores_id, name) FROM stdin;
\.


--
-- Data for Name: retweeter_groups_users_map; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.retweeter_groups_users_map (retweeter_groups_id, retweeter_scores_id, retweeted_user) FROM stdin;
\.


--
-- Data for Name: retweeter_media; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.retweeter_media (retweeter_media_id, retweeter_scores_id, media_id, group_a_count, group_b_count, group_a_count_n, score, partition) FROM stdin;
\.


--
-- Data for Name: retweeter_partition_matrix; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.retweeter_partition_matrix (retweeter_partition_matrix_id, retweeter_scores_id, retweeter_groups_id, group_name, share_count, group_proportion, partition) FROM stdin;
\.


--
-- Data for Name: retweeter_scores; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.retweeter_scores (retweeter_scores_id, topics_id, group_a_id, group_b_id, name, state, message, num_partitions, match_type) FROM stdin;
\.


--
-- Data for Name: retweeter_stories; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.retweeter_stories (retweeter_shares_id, retweeter_scores_id, stories_id, retweeted_user, share_count) FROM stdin;
\.


--
-- Data for Name: retweeters; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.retweeters (retweeters_id, retweeter_scores_id, twitter_user, retweeted_user) FROM stdin;
\.


--
-- Data for Name: schema_version; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.schema_version (version, description, type, installed_by, installed_on) FROM stdin;
1	initial schema	auto	mediacloud	2021-06-25 16:30:14.821324
2	drop db version var	auto	mediacloud	2021-06-25 16:30:14.821324
3	drop db version func	auto	mediacloud	2021-06-25 16:30:14.821324
\.


--
-- Data for Name: scraped_feeds; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.scraped_feeds (feed_scrapes_id, feeds_id, scrape_date, import_module) FROM stdin;
\.


--
-- Data for Name: scraped_stories; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.scraped_stories (scraped_stories_id, stories_id, import_module) FROM stdin;
\.


--
-- Data for Name: similarweb_domains; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.similarweb_domains (similarweb_domains_id, domain) FROM stdin;
\.


--
-- Data for Name: similarweb_estimated_visits; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.similarweb_estimated_visits (similarweb_estimated_visits_id, similarweb_domains_id, month, main_domain_only, visits) FROM stdin;
\.


--
-- Data for Name: snapshot_files; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.snapshot_files (snapshot_files_id, snapshots_id, name, url) FROM stdin;
\.


--
-- Data for Name: snapshots; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.snapshots (snapshots_id, topics_id, snapshot_date, start_date, end_date, note, state, message, searchable, bot_policy, seed_queries) FROM stdin;
\.


--
-- Data for Name: solr_import_stories; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.solr_import_stories (stories_id) FROM stdin;
\.


--
-- Data for Name: solr_imported_stories; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.solr_imported_stories (stories_id, import_date) FROM stdin;
\.


--
-- Data for Name: solr_imports; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.solr_imports (solr_imports_id, import_date, full_import, num_stories) FROM stdin;
\.


--
-- Data for Name: stories; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.stories (stories_id, media_id, url, guid, title, normalized_title_hash, description, publish_date, collect_date, full_text_rss, language) FROM stdin;
\.


--
-- Data for Name: stories_ap_syndicated; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.stories_ap_syndicated (stories_ap_syndicated_id, stories_id, ap_syndicated) FROM stdin;
\.


--
-- Data for Name: stories_tags_map_p; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.stories_tags_map_p (stories_tags_map_p_id, stories_id, tags_id) FROM stdin;
\.


--
-- Data for Name: stories_tags_map_p_00; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.stories_tags_map_p_00 (stories_tags_map_p_id, stories_id, tags_id) FROM stdin;
\.


--
-- Data for Name: story_enclosures; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.story_enclosures (story_enclosures_id, stories_id, url, mime_type, length) FROM stdin;
\.


--
-- Data for Name: story_sentences_p; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.story_sentences_p (story_sentences_p_id, stories_id, sentence_number, sentence, media_id, publish_date, language, is_dup) FROM stdin;
\.


--
-- Data for Name: story_sentences_p_00; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.story_sentences_p_00 (story_sentences_p_id, stories_id, sentence_number, sentence, media_id, publish_date, language, is_dup) FROM stdin;
\.


--
-- Data for Name: story_statistics; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.story_statistics (story_statistics_id, stories_id, facebook_share_count, facebook_comment_count, facebook_reaction_count, facebook_api_collect_date, facebook_api_error) FROM stdin;
\.


--
-- Data for Name: story_statistics_twitter; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.story_statistics_twitter (story_statistics_id, stories_id, twitter_url_tweet_count, twitter_api_collect_date, twitter_api_error) FROM stdin;
\.


--
-- Data for Name: story_urls; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.story_urls (story_urls_id, stories_id, url) FROM stdin;
\.


--
-- Data for Name: tag_sets; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.tag_sets (tag_sets_id, name, label, description, show_on_media, show_on_stories) FROM stdin;
1	media_type	Media Type	High level topology for media sources for use across a variety of different topics	\N	\N
\.


--
-- Data for Name: tags; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.tags (tags_id, tag_sets_id, tag, label, description, show_on_media, show_on_stories, is_static) FROM stdin;
\.


--
-- Data for Name: timespan_files; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.timespan_files (timespan_files_id, timespans_id, name, url) FROM stdin;
\.


--
-- Data for Name: timespan_maps; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.timespan_maps (timespan_maps_id, timespans_id, options, content, url, format) FROM stdin;
\.


--
-- Data for Name: timespans; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.timespans (timespans_id, snapshots_id, archive_snapshots_id, foci_id, start_date, end_date, period, model_r2_mean, model_r2_stddev, model_num_media, story_count, story_link_count, medium_count, medium_link_count, post_count, tags_id) FROM stdin;
\.


--
-- Data for Name: topic_dates; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_dates (topic_dates_id, topics_id, start_date, end_date, boundary) FROM stdin;
\.


--
-- Data for Name: topic_dead_links; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_dead_links (topic_dead_links_id, topics_id, stories_id, url) FROM stdin;
\.


--
-- Data for Name: topic_domains; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_domains (topic_domains_id, topics_id, domain, self_links) FROM stdin;
\.


--
-- Data for Name: topic_fetch_urls; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_fetch_urls (topic_fetch_urls_id, topics_id, url, code, fetch_date, state, message, stories_id, assume_match, topic_links_id) FROM stdin;
\.


--
-- Data for Name: topic_ignore_redirects; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_ignore_redirects (topic_ignore_redirects_id, url) FROM stdin;
\.


--
-- Data for Name: topic_links; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_links (topic_links_id, topics_id, stories_id, url, redirect_url, ref_stories_id, link_spidered) FROM stdin;
\.


--
-- Data for Name: topic_media_codes; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_media_codes (topics_id, media_id, code_type, code) FROM stdin;
\.


--
-- Data for Name: topic_merged_stories_map; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_merged_stories_map (source_stories_id, target_stories_id) FROM stdin;
\.


--
-- Data for Name: topic_modes; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_modes (topic_modes_id, name, description) FROM stdin;
1	web	analyze urls using hyperlinks as network edges
2	url_sharing	analyze urls shared on social media using co-sharing as network edges
\.


--
-- Data for Name: topic_permissions; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_permissions (topic_permissions_id, topics_id, auth_users_id, permission) FROM stdin;
\.


--
-- Data for Name: topic_platforms; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_platforms (topic_platforms_id, name, description) FROM stdin;
1	web	pages on the open web
2	twitter	tweets from twitter.com
3	generic_post	generic social media posts
4	reddit	submissions and comments from reddit.com
\.


--
-- Data for Name: topic_platforms_sources_map; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_platforms_sources_map (topic_platforms_id, topic_sources_id) FROM stdin;
1	1
2	2
3	4
3	5
4	6
1	7
\.


--
-- Data for Name: topic_post_days; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_post_days (topic_post_days_id, topic_seed_queries_id, day, num_posts_stored, num_posts_fetched, posts_fetched) FROM stdin;
\.


--
-- Data for Name: topic_post_urls; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_post_urls (topic_post_urls_id, topic_posts_id, url) FROM stdin;
\.


--
-- Data for Name: topic_posts; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_posts (topic_posts_id, topic_post_days_id, data, post_id, content, publish_date, author, channel, url) FROM stdin;
\.


--
-- Data for Name: topic_query_story_searches_imported_stories_map; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_query_story_searches_imported_stories_map (topics_id, stories_id) FROM stdin;
\.


--
-- Data for Name: topic_seed_queries; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_seed_queries (topic_seed_queries_id, topics_id, source, platform, query, imported_date, ignore_pattern) FROM stdin;
\.


--
-- Data for Name: topic_seed_urls; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_seed_urls (topic_seed_urls_id, topics_id, url, source, stories_id, processed, assume_match, content, guid, title, publish_date, topic_seed_queries_id, topic_post_urls_id) FROM stdin;
\.


--
-- Data for Name: topic_sources; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_sources (topic_sources_id, name, description) FROM stdin;
1	mediacloud	import from the mediacloud.org archive
2	crimson_hexagon	import from the crimsonhexagon.com forsight api, only accessible to internal media cloud team
3	brandwatch	import from the brandwatch api, only accessible to internal media cloud team
4	csv	import generic posts directly from csv
5	postgres	import generic posts from a postgres table
6	pushshift	import from the pushshift.io api
7	google	import from search results on google
\.


--
-- Data for Name: topic_spider_metrics; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_spider_metrics (topic_spider_metrics_id, topics_id, iteration, links_processed, elapsed_time, processed_date) FROM stdin;
\.


--
-- Data for Name: topic_stories; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topic_stories (topic_stories_id, topics_id, stories_id, link_mined, iteration, link_weight, redirect_url, valid_foreign_rss_story, link_mine_error) FROM stdin;
\.


--
-- Data for Name: topics; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topics (topics_id, name, pattern, solr_seed_query, solr_seed_query_run, description, media_type_tag_sets_id, max_iterations, state, message, is_public, is_logogram, start_date, end_date, respider_stories, respider_start_date, respider_end_date, snapshot_periods, platform, mode, job_queue, max_stories, is_story_index_ready, only_snapshot_engaged_stories) FROM stdin;
\.


--
-- Data for Name: topics_media_map; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topics_media_map (topics_id, media_id) FROM stdin;
\.


--
-- Data for Name: topics_media_tags_map; Type: TABLE DATA; Schema: public; Owner: mediacloud
--

COPY public.topics_media_tags_map (topics_id, tags_id) FROM stdin;
\.


--
-- Data for Name: snapshot_files; Type: TABLE DATA; Schema: public_store; Owner: mediacloud
--

COPY public_store.snapshot_files (snapshot_files_id, object_id, raw_data) FROM stdin;
\.


--
-- Data for Name: timespan_files; Type: TABLE DATA; Schema: public_store; Owner: mediacloud
--

COPY public_store.timespan_files (timespan_files_id, object_id, raw_data) FROM stdin;
\.


--
-- Data for Name: timespan_maps; Type: TABLE DATA; Schema: public_store; Owner: mediacloud
--

COPY public_store.timespan_maps (timespan_maps_id, object_id, raw_data) FROM stdin;
\.


--
-- Data for Name: live_stories; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.live_stories (topics_id, topic_stories_id, stories_id, media_id, url, guid, title, normalized_title_hash, description, publish_date, collect_date, full_text_rss, language) FROM stdin;
\.


--
-- Data for Name: media; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.media (snapshots_id, media_id, url, name, full_text_rss, foreign_rss_links, dup_media_id, is_not_dup) FROM stdin;
\.


--
-- Data for Name: media_tags_map; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.media_tags_map (snapshots_id, media_tags_map_id, media_id, tags_id) FROM stdin;
\.


--
-- Data for Name: medium_link_counts; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.medium_link_counts (timespans_id, media_id, sum_media_inlink_count, media_inlink_count, inlink_count, outlink_count, story_count, facebook_share_count, sum_post_count, sum_author_count, sum_channel_count) FROM stdin;
\.


--
-- Data for Name: medium_links; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.medium_links (timespans_id, source_media_id, ref_media_id, link_count) FROM stdin;
\.


--
-- Data for Name: stories; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.stories (snapshots_id, stories_id, media_id, url, guid, title, publish_date, collect_date, full_text_rss, language) FROM stdin;
\.


--
-- Data for Name: stories_tags_map; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.stories_tags_map (snapshots_id, stories_tags_map_id, stories_id, tags_id) FROM stdin;
\.


--
-- Data for Name: story_link_counts; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.story_link_counts (timespans_id, stories_id, media_inlink_count, inlink_count, outlink_count, facebook_share_count, post_count, author_count, channel_count) FROM stdin;
\.


--
-- Data for Name: story_links; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.story_links (timespans_id, source_stories_id, ref_stories_id) FROM stdin;
\.


--
-- Data for Name: timespan_posts; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.timespan_posts (topic_posts_id, timespans_id) FROM stdin;
\.


--
-- Data for Name: topic_links_cross_media; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.topic_links_cross_media (snapshots_id, topic_links_id, topics_id, stories_id, url, ref_stories_id) FROM stdin;
\.


--
-- Data for Name: topic_media_codes; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.topic_media_codes (snapshots_id, topics_id, media_id, code_type, code) FROM stdin;
\.


--
-- Data for Name: topic_stories; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.topic_stories (snapshots_id, topic_stories_id, topics_id, stories_id, link_mined, iteration, link_weight, redirect_url, valid_foreign_rss_story) FROM stdin;
\.


--
-- Data for Name: word2vec_models; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.word2vec_models (word2vec_models_id, object_id, creation_date) FROM stdin;
\.


--
-- Data for Name: word2vec_models_data; Type: TABLE DATA; Schema: snap; Owner: mediacloud
--

COPY snap.word2vec_models_data (word2vec_models_data_id, object_id, raw_data) FROM stdin;
\.


--
-- Name: extractor_results_cache_extractor_results_cache_id_seq; Type: SEQUENCE SET; Schema: cache; Owner: mediacloud
--

SELECT pg_catalog.setval('cache.extractor_results_cache_extractor_results_cache_id_seq', 1, false);


--
-- Name: s3_raw_downloads_cache_s3_raw_downloads_cache_id_seq; Type: SEQUENCE SET; Schema: cache; Owner: mediacloud
--

SELECT pg_catalog.setval('cache.s3_raw_downloads_cache_s3_raw_downloads_cache_id_seq', 1, false);


--
-- Name: activities_activities_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.activities_activities_id_seq', 1, false);


--
-- Name: api_links_api_links_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.api_links_api_links_id_seq', 1, false);


--
-- Name: auth_roles_auth_roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.auth_roles_auth_roles_id_seq', 7, true);


--
-- Name: auth_user_api_keys_auth_user_api_keys_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.auth_user_api_keys_auth_user_api_keys_id_seq', 1, false);


--
-- Name: auth_user_limits_auth_user_limits_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.auth_user_limits_auth_user_limits_id_seq', 1, false);


--
-- Name: auth_user_request_daily_count_auth_user_request_daily_count_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.auth_user_request_daily_count_auth_user_request_daily_count_seq', 1, false);


--
-- Name: auth_users_auth_users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.auth_users_auth_users_id_seq', 1, false);


--
-- Name: auth_users_roles_map_auth_users_roles_map_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.auth_users_roles_map_auth_users_roles_map_id_seq', 1, false);


--
-- Name: auth_users_tag_sets_permissio_auth_users_tag_sets_permissio_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.auth_users_tag_sets_permissio_auth_users_tag_sets_permissio_seq', 1, false);


--
-- Name: cliff_annotations_cliff_annotations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.cliff_annotations_cliff_annotations_id_seq', 1, false);


--
-- Name: color_sets_color_sets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.color_sets_color_sets_id_seq', 3, true);


--
-- Name: database_variables_database_variables_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.database_variables_database_variables_id_seq', 1, true);


--
-- Name: download_texts_download_texts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.download_texts_download_texts_id_seq', 1, false);


--
-- Name: downloads_downloads_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.downloads_downloads_id_seq', 1, false);


--
-- Name: feeds_after_rescraping_feeds_after_rescraping_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.feeds_after_rescraping_feeds_after_rescraping_id_seq', 1, false);


--
-- Name: feeds_feeds_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.feeds_feeds_id_seq', 1, false);


--
-- Name: feeds_stories_map_p_feeds_stories_map_p_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.feeds_stories_map_p_feeds_stories_map_p_id_seq', 1, true);


--
-- Name: feeds_tags_map_feeds_tags_map_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.feeds_tags_map_feeds_tags_map_id_seq', 1, false);


--
-- Name: focal_set_definitions_focal_set_definitions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.focal_set_definitions_focal_set_definitions_id_seq', 1, false);


--
-- Name: focal_sets_focal_sets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.focal_sets_focal_sets_id_seq', 1, false);


--
-- Name: foci_foci_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.foci_foci_id_seq', 1, false);


--
-- Name: focus_definitions_focus_definitions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.focus_definitions_focus_definitions_id_seq', 1, false);


--
-- Name: job_states_job_states_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.job_states_job_states_id_seq', 1, false);


--
-- Name: media_health_media_health_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.media_health_media_health_id_seq', 1, false);


--
-- Name: media_media_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.media_media_id_seq', 1, false);


--
-- Name: media_similarweb_domains_map_media_similarweb_domains_map_i_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.media_similarweb_domains_map_media_similarweb_domains_map_i_seq', 1, false);


--
-- Name: media_sitemap_pages_media_sitemap_pages_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.media_sitemap_pages_media_sitemap_pages_id_seq', 1, false);


--
-- Name: media_stats_media_stats_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.media_stats_media_stats_id_seq', 1, false);


--
-- Name: media_suggestions_media_suggestions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.media_suggestions_media_suggestions_id_seq', 1, false);


--
-- Name: media_tags_map_media_tags_map_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.media_tags_map_media_tags_map_id_seq', 1, false);


--
-- Name: mediacloud_stats_mediacloud_stats_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.mediacloud_stats_mediacloud_stats_id_seq', 1, false);


--
-- Name: nytlabels_annotations_nytlabels_annotations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.nytlabels_annotations_nytlabels_annotations_id_seq', 1, false);


--
-- Name: processed_stories_processed_stories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.processed_stories_processed_stories_id_seq', 1, false);


--
-- Name: queued_downloads_queued_downloads_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.queued_downloads_queued_downloads_id_seq', 1, false);


--
-- Name: raw_downloads_raw_downloads_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.raw_downloads_raw_downloads_id_seq', 1, false);


--
-- Name: retweeter_groups_retweeter_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.retweeter_groups_retweeter_groups_id_seq', 1, false);


--
-- Name: retweeter_media_retweeter_media_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.retweeter_media_retweeter_media_id_seq', 1, false);


--
-- Name: retweeter_partition_matrix_retweeter_partition_matrix_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.retweeter_partition_matrix_retweeter_partition_matrix_id_seq', 1, false);


--
-- Name: retweeter_scores_retweeter_scores_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.retweeter_scores_retweeter_scores_id_seq', 1, false);


--
-- Name: retweeter_stories_retweeter_shares_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.retweeter_stories_retweeter_shares_id_seq', 1, false);


--
-- Name: retweeters_retweeters_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.retweeters_retweeters_id_seq', 1, false);


--
-- Name: scraped_feeds_feed_scrapes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.scraped_feeds_feed_scrapes_id_seq', 1, false);


--
-- Name: scraped_stories_scraped_stories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.scraped_stories_scraped_stories_id_seq', 1, false);


--
-- Name: similarweb_domains_similarweb_domains_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.similarweb_domains_similarweb_domains_id_seq', 1, false);


--
-- Name: similarweb_estimated_visits_similarweb_estimated_visits_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.similarweb_estimated_visits_similarweb_estimated_visits_id_seq', 1, false);


--
-- Name: snapshot_files_snapshot_files_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.snapshot_files_snapshot_files_id_seq', 1, false);


--
-- Name: snapshots_snapshots_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.snapshots_snapshots_id_seq', 1, false);


--
-- Name: solr_imports_solr_imports_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.solr_imports_solr_imports_id_seq', 1, false);


--
-- Name: stories_ap_syndicated_stories_ap_syndicated_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.stories_ap_syndicated_stories_ap_syndicated_id_seq', 1, false);


--
-- Name: stories_stories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.stories_stories_id_seq', 1, false);


--
-- Name: stories_tags_map_p_stories_tags_map_p_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.stories_tags_map_p_stories_tags_map_p_id_seq', 1, true);


--
-- Name: story_enclosures_story_enclosures_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.story_enclosures_story_enclosures_id_seq', 1, false);


--
-- Name: story_sentences_p_story_sentences_p_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.story_sentences_p_story_sentences_p_id_seq', 1, true);


--
-- Name: story_statistics_story_statistics_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.story_statistics_story_statistics_id_seq', 1, false);


--
-- Name: story_statistics_twitter_story_statistics_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.story_statistics_twitter_story_statistics_id_seq', 1, false);


--
-- Name: story_urls_story_urls_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.story_urls_story_urls_id_seq', 1, false);


--
-- Name: tag_sets_tag_sets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.tag_sets_tag_sets_id_seq', 1, true);


--
-- Name: tags_tags_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.tags_tags_id_seq', 1, false);


--
-- Name: task_id_sequence; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.task_id_sequence', 1, false);


--
-- Name: timespan_files_timespan_files_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.timespan_files_timespan_files_id_seq', 1, false);


--
-- Name: timespan_maps_timespan_maps_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.timespan_maps_timespan_maps_id_seq', 1, false);


--
-- Name: timespans_timespans_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.timespans_timespans_id_seq', 1, false);


--
-- Name: topic_dates_topic_dates_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_dates_topic_dates_id_seq', 1, false);


--
-- Name: topic_dead_links_topic_dead_links_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_dead_links_topic_dead_links_id_seq', 1, false);


--
-- Name: topic_domains_topic_domains_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_domains_topic_domains_id_seq', 1, false);


--
-- Name: topic_fetch_urls_topic_fetch_urls_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_fetch_urls_topic_fetch_urls_id_seq', 1, false);


--
-- Name: topic_ignore_redirects_topic_ignore_redirects_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_ignore_redirects_topic_ignore_redirects_id_seq', 1, false);


--
-- Name: topic_links_topic_links_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_links_topic_links_id_seq', 1, false);


--
-- Name: topic_modes_topic_modes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_modes_topic_modes_id_seq', 2, true);


--
-- Name: topic_permissions_topic_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_permissions_topic_permissions_id_seq', 1, false);


--
-- Name: topic_platforms_topic_platforms_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_platforms_topic_platforms_id_seq', 4, true);


--
-- Name: topic_post_days_topic_post_days_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_post_days_topic_post_days_id_seq', 1, false);


--
-- Name: topic_post_urls_topic_post_urls_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_post_urls_topic_post_urls_id_seq', 1, false);


--
-- Name: topic_posts_topic_posts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_posts_topic_posts_id_seq', 1, false);


--
-- Name: topic_seed_queries_topic_seed_queries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_seed_queries_topic_seed_queries_id_seq', 1, false);


--
-- Name: topic_seed_urls_topic_seed_urls_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_seed_urls_topic_seed_urls_id_seq', 1, false);


--
-- Name: topic_sources_topic_sources_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_sources_topic_sources_id_seq', 7, true);


--
-- Name: topic_spider_metrics_topic_spider_metrics_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_spider_metrics_topic_spider_metrics_id_seq', 1, false);


--
-- Name: topic_stories_topic_stories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topic_stories_topic_stories_id_seq', 1, false);


--
-- Name: topics_topics_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mediacloud
--

SELECT pg_catalog.setval('public.topics_topics_id_seq', 1, false);


--
-- Name: snapshot_files_snapshot_files_id_seq; Type: SEQUENCE SET; Schema: public_store; Owner: mediacloud
--

SELECT pg_catalog.setval('public_store.snapshot_files_snapshot_files_id_seq', 1, false);


--
-- Name: timespan_files_timespan_files_id_seq; Type: SEQUENCE SET; Schema: public_store; Owner: mediacloud
--

SELECT pg_catalog.setval('public_store.timespan_files_timespan_files_id_seq', 1, false);


--
-- Name: timespan_maps_timespan_maps_id_seq; Type: SEQUENCE SET; Schema: public_store; Owner: mediacloud
--

SELECT pg_catalog.setval('public_store.timespan_maps_timespan_maps_id_seq', 1, false);


--
-- Name: word2vec_models_data_word2vec_models_data_id_seq; Type: SEQUENCE SET; Schema: snap; Owner: mediacloud
--

SELECT pg_catalog.setval('snap.word2vec_models_data_word2vec_models_data_id_seq', 1, false);


--
-- Name: word2vec_models_word2vec_models_id_seq; Type: SEQUENCE SET; Schema: snap; Owner: mediacloud
--

SELECT pg_catalog.setval('snap.word2vec_models_word2vec_models_id_seq', 1, false);


--
-- Name: extractor_results_cache extractor_results_cache_pkey; Type: CONSTRAINT; Schema: cache; Owner: mediacloud
--

ALTER TABLE ONLY cache.extractor_results_cache
    ADD CONSTRAINT extractor_results_cache_pkey PRIMARY KEY (extractor_results_cache_id);


--
-- Name: s3_raw_downloads_cache s3_raw_downloads_cache_pkey; Type: CONSTRAINT; Schema: cache; Owner: mediacloud
--

ALTER TABLE ONLY cache.s3_raw_downloads_cache
    ADD CONSTRAINT s3_raw_downloads_cache_pkey PRIMARY KEY (s3_raw_downloads_cache_id);


--
-- Name: activities activities_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_pkey PRIMARY KEY (activities_id);


--
-- Name: api_links api_links_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.api_links
    ADD CONSTRAINT api_links_pkey PRIMARY KEY (api_links_id);


--
-- Name: auth_roles auth_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_roles
    ADD CONSTRAINT auth_roles_pkey PRIMARY KEY (auth_roles_id);


--
-- Name: auth_roles auth_roles_role_key; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_roles
    ADD CONSTRAINT auth_roles_role_key UNIQUE (role);


--
-- Name: auth_user_api_keys auth_user_api_keys_api_key_key; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_user_api_keys
    ADD CONSTRAINT auth_user_api_keys_api_key_key UNIQUE (api_key);


--
-- Name: auth_user_api_keys auth_user_api_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_user_api_keys
    ADD CONSTRAINT auth_user_api_keys_pkey PRIMARY KEY (auth_user_api_keys_id);


--
-- Name: auth_user_limits auth_user_limits_auth_users_id_key; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_user_limits
    ADD CONSTRAINT auth_user_limits_auth_users_id_key UNIQUE (auth_users_id);


--
-- Name: auth_user_limits auth_user_limits_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_user_limits
    ADD CONSTRAINT auth_user_limits_pkey PRIMARY KEY (auth_user_limits_id);


--
-- Name: auth_user_request_daily_counts auth_user_request_daily_counts_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_user_request_daily_counts
    ADD CONSTRAINT auth_user_request_daily_counts_pkey PRIMARY KEY (auth_user_request_daily_counts_id);


--
-- Name: auth_users auth_users_email_key; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_users
    ADD CONSTRAINT auth_users_email_key UNIQUE (email);


--
-- Name: auth_users auth_users_password_reset_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_users
    ADD CONSTRAINT auth_users_password_reset_token_hash_key UNIQUE (password_reset_token_hash);


--
-- Name: auth_users auth_users_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_users
    ADD CONSTRAINT auth_users_pkey PRIMARY KEY (auth_users_id);


--
-- Name: auth_users_roles_map auth_users_roles_map_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_users_roles_map
    ADD CONSTRAINT auth_users_roles_map_pkey PRIMARY KEY (auth_users_roles_map_id);


--
-- Name: auth_users_tag_sets_permissions auth_users_tag_sets_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_users_tag_sets_permissions
    ADD CONSTRAINT auth_users_tag_sets_permissions_pkey PRIMARY KEY (auth_users_tag_sets_permissions_id);


--
-- Name: celery_groups celery_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.celery_groups
    ADD CONSTRAINT celery_groups_pkey PRIMARY KEY (id);


--
-- Name: celery_groups celery_groups_taskset_id_key; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.celery_groups
    ADD CONSTRAINT celery_groups_taskset_id_key UNIQUE (taskset_id);


--
-- Name: celery_tasks celery_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.celery_tasks
    ADD CONSTRAINT celery_tasks_pkey PRIMARY KEY (id);


--
-- Name: celery_tasks celery_tasks_task_id_key; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.celery_tasks
    ADD CONSTRAINT celery_tasks_task_id_key UNIQUE (task_id);


--
-- Name: cliff_annotations cliff_annotations_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.cliff_annotations
    ADD CONSTRAINT cliff_annotations_pkey PRIMARY KEY (cliff_annotations_id);


--
-- Name: color_sets color_sets_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.color_sets
    ADD CONSTRAINT color_sets_pkey PRIMARY KEY (color_sets_id);


--
-- Name: database_variables database_variables_name_key; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.database_variables
    ADD CONSTRAINT database_variables_name_key UNIQUE (name);


--
-- Name: database_variables database_variables_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.database_variables
    ADD CONSTRAINT database_variables_pkey PRIMARY KEY (database_variables_id);


--
-- Name: download_texts download_texts_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.download_texts
    ADD CONSTRAINT download_texts_pkey PRIMARY KEY (download_texts_id, downloads_id);


--
-- Name: download_texts_00 download_texts_00_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.download_texts_00
    ADD CONSTRAINT download_texts_00_pkey PRIMARY KEY (download_texts_id, downloads_id);


--
-- Name: downloads downloads_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.downloads
    ADD CONSTRAINT downloads_pkey PRIMARY KEY (downloads_id, state, type);


--
-- Name: downloads_error downloads_error_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.downloads_error
    ADD CONSTRAINT downloads_error_pkey PRIMARY KEY (downloads_id, state, type);


--
-- Name: downloads_feed_error downloads_feed_error_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.downloads_feed_error
    ADD CONSTRAINT downloads_feed_error_pkey PRIMARY KEY (downloads_id, state, type);


--
-- Name: downloads_fetching downloads_fetching_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.downloads_fetching
    ADD CONSTRAINT downloads_fetching_pkey PRIMARY KEY (downloads_id, state, type);


--
-- Name: downloads_pending downloads_pending_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.downloads_pending
    ADD CONSTRAINT downloads_pending_pkey PRIMARY KEY (downloads_id, state, type);


--
-- Name: downloads_success downloads_success_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.downloads_success
    ADD CONSTRAINT downloads_success_pkey PRIMARY KEY (downloads_id, state, type);


--
-- Name: downloads_success_content downloads_success_content_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.downloads_success_content
    ADD CONSTRAINT downloads_success_content_pkey PRIMARY KEY (downloads_id, state, type);


--
-- Name: downloads_success_content_00 downloads_success_content_00_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.downloads_success_content_00
    ADD CONSTRAINT downloads_success_content_00_pkey PRIMARY KEY (downloads_id, state, type);


--
-- Name: downloads_success_feed downloads_success_feed_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.downloads_success_feed
    ADD CONSTRAINT downloads_success_feed_pkey PRIMARY KEY (downloads_id, state, type);


--
-- Name: downloads_success_feed_00 downloads_success_feed_00_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.downloads_success_feed_00
    ADD CONSTRAINT downloads_success_feed_00_pkey PRIMARY KEY (downloads_id, state, type);


--
-- Name: feeds_after_rescraping feeds_after_rescraping_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_after_rescraping
    ADD CONSTRAINT feeds_after_rescraping_pkey PRIMARY KEY (feeds_after_rescraping_id);


--
-- Name: feeds feeds_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds
    ADD CONSTRAINT feeds_pkey PRIMARY KEY (feeds_id);


--
-- Name: feeds_stories_map_p_00 feeds_stories_map_p_00_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_stories_map_p_00
    ADD CONSTRAINT feeds_stories_map_p_00_pkey PRIMARY KEY (feeds_stories_map_p_id);


--
-- Name: feeds_stories_map_p feeds_stories_map_p_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_stories_map_p
    ADD CONSTRAINT feeds_stories_map_p_pkey PRIMARY KEY (feeds_stories_map_p_id);


--
-- Name: feeds_tags_map feeds_tags_map_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_tags_map
    ADD CONSTRAINT feeds_tags_map_pkey PRIMARY KEY (feeds_tags_map_id);


--
-- Name: focal_set_definitions focal_set_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.focal_set_definitions
    ADD CONSTRAINT focal_set_definitions_pkey PRIMARY KEY (focal_set_definitions_id);


--
-- Name: focal_sets focal_sets_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.focal_sets
    ADD CONSTRAINT focal_sets_pkey PRIMARY KEY (focal_sets_id);


--
-- Name: foci foci_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.foci
    ADD CONSTRAINT foci_pkey PRIMARY KEY (foci_id);


--
-- Name: focus_definitions focus_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.focus_definitions
    ADD CONSTRAINT focus_definitions_pkey PRIMARY KEY (focus_definitions_id);


--
-- Name: job_states job_states_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.job_states
    ADD CONSTRAINT job_states_pkey PRIMARY KEY (job_states_id);


--
-- Name: media_health media_health_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_health
    ADD CONSTRAINT media_health_pkey PRIMARY KEY (media_health_id);


--
-- Name: media media_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media
    ADD CONSTRAINT media_pkey PRIMARY KEY (media_id);


--
-- Name: media_rescraping media_rescraping_media_id_key; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_rescraping
    ADD CONSTRAINT media_rescraping_media_id_key UNIQUE (media_id);


--
-- Name: media_similarweb_domains_map media_similarweb_domains_map_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_similarweb_domains_map
    ADD CONSTRAINT media_similarweb_domains_map_pkey PRIMARY KEY (media_similarweb_domains_map_id);


--
-- Name: media_sitemap_pages media_sitemap_pages_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_sitemap_pages
    ADD CONSTRAINT media_sitemap_pages_pkey PRIMARY KEY (media_sitemap_pages_id);


--
-- Name: media_stats media_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_stats
    ADD CONSTRAINT media_stats_pkey PRIMARY KEY (media_stats_id);


--
-- Name: media_suggestions media_suggestions_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_suggestions
    ADD CONSTRAINT media_suggestions_pkey PRIMARY KEY (media_suggestions_id);


--
-- Name: media_tags_map media_tags_map_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_tags_map
    ADD CONSTRAINT media_tags_map_pkey PRIMARY KEY (media_tags_map_id);


--
-- Name: mediacloud_stats mediacloud_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.mediacloud_stats
    ADD CONSTRAINT mediacloud_stats_pkey PRIMARY KEY (mediacloud_stats_id);


--
-- Name: auth_users_roles_map no_duplicate_entries; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_users_roles_map
    ADD CONSTRAINT no_duplicate_entries UNIQUE (auth_users_id, auth_roles_id);


--
-- Name: nytlabels_annotations nytlabels_annotations_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.nytlabels_annotations
    ADD CONSTRAINT nytlabels_annotations_pkey PRIMARY KEY (nytlabels_annotations_id);


--
-- Name: processed_stories processed_stories_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.processed_stories
    ADD CONSTRAINT processed_stories_pkey PRIMARY KEY (processed_stories_id);


--
-- Name: queued_downloads queued_downloads_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.queued_downloads
    ADD CONSTRAINT queued_downloads_pkey PRIMARY KEY (queued_downloads_id);


--
-- Name: raw_downloads raw_downloads_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.raw_downloads
    ADD CONSTRAINT raw_downloads_pkey PRIMARY KEY (raw_downloads_id);


--
-- Name: retweeter_groups retweeter_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_groups
    ADD CONSTRAINT retweeter_groups_pkey PRIMARY KEY (retweeter_groups_id);


--
-- Name: retweeter_media retweeter_media_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_media
    ADD CONSTRAINT retweeter_media_pkey PRIMARY KEY (retweeter_media_id);


--
-- Name: retweeter_partition_matrix retweeter_partition_matrix_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_partition_matrix
    ADD CONSTRAINT retweeter_partition_matrix_pkey PRIMARY KEY (retweeter_partition_matrix_id);


--
-- Name: retweeter_scores retweeter_scores_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_scores
    ADD CONSTRAINT retweeter_scores_pkey PRIMARY KEY (retweeter_scores_id);


--
-- Name: retweeter_stories retweeter_stories_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_stories
    ADD CONSTRAINT retweeter_stories_pkey PRIMARY KEY (retweeter_shares_id);


--
-- Name: retweeters retweeters_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeters
    ADD CONSTRAINT retweeters_pkey PRIMARY KEY (retweeters_id);


--
-- Name: schema_version schema_version_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.schema_version
    ADD CONSTRAINT schema_version_pkey PRIMARY KEY (version);


--
-- Name: scraped_feeds scraped_feeds_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.scraped_feeds
    ADD CONSTRAINT scraped_feeds_pkey PRIMARY KEY (feed_scrapes_id);


--
-- Name: scraped_stories scraped_stories_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.scraped_stories
    ADD CONSTRAINT scraped_stories_pkey PRIMARY KEY (scraped_stories_id);


--
-- Name: similarweb_domains similarweb_domains_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.similarweb_domains
    ADD CONSTRAINT similarweb_domains_pkey PRIMARY KEY (similarweb_domains_id);


--
-- Name: similarweb_estimated_visits similarweb_estimated_visits_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.similarweb_estimated_visits
    ADD CONSTRAINT similarweb_estimated_visits_pkey PRIMARY KEY (similarweb_estimated_visits_id);


--
-- Name: snapshot_files snapshot_files_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.snapshot_files
    ADD CONSTRAINT snapshot_files_pkey PRIMARY KEY (snapshot_files_id);


--
-- Name: snapshots snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.snapshots
    ADD CONSTRAINT snapshots_pkey PRIMARY KEY (snapshots_id);


--
-- Name: solr_imports solr_imports_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.solr_imports
    ADD CONSTRAINT solr_imports_pkey PRIMARY KEY (solr_imports_id);


--
-- Name: stories_ap_syndicated stories_ap_syndicated_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories_ap_syndicated
    ADD CONSTRAINT stories_ap_syndicated_pkey PRIMARY KEY (stories_ap_syndicated_id);


--
-- Name: stories stories_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories
    ADD CONSTRAINT stories_pkey PRIMARY KEY (stories_id);


--
-- Name: stories_tags_map_p_00 stories_tags_map_p_00_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories_tags_map_p_00
    ADD CONSTRAINT stories_tags_map_p_00_pkey PRIMARY KEY (stories_tags_map_p_id);


--
-- Name: stories_tags_map_p_00 stories_tags_map_p_00_stories_id_tags_id_unique; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories_tags_map_p_00
    ADD CONSTRAINT stories_tags_map_p_00_stories_id_tags_id_unique UNIQUE (stories_id, tags_id);


--
-- Name: stories_tags_map_p stories_tags_map_p_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories_tags_map_p
    ADD CONSTRAINT stories_tags_map_p_pkey PRIMARY KEY (stories_tags_map_p_id);


--
-- Name: story_enclosures story_enclosures_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_enclosures
    ADD CONSTRAINT story_enclosures_pkey PRIMARY KEY (story_enclosures_id);


--
-- Name: story_sentences_p_00 story_sentences_p_00_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_sentences_p_00
    ADD CONSTRAINT story_sentences_p_00_pkey PRIMARY KEY (story_sentences_p_id);


--
-- Name: story_sentences_p story_sentences_p_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_sentences_p
    ADD CONSTRAINT story_sentences_p_pkey PRIMARY KEY (story_sentences_p_id);


--
-- Name: story_statistics story_statistics_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_statistics
    ADD CONSTRAINT story_statistics_pkey PRIMARY KEY (story_statistics_id);


--
-- Name: story_statistics_twitter story_statistics_twitter_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_statistics_twitter
    ADD CONSTRAINT story_statistics_twitter_pkey PRIMARY KEY (story_statistics_id);


--
-- Name: story_urls story_urls_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_urls
    ADD CONSTRAINT story_urls_pkey PRIMARY KEY (story_urls_id);


--
-- Name: tag_sets tag_sets_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.tag_sets
    ADD CONSTRAINT tag_sets_pkey PRIMARY KEY (tag_sets_id);


--
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (tags_id);


--
-- Name: timespan_files timespan_files_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.timespan_files
    ADD CONSTRAINT timespan_files_pkey PRIMARY KEY (timespan_files_id);


--
-- Name: timespan_maps timespan_maps_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.timespan_maps
    ADD CONSTRAINT timespan_maps_pkey PRIMARY KEY (timespan_maps_id);


--
-- Name: timespans timespans_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.timespans
    ADD CONSTRAINT timespans_pkey PRIMARY KEY (timespans_id);


--
-- Name: topic_dates topic_dates_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_dates
    ADD CONSTRAINT topic_dates_pkey PRIMARY KEY (topic_dates_id);


--
-- Name: topic_dead_links topic_dead_links_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_dead_links
    ADD CONSTRAINT topic_dead_links_pkey PRIMARY KEY (topic_dead_links_id);


--
-- Name: topic_domains topic_domains_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_domains
    ADD CONSTRAINT topic_domains_pkey PRIMARY KEY (topic_domains_id);


--
-- Name: topic_fetch_urls topic_fetch_urls_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_fetch_urls
    ADD CONSTRAINT topic_fetch_urls_pkey PRIMARY KEY (topic_fetch_urls_id);


--
-- Name: topic_ignore_redirects topic_ignore_redirects_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_ignore_redirects
    ADD CONSTRAINT topic_ignore_redirects_pkey PRIMARY KEY (topic_ignore_redirects_id);


--
-- Name: topic_links topic_links_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_links
    ADD CONSTRAINT topic_links_pkey PRIMARY KEY (topic_links_id);


--
-- Name: topic_modes topic_modes_name_key; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_modes
    ADD CONSTRAINT topic_modes_name_key UNIQUE (name);


--
-- Name: topic_modes topic_modes_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_modes
    ADD CONSTRAINT topic_modes_pkey PRIMARY KEY (topic_modes_id);


--
-- Name: topic_permissions topic_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_permissions
    ADD CONSTRAINT topic_permissions_pkey PRIMARY KEY (topic_permissions_id);


--
-- Name: topic_platforms topic_platforms_name_key; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_platforms
    ADD CONSTRAINT topic_platforms_name_key UNIQUE (name);


--
-- Name: topic_platforms topic_platforms_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_platforms
    ADD CONSTRAINT topic_platforms_pkey PRIMARY KEY (topic_platforms_id);


--
-- Name: topic_post_days topic_post_days_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_post_days
    ADD CONSTRAINT topic_post_days_pkey PRIMARY KEY (topic_post_days_id);


--
-- Name: topic_post_urls topic_post_urls_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_post_urls
    ADD CONSTRAINT topic_post_urls_pkey PRIMARY KEY (topic_post_urls_id);


--
-- Name: topic_posts topic_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_posts
    ADD CONSTRAINT topic_posts_pkey PRIMARY KEY (topic_posts_id);


--
-- Name: topic_seed_queries topic_seed_queries_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_seed_queries
    ADD CONSTRAINT topic_seed_queries_pkey PRIMARY KEY (topic_seed_queries_id);


--
-- Name: topic_seed_urls topic_seed_urls_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_seed_urls
    ADD CONSTRAINT topic_seed_urls_pkey PRIMARY KEY (topic_seed_urls_id);


--
-- Name: topic_sources topic_sources_name_key; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_sources
    ADD CONSTRAINT topic_sources_name_key UNIQUE (name);


--
-- Name: topic_sources topic_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_sources
    ADD CONSTRAINT topic_sources_pkey PRIMARY KEY (topic_sources_id);


--
-- Name: topic_spider_metrics topic_spider_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_spider_metrics
    ADD CONSTRAINT topic_spider_metrics_pkey PRIMARY KEY (topic_spider_metrics_id);


--
-- Name: topic_stories topic_stories_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_stories
    ADD CONSTRAINT topic_stories_pkey PRIMARY KEY (topic_stories_id);


--
-- Name: topics topics_pkey; Type: CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topics
    ADD CONSTRAINT topics_pkey PRIMARY KEY (topics_id);


--
-- Name: snapshot_files snapshot_files_pkey; Type: CONSTRAINT; Schema: public_store; Owner: mediacloud
--

ALTER TABLE ONLY public_store.snapshot_files
    ADD CONSTRAINT snapshot_files_pkey PRIMARY KEY (snapshot_files_id);


--
-- Name: timespan_files timespan_files_pkey; Type: CONSTRAINT; Schema: public_store; Owner: mediacloud
--

ALTER TABLE ONLY public_store.timespan_files
    ADD CONSTRAINT timespan_files_pkey PRIMARY KEY (timespan_files_id);


--
-- Name: timespan_maps timespan_maps_pkey; Type: CONSTRAINT; Schema: public_store; Owner: mediacloud
--

ALTER TABLE ONLY public_store.timespan_maps
    ADD CONSTRAINT timespan_maps_pkey PRIMARY KEY (timespan_maps_id);


--
-- Name: word2vec_models_data word2vec_models_data_pkey; Type: CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.word2vec_models_data
    ADD CONSTRAINT word2vec_models_data_pkey PRIMARY KEY (word2vec_models_data_id);


--
-- Name: word2vec_models word2vec_models_pkey; Type: CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.word2vec_models
    ADD CONSTRAINT word2vec_models_pkey PRIMARY KEY (word2vec_models_id);


--
-- Name: extractor_results_cache_db_row_last_updated; Type: INDEX; Schema: cache; Owner: mediacloud
--

CREATE INDEX extractor_results_cache_db_row_last_updated ON cache.extractor_results_cache USING btree (db_row_last_updated);


--
-- Name: extractor_results_cache_downloads_id; Type: INDEX; Schema: cache; Owner: mediacloud
--

CREATE UNIQUE INDEX extractor_results_cache_downloads_id ON cache.extractor_results_cache USING btree (downloads_id);


--
-- Name: s3_raw_downloads_cache_db_row_last_updated; Type: INDEX; Schema: cache; Owner: mediacloud
--

CREATE INDEX s3_raw_downloads_cache_db_row_last_updated ON cache.s3_raw_downloads_cache USING btree (db_row_last_updated);


--
-- Name: s3_raw_downloads_cache_object_id; Type: INDEX; Schema: cache; Owner: mediacloud
--

CREATE UNIQUE INDEX s3_raw_downloads_cache_object_id ON cache.s3_raw_downloads_cache USING btree (object_id);


--
-- Name: activities_creation_date; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX activities_creation_date ON public.activities USING btree (creation_date);


--
-- Name: activities_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX activities_name ON public.activities USING btree (name);


--
-- Name: activities_object_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX activities_object_id ON public.activities USING btree (object_id);


--
-- Name: activities_user_identifier; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX activities_user_identifier ON public.activities USING btree (user_identifier);


--
-- Name: api_links_params; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX api_links_params ON public.api_links USING btree (path, md5(params_json));


--
-- Name: auth_user_api_keys_api_key_ip_address; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX auth_user_api_keys_api_key_ip_address ON public.auth_user_api_keys USING btree (api_key, ip_address);


--
-- Name: auth_user_limits_auth_users_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX auth_user_limits_auth_users_id ON public.auth_user_limits USING btree (auth_users_id);


--
-- Name: auth_user_request_daily_counts_email_day; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX auth_user_request_daily_counts_email_day ON public.auth_user_request_daily_counts USING btree (email, day);


--
-- Name: INDEX auth_user_request_daily_counts_email_day; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON INDEX public.auth_user_request_daily_counts_email_day IS 'Single index to enforce upsert uniqueness';


--
-- Name: auth_users_created_day; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX auth_users_created_day ON public.auth_users USING btree (date_trunc('day'::text, created_date));


--
-- Name: INDEX auth_users_created_day; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON INDEX public.auth_users_created_day IS 'used by daily stats script';


--
-- Name: auth_users_roles_map_auth_users_id_auth_roles_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX auth_users_roles_map_auth_users_id_auth_roles_id ON public.auth_users_roles_map USING btree (auth_users_id, auth_roles_id);


--
-- Name: auth_users_tag_sets_permissions_auth_user; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX auth_users_tag_sets_permissions_auth_user ON public.auth_users_tag_sets_permissions USING btree (auth_users_id);


--
-- Name: auth_users_tag_sets_permissions_auth_user_tag_set; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX auth_users_tag_sets_permissions_auth_user_tag_set ON public.auth_users_tag_sets_permissions USING btree (auth_users_id, tag_sets_id);


--
-- Name: auth_users_tag_sets_permissions_tag_sets; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX auth_users_tag_sets_permissions_tag_sets ON public.auth_users_tag_sets_permissions USING btree (tag_sets_id);


--
-- Name: cliff_annotations_object_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX cliff_annotations_object_id ON public.cliff_annotations USING btree (object_id);


--
-- Name: color_sets_set_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX color_sets_set_id ON public.color_sets USING btree (color_set, id);


--
-- Name: cqssism_c; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX cqssism_c ON public.topic_query_story_searches_imported_stories_map USING btree (topics_id);


--
-- Name: cqssism_s; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX cqssism_s ON public.topic_query_story_searches_imported_stories_map USING btree (stories_id);


--
-- Name: database_variables_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX database_variables_name ON public.database_variables USING btree (name);


--
-- Name: domain_web_requests_domain; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX domain_web_requests_domain ON public.domain_web_requests USING btree (domain);


--
-- Name: download_texts_downloads_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX download_texts_downloads_id ON ONLY public.download_texts USING btree (downloads_id);


--
-- Name: download_texts_00_downloads_id_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX download_texts_00_downloads_id_idx ON public.download_texts_00 USING btree (downloads_id);


--
-- Name: downloads_time; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_time ON ONLY public.downloads USING btree (download_time);


--
-- Name: downloads_error_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_error_download_time_idx ON public.downloads_error USING btree (download_time);


--
-- Name: downloads_feed_download_time; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_feed_download_time ON ONLY public.downloads USING btree (feeds_id, download_time);


--
-- Name: downloads_error_feeds_id_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_error_feeds_id_download_time_idx ON public.downloads_error USING btree (feeds_id, download_time);


--
-- Name: downloads_parent; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_parent ON ONLY public.downloads USING btree (parent);


--
-- Name: downloads_error_parent_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_error_parent_idx ON public.downloads_error USING btree (parent);


--
-- Name: downloads_story; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_story ON ONLY public.downloads USING btree (stories_id);


--
-- Name: downloads_error_stories_id_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_error_stories_id_idx ON public.downloads_error USING btree (stories_id);


--
-- Name: downloads_feed_error_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_feed_error_download_time_idx ON public.downloads_feed_error USING btree (download_time);


--
-- Name: downloads_feed_error_feeds_id_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_feed_error_feeds_id_download_time_idx ON public.downloads_feed_error USING btree (feeds_id, download_time);


--
-- Name: downloads_feed_error_parent_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_feed_error_parent_idx ON public.downloads_feed_error USING btree (parent);


--
-- Name: downloads_feed_error_stories_id_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_feed_error_stories_id_idx ON public.downloads_feed_error USING btree (stories_id);


--
-- Name: downloads_fetching_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_fetching_download_time_idx ON public.downloads_fetching USING btree (download_time);


--
-- Name: downloads_fetching_feeds_id_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_fetching_feeds_id_download_time_idx ON public.downloads_fetching USING btree (feeds_id, download_time);


--
-- Name: downloads_fetching_parent_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_fetching_parent_idx ON public.downloads_fetching USING btree (parent);


--
-- Name: downloads_fetching_stories_id_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_fetching_stories_id_idx ON public.downloads_fetching USING btree (stories_id);


--
-- Name: downloads_pending_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_pending_download_time_idx ON public.downloads_pending USING btree (download_time);


--
-- Name: downloads_pending_feeds_id_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_pending_feeds_id_download_time_idx ON public.downloads_pending USING btree (feeds_id, download_time);


--
-- Name: downloads_pending_parent_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_pending_parent_idx ON public.downloads_pending USING btree (parent);


--
-- Name: downloads_pending_stories_id_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_pending_stories_id_idx ON public.downloads_pending USING btree (stories_id);


--
-- Name: downloads_success_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_download_time_idx ON ONLY public.downloads_success USING btree (download_time);


--
-- Name: downloads_success_content_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_content_download_time_idx ON ONLY public.downloads_success_content USING btree (download_time);


--
-- Name: downloads_success_content_00_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_content_00_download_time_idx ON public.downloads_success_content_00 USING btree (download_time);


--
-- Name: downloads_success_content_downloads_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX downloads_success_content_downloads_id ON ONLY public.downloads_success_content USING btree (downloads_id);


--
-- Name: INDEX downloads_success_content_downloads_id; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON INDEX public.downloads_success_content_downloads_id IS 'We need a separate unique index for the 
"download_texts" foreign key to be able to point to "downloads_success_content" partitions';


--
-- Name: downloads_success_content_00_downloads_id_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX downloads_success_content_00_downloads_id_idx ON public.downloads_success_content_00 USING btree (downloads_id);


--
-- Name: downloads_success_content_extracted; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_content_extracted ON ONLY public.downloads_success_content USING btree (extracted);


--
-- Name: downloads_success_content_00_extracted_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_content_00_extracted_idx ON public.downloads_success_content_00 USING btree (extracted);


--
-- Name: downloads_success_feeds_id_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_feeds_id_download_time_idx ON ONLY public.downloads_success USING btree (feeds_id, download_time);


--
-- Name: downloads_success_content_feeds_id_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_content_feeds_id_download_time_idx ON ONLY public.downloads_success_content USING btree (feeds_id, download_time);


--
-- Name: downloads_success_content_00_feeds_id_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_content_00_feeds_id_download_time_idx ON public.downloads_success_content_00 USING btree (feeds_id, download_time);


--
-- Name: downloads_success_parent_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_parent_idx ON ONLY public.downloads_success USING btree (parent);


--
-- Name: downloads_success_content_parent_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_content_parent_idx ON ONLY public.downloads_success_content USING btree (parent);


--
-- Name: downloads_success_content_00_parent_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_content_00_parent_idx ON public.downloads_success_content_00 USING btree (parent);


--
-- Name: downloads_success_stories_id_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_stories_id_idx ON ONLY public.downloads_success USING btree (stories_id);


--
-- Name: downloads_success_content_stories_id_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_content_stories_id_idx ON ONLY public.downloads_success_content USING btree (stories_id);


--
-- Name: downloads_success_content_00_stories_id_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_content_00_stories_id_idx ON public.downloads_success_content_00 USING btree (stories_id);


--
-- Name: downloads_success_feed_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_feed_download_time_idx ON ONLY public.downloads_success_feed USING btree (download_time);


--
-- Name: downloads_success_feed_00_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_feed_00_download_time_idx ON public.downloads_success_feed_00 USING btree (download_time);


--
-- Name: downloads_success_feed_feeds_id_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_feed_feeds_id_download_time_idx ON ONLY public.downloads_success_feed USING btree (feeds_id, download_time);


--
-- Name: downloads_success_feed_00_feeds_id_download_time_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_feed_00_feeds_id_download_time_idx ON public.downloads_success_feed_00 USING btree (feeds_id, download_time);


--
-- Name: downloads_success_feed_parent_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_feed_parent_idx ON ONLY public.downloads_success_feed USING btree (parent);


--
-- Name: downloads_success_feed_00_parent_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_feed_00_parent_idx ON public.downloads_success_feed_00 USING btree (parent);


--
-- Name: downloads_success_feed_stories_id_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_feed_stories_id_idx ON ONLY public.downloads_success_feed USING btree (stories_id);


--
-- Name: downloads_success_feed_00_stories_id_idx; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX downloads_success_feed_00_stories_id_idx ON public.downloads_success_feed_00 USING btree (stories_id);


--
-- Name: feeds_after_rescraping_media_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX feeds_after_rescraping_media_id ON public.feeds_after_rescraping USING btree (media_id);


--
-- Name: feeds_after_rescraping_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX feeds_after_rescraping_name ON public.feeds_after_rescraping USING btree (name);


--
-- Name: feeds_after_rescraping_url; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX feeds_after_rescraping_url ON public.feeds_after_rescraping USING btree (url, media_id);


--
-- Name: feeds_from_yesterday_feeds_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX feeds_from_yesterday_feeds_id ON public.feeds_from_yesterday USING btree (feeds_id);


--
-- Name: feeds_from_yesterday_media_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX feeds_from_yesterday_media_id ON public.feeds_from_yesterday USING btree (media_id);


--
-- Name: feeds_from_yesterday_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX feeds_from_yesterday_name ON public.feeds_from_yesterday USING btree (name);


--
-- Name: feeds_from_yesterday_url; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX feeds_from_yesterday_url ON public.feeds_from_yesterday USING btree (url, media_id);


--
-- Name: feeds_last_attempted_download_time; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX feeds_last_attempted_download_time ON public.feeds USING btree (last_attempted_download_time);


--
-- Name: feeds_last_successful_download_time; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX feeds_last_successful_download_time ON public.feeds USING btree (last_successful_download_time);


--
-- Name: feeds_media; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX feeds_media ON public.feeds USING btree (media_id);


--
-- Name: feeds_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX feeds_name ON public.feeds USING btree (name);


--
-- Name: feeds_stories_map_p_00_feeds_id_stories_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX feeds_stories_map_p_00_feeds_id_stories_id ON public.feeds_stories_map_p_00 USING btree (feeds_id, stories_id);


--
-- Name: feeds_stories_map_p_00_stories_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX feeds_stories_map_p_00_stories_id ON public.feeds_stories_map_p_00 USING btree (stories_id);


--
-- Name: feeds_tags_map_feed; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX feeds_tags_map_feed ON public.feeds_tags_map USING btree (feeds_id, tags_id);


--
-- Name: feeds_tags_map_tag; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX feeds_tags_map_tag ON public.feeds_tags_map USING btree (tags_id);


--
-- Name: feeds_url; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX feeds_url ON public.feeds USING btree (url, media_id);


--
-- Name: focal_set_definitions_topic_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX focal_set_definitions_topic_name ON public.focal_set_definitions USING btree (topics_id, name);


--
-- Name: focal_set_snapshot; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX focal_set_snapshot ON public.focal_sets USING btree (snapshots_id, name);


--
-- Name: foci_set_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX foci_set_name ON public.foci USING btree (focal_sets_id, name);


--
-- Name: focus_definition_set_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX focus_definition_set_name ON public.focus_definitions USING btree (focal_set_definitions_id, name);


--
-- Name: job_states_class_date; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX job_states_class_date ON public.job_states USING btree (class, last_updated);


--
-- Name: media_coverage_gaps_medium; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX media_coverage_gaps_medium ON public.media_coverage_gaps USING btree (media_id);


--
-- Name: media_expected_volume_medium; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX media_expected_volume_medium ON public.media_expected_volume USING btree (media_id);


--
-- Name: media_health_medium; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX media_health_medium ON public.media_health USING btree (media_id);


--
-- Name: media_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX media_name ON public.media USING btree (name);


--
-- Name: media_name_fts; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX media_name_fts ON public.media USING gin (to_tsvector('english'::regconfig, (name)::text));


--
-- Name: media_normalized_url; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX media_normalized_url ON public.media USING btree (normalized_url);


--
-- Name: media_rescraping_last_rescrape_time; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX media_rescraping_last_rescrape_time ON public.media_rescraping USING btree (last_rescrape_time);


--
-- Name: media_rescraping_media_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX media_rescraping_media_id ON public.media_rescraping USING btree (media_id);


--
-- Name: media_similarweb_domains_map_media_id_sdi; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX media_similarweb_domains_map_media_id_sdi ON public.media_similarweb_domains_map USING btree (media_id, similarweb_domains_id);


--
-- Name: INDEX media_similarweb_domains_map_media_id_sdi; Type: COMMENT; Schema: public; Owner: mediacloud
--

COMMENT ON INDEX public.media_similarweb_domains_map_media_id_sdi IS 'Different media sources can point 
to the same domain';


--
-- Name: media_sitemap_pages_media_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX media_sitemap_pages_media_id ON public.media_sitemap_pages USING btree (media_id);


--
-- Name: media_sitemap_pages_url; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX media_sitemap_pages_url ON public.media_sitemap_pages USING btree (url);


--
-- Name: media_stats_medium_date; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX media_stats_medium_date ON public.media_stats USING btree (media_id, stat_date);


--
-- Name: media_stats_weekly_medium; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX media_stats_weekly_medium ON public.media_stats_weekly USING btree (media_id);


--
-- Name: media_suggestions_date; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX media_suggestions_date ON public.media_suggestions USING btree (date_submitted);


--
-- Name: media_suggestions_tags_map_ms; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX media_suggestions_tags_map_ms ON public.media_suggestions_tags_map USING btree (media_suggestions_id);


--
-- Name: media_suggestions_tags_map_tag; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX media_suggestions_tags_map_tag ON public.media_suggestions_tags_map USING btree (tags_id);


--
-- Name: media_tags_map_media; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX media_tags_map_media ON public.media_tags_map USING btree (media_id, tags_id);


--
-- Name: media_tags_map_tag; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX media_tags_map_tag ON public.media_tags_map USING btree (tags_id);


--
-- Name: media_url; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX media_url ON public.media USING btree (url);


--
-- Name: nytlabels_annotations_object_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX nytlabels_annotations_object_id ON public.nytlabels_annotations USING btree (object_id);


--
-- Name: processed_stories_story; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX processed_stories_story ON public.processed_stories USING btree (stories_id);


--
-- Name: queued_downloads_download; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX queued_downloads_download ON public.queued_downloads USING btree (downloads_id);


--
-- Name: raw_downloads_object_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX raw_downloads_object_id ON public.raw_downloads USING btree (object_id);


--
-- Name: retweeter_media_score; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX retweeter_media_score ON public.retweeter_media USING btree (retweeter_scores_id, media_id);


--
-- Name: retweeter_partition_matrix_score; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX retweeter_partition_matrix_score ON public.retweeter_partition_matrix USING btree (retweeter_scores_id);


--
-- Name: retweeter_stories_psu; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX retweeter_stories_psu ON public.retweeter_stories USING btree (retweeter_scores_id, stories_id, retweeted_user);


--
-- Name: retweeters_user; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX retweeters_user ON public.retweeters USING btree (retweeter_scores_id, twitter_user, retweeted_user);


--
-- Name: scraped_feeds_feed; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX scraped_feeds_feed ON public.scraped_feeds USING btree (feeds_id);


--
-- Name: scraped_stories_story; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX scraped_stories_story ON public.scraped_stories USING btree (stories_id);


--
-- Name: similarweb_domains_domain; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX similarweb_domains_domain ON public.similarweb_domains USING btree (domain);


--
-- Name: similarweb_estimated_visits_domain_month_mdo; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX similarweb_estimated_visits_domain_month_mdo ON public.similarweb_estimated_visits USING btree (similarweb_domains_id, month, main_domain_only);


--
-- Name: snapshot_files_snapshot_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX snapshot_files_snapshot_name ON public.snapshot_files USING btree (snapshots_id, name);


--
-- Name: snapshots_topic; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX snapshots_topic ON public.snapshots USING btree (topics_id);


--
-- Name: solr_import_stories_story; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX solr_import_stories_story ON public.solr_import_stories USING btree (stories_id);


--
-- Name: solr_imported_stories_day; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX solr_imported_stories_day ON public.solr_imported_stories USING btree (date_trunc('day'::text, import_date));


--
-- Name: solr_imported_stories_story; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX solr_imported_stories_story ON public.solr_imported_stories USING btree (stories_id);


--
-- Name: solr_imports_date; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX solr_imports_date ON public.solr_imports USING btree (import_date);


--
-- Name: stories_ap_syndicated_story; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX stories_ap_syndicated_story ON public.stories_ap_syndicated USING btree (stories_id);


--
-- Name: stories_collect_date; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX stories_collect_date ON public.stories USING btree (collect_date);


--
-- Name: stories_guid; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX stories_guid ON public.stories USING btree (guid, media_id);


--
-- Name: stories_language; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX stories_language ON public.stories USING btree (language);


--
-- Name: stories_md; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX stories_md ON public.stories USING btree (media_id, date_trunc('day'::text, publish_date));


--
-- Name: stories_media_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX stories_media_id ON public.stories USING btree (media_id);


--
-- Name: stories_normalized_title_hash; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX stories_normalized_title_hash ON public.stories USING btree (media_id, normalized_title_hash);


--
-- Name: stories_publish_date; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX stories_publish_date ON public.stories USING btree (publish_date);


--
-- Name: stories_publish_day; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX stories_publish_day ON public.stories USING btree (date_trunc('day'::text, publish_date));


--
-- Name: stories_story; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX stories_story ON public.story_urls USING btree (stories_id);


--
-- Name: stories_title_hash; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX stories_title_hash ON public.stories USING btree (md5(title));


--
-- Name: stories_url; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX stories_url ON public.stories USING btree (url);


--
-- Name: story_enclosures_stories_id_url; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX story_enclosures_stories_id_url ON public.story_enclosures USING btree (stories_id, url);


--
-- Name: story_sentences_p_00_sentence_media_week; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX story_sentences_p_00_sentence_media_week ON public.story_sentences_p_00 USING btree (public.half_md5(sentence), media_id, public.week_start_date((publish_date)::date));


--
-- Name: story_sentences_p_00_stories_id_sentence_number; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX story_sentences_p_00_stories_id_sentence_number ON public.story_sentences_p_00 USING btree (stories_id, sentence_number);


--
-- Name: story_statistics_story; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX story_statistics_story ON public.story_statistics USING btree (stories_id);


--
-- Name: story_statistics_twitter_story; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX story_statistics_twitter_story ON public.story_statistics_twitter USING btree (stories_id);


--
-- Name: story_urls_url; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX story_urls_url ON public.story_urls USING btree (url, stories_id);


--
-- Name: tag_sets_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX tag_sets_name ON public.tag_sets USING btree (name);


--
-- Name: tags_fts; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX tags_fts ON public.tags USING gin (to_tsvector('english'::regconfig, (((tag)::text || ' '::text) || (label)::text)));


--
-- Name: tags_label; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX tags_label ON public.tags USING btree (label);


--
-- Name: tags_show_on_media; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX tags_show_on_media ON public.tags USING btree (show_on_media);


--
-- Name: tags_show_on_stories; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX tags_show_on_stories ON public.tags USING btree (show_on_stories);


--
-- Name: tags_tag; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX tags_tag ON public.tags USING btree (tag, tag_sets_id);


--
-- Name: tags_tag_sets_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX tags_tag_sets_id ON public.tags USING btree (tag_sets_id);


--
-- Name: timespan_files_timespan_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX timespan_files_timespan_name ON public.timespan_files USING btree (timespans_id, name);


--
-- Name: timespans_snapshot; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX timespans_snapshot ON public.timespans USING btree (snapshots_id);


--
-- Name: timespans_unique; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX timespans_unique ON public.timespans USING btree (snapshots_id, foci_id, start_date, end_date, period);


--
-- Name: topic_domains_domain; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX topic_domains_domain ON public.topic_domains USING btree (topics_id, md5(domain));


--
-- Name: topic_fetch_urls_link; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_fetch_urls_link ON public.topic_fetch_urls USING btree (topic_links_id);


--
-- Name: topic_fetch_urls_pending; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_fetch_urls_pending ON public.topic_fetch_urls USING btree (topics_id) WHERE (state = 'pending'::text);


--
-- Name: topic_fetch_urls_url; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_fetch_urls_url ON public.topic_fetch_urls USING btree (md5(url));


--
-- Name: topic_ignore_redirects_url; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_ignore_redirects_url ON public.topic_ignore_redirects USING btree (url);


--
-- Name: topic_links_ref_story; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_links_ref_story ON public.topic_links USING btree (ref_stories_id);


--
-- Name: topic_links_scr; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX topic_links_scr ON public.topic_links USING btree (stories_id, topics_id, ref_stories_id);


--
-- Name: topic_links_topic; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_links_topic ON public.topic_links USING btree (topics_id);


--
-- Name: topic_maps_timespan; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_maps_timespan ON public.timespan_maps USING btree (timespans_id);


--
-- Name: topic_merged_stories_map_source; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_merged_stories_map_source ON public.topic_merged_stories_map USING btree (source_stories_id);


--
-- Name: topic_merged_stories_map_story; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_merged_stories_map_story ON public.topic_merged_stories_map USING btree (target_stories_id);


--
-- Name: topic_modes_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX topic_modes_name ON public.topic_modes USING btree (name);


--
-- Name: topic_permissions_topic; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_permissions_topic ON public.topic_permissions USING btree (topics_id);


--
-- Name: topic_permissions_user; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX topic_permissions_user ON public.topic_permissions USING btree (auth_users_id, topics_id);


--
-- Name: topic_platforms_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX topic_platforms_name ON public.topic_platforms USING btree (name);


--
-- Name: topic_platforms_sources_map_ps; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX topic_platforms_sources_map_ps ON public.topic_platforms_sources_map USING btree (topic_platforms_id, topic_sources_id);


--
-- Name: topic_post_days_td; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_post_days_td ON public.topic_post_days USING btree (topic_seed_queries_id, day);


--
-- Name: topic_post_topic_author; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_post_topic_author ON public.topic_posts USING btree (topic_post_days_id, author);


--
-- Name: topic_post_topic_channel; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_post_topic_channel ON public.topic_posts USING btree (topic_post_days_id, channel);


--
-- Name: topic_post_urls_tt; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX topic_post_urls_tt ON public.topic_post_urls USING btree (topic_posts_id, url);


--
-- Name: topic_post_urls_url; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_post_urls_url ON public.topic_post_urls USING btree (url);


--
-- Name: topic_posts_id; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX topic_posts_id ON public.topic_posts USING btree (topic_post_days_id, post_id);


--
-- Name: topic_seed_queries_topic; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_seed_queries_topic ON public.topic_seed_queries USING btree (topics_id);


--
-- Name: topic_seed_urls_story; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_seed_urls_story ON public.topic_seed_urls USING btree (stories_id);


--
-- Name: topic_seed_urls_topic; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_seed_urls_topic ON public.topic_seed_urls USING btree (topics_id);


--
-- Name: topic_seed_urls_tpu; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX topic_seed_urls_tpu ON public.topic_seed_urls USING btree (topic_post_urls_id);


--
-- Name: topic_seed_urls_url; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_seed_urls_url ON public.topic_seed_urls USING btree (url);


--
-- Name: topic_sources_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX topic_sources_name ON public.topic_sources USING btree (name);


--
-- Name: topic_spider_metrics_dat; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_spider_metrics_dat ON public.topic_spider_metrics USING btree (processed_date);


--
-- Name: topic_spider_metrics_topic; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_spider_metrics_topic ON public.topic_spider_metrics USING btree (topics_id);


--
-- Name: topic_stories_sc; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX topic_stories_sc ON public.topic_stories USING btree (stories_id, topics_id);


--
-- Name: topic_stories_topic; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topic_stories_topic ON public.topic_stories USING btree (topics_id);


--
-- Name: topics_media_map_topic; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topics_media_map_topic ON public.topics_media_map USING btree (topics_id);


--
-- Name: topics_media_tags_map_topic; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE INDEX topics_media_tags_map_topic ON public.topics_media_tags_map USING btree (topics_id);


--
-- Name: topics_media_type_tag_set; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX topics_media_type_tag_set ON public.topics USING btree (media_type_tag_sets_id);


--
-- Name: topics_name; Type: INDEX; Schema: public; Owner: mediacloud
--

CREATE UNIQUE INDEX topics_name ON public.topics USING btree (name);


--
-- Name: snapshot_files_id; Type: INDEX; Schema: public_store; Owner: mediacloud
--

CREATE UNIQUE INDEX snapshot_files_id ON public_store.snapshot_files USING btree (object_id);


--
-- Name: timespan_files_id; Type: INDEX; Schema: public_store; Owner: mediacloud
--

CREATE UNIQUE INDEX timespan_files_id ON public_store.timespan_files USING btree (object_id);


--
-- Name: timespan_maps_id; Type: INDEX; Schema: public_store; Owner: mediacloud
--

CREATE UNIQUE INDEX timespan_maps_id ON public_store.timespan_maps USING btree (object_id);


--
-- Name: live_stories_story; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE UNIQUE INDEX live_stories_story ON snap.live_stories USING btree (topics_id, stories_id);


--
-- Name: live_stories_story_solo; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX live_stories_story_solo ON snap.live_stories USING btree (stories_id);


--
-- Name: live_stories_title_hash; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX live_stories_title_hash ON snap.live_stories USING btree (topics_id, media_id, date_trunc('day'::text, publish_date), normalized_title_hash);


--
-- Name: live_stories_topic_story; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX live_stories_topic_story ON snap.live_stories USING btree (topic_stories_id);


--
-- Name: live_story_topic; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX live_story_topic ON snap.live_stories USING btree (topics_id);


--
-- Name: media_id; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX media_id ON snap.media USING btree (snapshots_id, media_id);


--
-- Name: media_tags_map_medium; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX media_tags_map_medium ON snap.media_tags_map USING btree (snapshots_id, media_id);


--
-- Name: media_tags_map_tag; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX media_tags_map_tag ON snap.media_tags_map USING btree (snapshots_id, tags_id);


--
-- Name: medium_link_counts_fb; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX medium_link_counts_fb ON snap.medium_link_counts USING btree (timespans_id, facebook_share_count DESC NULLS LAST);


--
-- Name: medium_link_counts_medium; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX medium_link_counts_medium ON snap.medium_link_counts USING btree (timespans_id, media_id);


--
-- Name: INDEX medium_link_counts_medium; Type: COMMENT; Schema: snap; Owner: mediacloud
--

COMMENT ON INDEX snap.medium_link_counts_medium IS 'TODO: add complex foreign key 
to check that media_id exists for the snapshot media snapshot';


--
-- Name: medium_link_counts_sum_author; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX medium_link_counts_sum_author ON snap.medium_link_counts USING btree (timespans_id, sum_author_count DESC NULLS LAST);


--
-- Name: medium_link_counts_sum_channel; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX medium_link_counts_sum_channel ON snap.medium_link_counts USING btree (timespans_id, sum_channel_count DESC NULLS LAST);


--
-- Name: medium_link_counts_sum_post; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX medium_link_counts_sum_post ON snap.medium_link_counts USING btree (timespans_id, sum_post_count DESC NULLS LAST);


--
-- Name: medium_links_ref; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX medium_links_ref ON snap.medium_links USING btree (timespans_id, ref_media_id);


--
-- Name: medium_links_source; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX medium_links_source ON snap.medium_links USING btree (timespans_id, source_media_id);


--
-- Name: INDEX medium_links_source; Type: COMMENT; Schema: snap; Owner: mediacloud
--

COMMENT ON INDEX snap.medium_links_source IS 'TODO: add complex foreign key to check that 
*_media_id exist for the snapshot media snapshot';


--
-- Name: snap_timespan_posts_u; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE UNIQUE INDEX snap_timespan_posts_u ON snap.timespan_posts USING btree (timespans_id, topic_posts_id);


--
-- Name: snap_word2vec_models_data_object_id; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE UNIQUE INDEX snap_word2vec_models_data_object_id ON snap.word2vec_models_data USING btree (object_id);


--
-- Name: snap_word2vec_models_object_id_creation_date; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX snap_word2vec_models_object_id_creation_date ON snap.word2vec_models USING btree (object_id, creation_date);


--
-- Name: INDEX snap_word2vec_models_object_id_creation_date; Type: COMMENT; Schema: snap; Owner: mediacloud
--

COMMENT ON INDEX snap.snap_word2vec_models_object_id_creation_date IS 'We need to find the latest word2vec model';


--
-- Name: stories_id; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX stories_id ON snap.stories USING btree (snapshots_id, stories_id);


--
-- Name: stories_tags_map_story; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX stories_tags_map_story ON snap.stories_tags_map USING btree (snapshots_id, stories_id);


--
-- Name: stories_tags_map_tag; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX stories_tags_map_tag ON snap.stories_tags_map USING btree (snapshots_id, tags_id);


--
-- Name: story_link_counts_author; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX story_link_counts_author ON snap.story_link_counts USING btree (timespans_id, author_count DESC NULLS LAST);


--
-- Name: story_link_counts_channel; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX story_link_counts_channel ON snap.story_link_counts USING btree (timespans_id, channel_count DESC NULLS LAST);


--
-- Name: story_link_counts_fb; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX story_link_counts_fb ON snap.story_link_counts USING btree (timespans_id, facebook_share_count DESC NULLS LAST);


--
-- Name: story_link_counts_post; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX story_link_counts_post ON snap.story_link_counts USING btree (timespans_id, post_count DESC NULLS LAST);


--
-- Name: story_link_counts_story; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX story_link_counts_story ON snap.story_link_counts USING btree (stories_id);


--
-- Name: story_link_counts_ts; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX story_link_counts_ts ON snap.story_link_counts USING btree (timespans_id, stories_id);


--
-- Name: INDEX story_link_counts_ts; Type: COMMENT; Schema: snap; Owner: mediacloud
--

COMMENT ON INDEX snap.story_link_counts_ts IS 'TODO: add complex foreign key to check that stories_id 
exists for the snapshot stories snapshot';


--
-- Name: story_links_ref; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX story_links_ref ON snap.story_links USING btree (timespans_id, ref_stories_id);


--
-- Name: story_links_source; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX story_links_source ON snap.story_links USING btree (timespans_id, source_stories_id);


--
-- Name: INDEX story_links_source; Type: COMMENT; Schema: snap; Owner: mediacloud
--

COMMENT ON INDEX snap.story_links_source IS 'TODO: add complex foreign key to check that 
*_stories_id exist for the snapshot stories snapshot';


--
-- Name: topic_links_ref; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX topic_links_ref ON snap.topic_links_cross_media USING btree (snapshots_id, ref_stories_id);


--
-- Name: topic_links_story; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX topic_links_story ON snap.topic_links_cross_media USING btree (snapshots_id, stories_id);


--
-- Name: topic_media_codes_medium; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX topic_media_codes_medium ON snap.topic_media_codes USING btree (snapshots_id, media_id);


--
-- Name: topic_stories_id; Type: INDEX; Schema: snap; Owner: mediacloud
--

CREATE INDEX topic_stories_id ON snap.topic_stories USING btree (snapshots_id, stories_id);


--
-- Name: download_texts_00_downloads_id_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.download_texts_downloads_id ATTACH PARTITION public.download_texts_00_downloads_id_idx;


--
-- Name: download_texts_00_pkey; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.download_texts_pkey ATTACH PARTITION public.download_texts_00_pkey;


--
-- Name: downloads_error_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_time ATTACH PARTITION public.downloads_error_download_time_idx;


--
-- Name: downloads_error_feeds_id_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_feed_download_time ATTACH PARTITION public.downloads_error_feeds_id_download_time_idx;


--
-- Name: downloads_error_parent_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_parent ATTACH PARTITION public.downloads_error_parent_idx;


--
-- Name: downloads_error_pkey; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_pkey ATTACH PARTITION public.downloads_error_pkey;


--
-- Name: downloads_error_stories_id_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_story ATTACH PARTITION public.downloads_error_stories_id_idx;


--
-- Name: downloads_feed_error_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_time ATTACH PARTITION public.downloads_feed_error_download_time_idx;


--
-- Name: downloads_feed_error_feeds_id_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_feed_download_time ATTACH PARTITION public.downloads_feed_error_feeds_id_download_time_idx;


--
-- Name: downloads_feed_error_parent_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_parent ATTACH PARTITION public.downloads_feed_error_parent_idx;


--
-- Name: downloads_feed_error_pkey; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_pkey ATTACH PARTITION public.downloads_feed_error_pkey;


--
-- Name: downloads_feed_error_stories_id_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_story ATTACH PARTITION public.downloads_feed_error_stories_id_idx;


--
-- Name: downloads_fetching_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_time ATTACH PARTITION public.downloads_fetching_download_time_idx;


--
-- Name: downloads_fetching_feeds_id_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_feed_download_time ATTACH PARTITION public.downloads_fetching_feeds_id_download_time_idx;


--
-- Name: downloads_fetching_parent_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_parent ATTACH PARTITION public.downloads_fetching_parent_idx;


--
-- Name: downloads_fetching_pkey; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_pkey ATTACH PARTITION public.downloads_fetching_pkey;


--
-- Name: downloads_fetching_stories_id_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_story ATTACH PARTITION public.downloads_fetching_stories_id_idx;


--
-- Name: downloads_pending_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_time ATTACH PARTITION public.downloads_pending_download_time_idx;


--
-- Name: downloads_pending_feeds_id_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_feed_download_time ATTACH PARTITION public.downloads_pending_feeds_id_download_time_idx;


--
-- Name: downloads_pending_parent_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_parent ATTACH PARTITION public.downloads_pending_parent_idx;


--
-- Name: downloads_pending_pkey; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_pkey ATTACH PARTITION public.downloads_pending_pkey;


--
-- Name: downloads_pending_stories_id_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_story ATTACH PARTITION public.downloads_pending_stories_id_idx;


--
-- Name: downloads_success_content_00_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_content_download_time_idx ATTACH PARTITION public.downloads_success_content_00_download_time_idx;


--
-- Name: downloads_success_content_00_downloads_id_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_content_downloads_id ATTACH PARTITION public.downloads_success_content_00_downloads_id_idx;


--
-- Name: downloads_success_content_00_extracted_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_content_extracted ATTACH PARTITION public.downloads_success_content_00_extracted_idx;


--
-- Name: downloads_success_content_00_feeds_id_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_content_feeds_id_download_time_idx ATTACH PARTITION public.downloads_success_content_00_feeds_id_download_time_idx;


--
-- Name: downloads_success_content_00_parent_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_content_parent_idx ATTACH PARTITION public.downloads_success_content_00_parent_idx;


--
-- Name: downloads_success_content_00_pkey; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_content_pkey ATTACH PARTITION public.downloads_success_content_00_pkey;


--
-- Name: downloads_success_content_00_stories_id_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_content_stories_id_idx ATTACH PARTITION public.downloads_success_content_00_stories_id_idx;


--
-- Name: downloads_success_content_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_download_time_idx ATTACH PARTITION public.downloads_success_content_download_time_idx;


--
-- Name: downloads_success_content_feeds_id_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_feeds_id_download_time_idx ATTACH PARTITION public.downloads_success_content_feeds_id_download_time_idx;


--
-- Name: downloads_success_content_parent_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_parent_idx ATTACH PARTITION public.downloads_success_content_parent_idx;


--
-- Name: downloads_success_content_pkey; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_pkey ATTACH PARTITION public.downloads_success_content_pkey;


--
-- Name: downloads_success_content_stories_id_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_stories_id_idx ATTACH PARTITION public.downloads_success_content_stories_id_idx;


--
-- Name: downloads_success_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_time ATTACH PARTITION public.downloads_success_download_time_idx;


--
-- Name: downloads_success_feed_00_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_feed_download_time_idx ATTACH PARTITION public.downloads_success_feed_00_download_time_idx;


--
-- Name: downloads_success_feed_00_feeds_id_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_feed_feeds_id_download_time_idx ATTACH PARTITION public.downloads_success_feed_00_feeds_id_download_time_idx;


--
-- Name: downloads_success_feed_00_parent_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_feed_parent_idx ATTACH PARTITION public.downloads_success_feed_00_parent_idx;


--
-- Name: downloads_success_feed_00_pkey; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_feed_pkey ATTACH PARTITION public.downloads_success_feed_00_pkey;


--
-- Name: downloads_success_feed_00_stories_id_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_feed_stories_id_idx ATTACH PARTITION public.downloads_success_feed_00_stories_id_idx;


--
-- Name: downloads_success_feed_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_download_time_idx ATTACH PARTITION public.downloads_success_feed_download_time_idx;


--
-- Name: downloads_success_feed_feeds_id_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_feeds_id_download_time_idx ATTACH PARTITION public.downloads_success_feed_feeds_id_download_time_idx;


--
-- Name: downloads_success_feed_parent_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_parent_idx ATTACH PARTITION public.downloads_success_feed_parent_idx;


--
-- Name: downloads_success_feed_pkey; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_pkey ATTACH PARTITION public.downloads_success_feed_pkey;


--
-- Name: downloads_success_feed_stories_id_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_success_stories_id_idx ATTACH PARTITION public.downloads_success_feed_stories_id_idx;


--
-- Name: downloads_success_feeds_id_download_time_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_feed_download_time ATTACH PARTITION public.downloads_success_feeds_id_download_time_idx;


--
-- Name: downloads_success_parent_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_parent ATTACH PARTITION public.downloads_success_parent_idx;


--
-- Name: downloads_success_pkey; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_pkey ATTACH PARTITION public.downloads_success_pkey;


--
-- Name: downloads_success_stories_id_idx; Type: INDEX ATTACH; Schema: public; Owner: mediacloud
--

ALTER INDEX public.downloads_story ATTACH PARTITION public.downloads_success_stories_id_idx;


--
-- Name: extractor_results_cache extractor_results_cache_db_row_last_updated_trigger; Type: TRIGGER; Schema: cache; Owner: mediacloud
--

CREATE TRIGGER extractor_results_cache_db_row_last_updated_trigger BEFORE INSERT OR UPDATE ON cache.extractor_results_cache FOR EACH ROW EXECUTE FUNCTION cache.update_cache_db_row_last_updated();


--
-- Name: extractor_results_cache extractor_results_cache_test_referenced_download_trigger; Type: TRIGGER; Schema: cache; Owner: mediacloud
--

CREATE TRIGGER extractor_results_cache_test_referenced_download_trigger BEFORE INSERT OR UPDATE ON cache.extractor_results_cache FOR EACH ROW EXECUTE FUNCTION public.test_referenced_download_trigger('downloads_id');


--
-- Name: s3_raw_downloads_cache s3_raw_downloads_cache_db_row_last_updated_trigger; Type: TRIGGER; Schema: cache; Owner: mediacloud
--

CREATE TRIGGER s3_raw_downloads_cache_db_row_last_updated_trigger BEFORE INSERT OR UPDATE ON cache.s3_raw_downloads_cache FOR EACH ROW EXECUTE FUNCTION cache.update_cache_db_row_last_updated();


--
-- Name: s3_raw_downloads_cache s3_raw_downloads_cache_test_referenced_download_trigger; Type: TRIGGER; Schema: cache; Owner: mediacloud
--

CREATE TRIGGER s3_raw_downloads_cache_test_referenced_download_trigger BEFORE INSERT OR UPDATE ON cache.s3_raw_downloads_cache FOR EACH ROW EXECUTE FUNCTION public.test_referenced_download_trigger('object_id');


--
-- Name: auth_users auth_user_api_keys_add_non_ip_limited_api_key; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER auth_user_api_keys_add_non_ip_limited_api_key AFTER INSERT ON public.auth_users FOR EACH ROW EXECUTE FUNCTION public.auth_user_api_keys_add_non_ip_limited_api_key();


--
-- Name: auth_users auth_users_set_default_limits; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER auth_users_set_default_limits AFTER INSERT ON public.auth_users FOR EACH ROW EXECUTE FUNCTION public.auth_users_set_default_limits();


--
-- Name: download_texts_00 download_texts_00_test_referenced_download_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER download_texts_00_test_referenced_download_trigger BEFORE INSERT OR UPDATE ON public.download_texts_00 FOR EACH ROW EXECUTE FUNCTION public.test_referenced_download_trigger('downloads_id');


--
-- Name: downloads_error downloads_error_test_referenced_download_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER downloads_error_test_referenced_download_trigger BEFORE INSERT OR UPDATE ON public.downloads_error FOR EACH ROW EXECUTE FUNCTION public.test_referenced_download_trigger('parent');


--
-- Name: downloads_feed_error downloads_feed_error_test_referenced_download_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER downloads_feed_error_test_referenced_download_trigger BEFORE INSERT OR UPDATE ON public.downloads_feed_error FOR EACH ROW EXECUTE FUNCTION public.test_referenced_download_trigger('parent');


--
-- Name: downloads_fetching downloads_fetching_test_referenced_download_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER downloads_fetching_test_referenced_download_trigger BEFORE INSERT OR UPDATE ON public.downloads_fetching FOR EACH ROW EXECUTE FUNCTION public.test_referenced_download_trigger('parent');


--
-- Name: downloads_pending downloads_pending_test_referenced_download_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER downloads_pending_test_referenced_download_trigger BEFORE INSERT OR UPDATE ON public.downloads_pending FOR EACH ROW EXECUTE FUNCTION public.test_referenced_download_trigger('parent');


--
-- Name: downloads_success_content_00 downloads_success_content_00_test_referenced_download_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER downloads_success_content_00_test_referenced_download_trigger BEFORE INSERT OR UPDATE ON public.downloads_success_content_00 FOR EACH ROW EXECUTE FUNCTION public.test_referenced_download_trigger('parent');


--
-- Name: downloads_success_feed_00 downloads_success_feed_00_test_referenced_download_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER downloads_success_feed_00_test_referenced_download_trigger BEFORE INSERT OR UPDATE ON public.downloads_success_feed_00 FOR EACH ROW EXECUTE FUNCTION public.test_referenced_download_trigger('parent');


--
-- Name: feeds_stories_map_p feeds_stories_map_p_insert_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER feeds_stories_map_p_insert_trigger BEFORE INSERT ON public.feeds_stories_map_p FOR EACH ROW EXECUTE FUNCTION public.feeds_stories_map_p_insert_trigger();


--
-- Name: feeds_stories_map feeds_stories_map_view_insert_update_delete_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER feeds_stories_map_view_insert_update_delete_trigger INSTEAD OF INSERT OR DELETE OR UPDATE ON public.feeds_stories_map FOR EACH ROW EXECUTE FUNCTION public.feeds_stories_map_view_insert_update_delete();


--
-- Name: media media_rescraping_add_initial_state_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER media_rescraping_add_initial_state_trigger AFTER INSERT ON public.media FOR EACH ROW EXECUTE FUNCTION public.media_rescraping_add_initial_state_trigger();


--
-- Name: processed_stories ps_insert_solr_import_story; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER ps_insert_solr_import_story AFTER INSERT OR DELETE OR UPDATE ON public.processed_stories FOR EACH ROW EXECUTE FUNCTION public.insert_solr_import_story();


--
-- Name: raw_downloads raw_downloads_test_referenced_download_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER raw_downloads_test_referenced_download_trigger BEFORE INSERT OR UPDATE ON public.raw_downloads FOR EACH ROW EXECUTE FUNCTION public.test_referenced_download_trigger('object_id');


--
-- Name: stories stories_add_normalized_title; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER stories_add_normalized_title BEFORE INSERT OR UPDATE ON public.stories FOR EACH ROW EXECUTE FUNCTION public.add_normalized_title_hash();


--
-- Name: stories stories_insert_solr_import_story; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER stories_insert_solr_import_story AFTER INSERT OR DELETE OR UPDATE ON public.stories FOR EACH ROW EXECUTE FUNCTION public.insert_solr_import_story();


--
-- Name: stories_tags_map_p stories_tags_map_p_insert_solr_import_story; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER stories_tags_map_p_insert_solr_import_story BEFORE INSERT OR DELETE OR UPDATE ON public.stories_tags_map_p FOR EACH ROW EXECUTE FUNCTION public.insert_solr_import_story();


--
-- Name: stories_tags_map_p stories_tags_map_p_upsert_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER stories_tags_map_p_upsert_trigger BEFORE INSERT ON public.stories_tags_map_p FOR EACH ROW EXECUTE FUNCTION public.stories_tags_map_p_upsert_trigger();


--
-- Name: stories_tags_map stories_tags_map_view_insert_update_delete; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER stories_tags_map_view_insert_update_delete INSTEAD OF INSERT OR DELETE OR UPDATE ON public.stories_tags_map FOR EACH ROW EXECUTE FUNCTION public.stories_tags_map_view_insert_update_delete();


--
-- Name: stories stories_update_live_story; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER stories_update_live_story AFTER UPDATE ON public.stories FOR EACH ROW EXECUTE FUNCTION public.update_live_story();


--
-- Name: story_sentences_p story_sentences_p_insert_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER story_sentences_p_insert_trigger BEFORE INSERT ON public.story_sentences_p FOR EACH ROW EXECUTE FUNCTION public.story_sentences_p_insert_trigger();


--
-- Name: story_sentences story_sentences_view_insert_update_delete_trigger; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER story_sentences_view_insert_update_delete_trigger INSTEAD OF INSERT OR DELETE OR UPDATE ON public.story_sentences FOR EACH ROW EXECUTE FUNCTION public.story_sentences_view_insert_update_delete();


--
-- Name: topic_stories topic_stories_insert_live_story; Type: TRIGGER; Schema: public; Owner: mediacloud
--

CREATE TRIGGER topic_stories_insert_live_story AFTER INSERT ON public.topic_stories FOR EACH ROW EXECUTE FUNCTION public.insert_live_story();


--
-- Name: api_links api_links_next_link_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.api_links
    ADD CONSTRAINT api_links_next_link_id_fkey FOREIGN KEY (next_link_id) REFERENCES public.api_links(api_links_id) ON DELETE SET NULL DEFERRABLE;


--
-- Name: api_links api_links_previous_link_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.api_links
    ADD CONSTRAINT api_links_previous_link_id_fkey FOREIGN KEY (previous_link_id) REFERENCES public.api_links(api_links_id) ON DELETE SET NULL DEFERRABLE;


--
-- Name: auth_user_api_keys auth_user_api_keys_auth_users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_user_api_keys
    ADD CONSTRAINT auth_user_api_keys_auth_users_id_fkey FOREIGN KEY (auth_users_id) REFERENCES public.auth_users(auth_users_id) ON DELETE CASCADE;


--
-- Name: auth_user_limits auth_user_limits_auth_users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_user_limits
    ADD CONSTRAINT auth_user_limits_auth_users_id_fkey FOREIGN KEY (auth_users_id) REFERENCES public.auth_users(auth_users_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: auth_users_roles_map auth_users_roles_map_auth_roles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_users_roles_map
    ADD CONSTRAINT auth_users_roles_map_auth_roles_id_fkey FOREIGN KEY (auth_roles_id) REFERENCES public.auth_roles(auth_roles_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: auth_users_roles_map auth_users_roles_map_auth_users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_users_roles_map
    ADD CONSTRAINT auth_users_roles_map_auth_users_id_fkey FOREIGN KEY (auth_users_id) REFERENCES public.auth_users(auth_users_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: auth_users_tag_sets_permissions auth_users_tag_sets_permissions_auth_users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_users_tag_sets_permissions
    ADD CONSTRAINT auth_users_tag_sets_permissions_auth_users_id_fkey FOREIGN KEY (auth_users_id) REFERENCES public.auth_users(auth_users_id);


--
-- Name: auth_users_tag_sets_permissions auth_users_tag_sets_permissions_tag_sets_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.auth_users_tag_sets_permissions
    ADD CONSTRAINT auth_users_tag_sets_permissions_tag_sets_id_fkey FOREIGN KEY (tag_sets_id) REFERENCES public.tag_sets(tag_sets_id);


--
-- Name: cliff_annotations cliff_annotations_object_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.cliff_annotations
    ADD CONSTRAINT cliff_annotations_object_id_fkey FOREIGN KEY (object_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: download_texts_00 download_texts_00_downloads_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.download_texts_00
    ADD CONSTRAINT download_texts_00_downloads_id_fkey FOREIGN KEY (downloads_id) REFERENCES public.downloads_success_content_00(downloads_id) ON DELETE CASCADE;


--
-- Name: downloads downloads_feeds_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE public.downloads
    ADD CONSTRAINT downloads_feeds_id_fkey FOREIGN KEY (feeds_id) REFERENCES public.feeds(feeds_id);


--
-- Name: downloads downloads_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE public.downloads
    ADD CONSTRAINT downloads_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: feeds_after_rescraping feeds_after_rescraping_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_after_rescraping
    ADD CONSTRAINT feeds_after_rescraping_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: feeds feeds_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds
    ADD CONSTRAINT feeds_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: feeds_stories_map_p_00 feeds_stories_map_p_00_feeds_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_stories_map_p_00
    ADD CONSTRAINT feeds_stories_map_p_00_feeds_id_fkey FOREIGN KEY (feeds_id) REFERENCES public.feeds(feeds_id) MATCH FULL ON DELETE CASCADE;


--
-- Name: feeds_stories_map_p_00 feeds_stories_map_p_00_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_stories_map_p_00
    ADD CONSTRAINT feeds_stories_map_p_00_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) MATCH FULL ON DELETE CASCADE;


--
-- Name: feeds_tags_map feeds_tags_map_feeds_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_tags_map
    ADD CONSTRAINT feeds_tags_map_feeds_id_fkey FOREIGN KEY (feeds_id) REFERENCES public.feeds(feeds_id) ON DELETE CASCADE;


--
-- Name: feeds_tags_map feeds_tags_map_tags_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.feeds_tags_map
    ADD CONSTRAINT feeds_tags_map_tags_id_fkey FOREIGN KEY (tags_id) REFERENCES public.tags(tags_id) ON DELETE CASCADE;


--
-- Name: focal_set_definitions focal_set_definitions_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.focal_set_definitions
    ADD CONSTRAINT focal_set_definitions_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: focal_sets focal_sets_snapshots_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.focal_sets
    ADD CONSTRAINT focal_sets_snapshots_id_fkey FOREIGN KEY (snapshots_id) REFERENCES public.snapshots(snapshots_id);


--
-- Name: foci foci_focal_sets_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.foci
    ADD CONSTRAINT foci_focal_sets_id_fkey FOREIGN KEY (focal_sets_id) REFERENCES public.focal_sets(focal_sets_id) ON DELETE CASCADE;


--
-- Name: focus_definitions focus_definitions_focal_set_definitions_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.focus_definitions
    ADD CONSTRAINT focus_definitions_focal_set_definitions_id_fkey FOREIGN KEY (focal_set_definitions_id) REFERENCES public.focal_set_definitions(focal_set_definitions_id) ON DELETE CASCADE;


--
-- Name: media_coverage_gaps media_coverage_gaps_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_coverage_gaps
    ADD CONSTRAINT media_coverage_gaps_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: media media_dup_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media
    ADD CONSTRAINT media_dup_media_id_fkey FOREIGN KEY (dup_media_id) REFERENCES public.media(media_id) ON DELETE SET NULL DEFERRABLE;


--
-- Name: media_expected_volume media_expected_volume_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_expected_volume
    ADD CONSTRAINT media_expected_volume_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: media_health media_health_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_health
    ADD CONSTRAINT media_health_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: media_rescraping media_rescraping_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_rescraping
    ADD CONSTRAINT media_rescraping_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: media_similarweb_domains_map media_similarweb_domains_map_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_similarweb_domains_map
    ADD CONSTRAINT media_similarweb_domains_map_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: media_similarweb_domains_map media_similarweb_domains_map_similarweb_domains_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_similarweb_domains_map
    ADD CONSTRAINT media_similarweb_domains_map_similarweb_domains_id_fkey FOREIGN KEY (similarweb_domains_id) REFERENCES public.similarweb_domains(similarweb_domains_id) ON DELETE CASCADE;


--
-- Name: media_sitemap_pages media_sitemap_pages_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_sitemap_pages
    ADD CONSTRAINT media_sitemap_pages_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: media_stats media_stats_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_stats
    ADD CONSTRAINT media_stats_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: media_stats_weekly media_stats_weekly_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_stats_weekly
    ADD CONSTRAINT media_stats_weekly_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: media_suggestions media_suggestions_auth_users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_suggestions
    ADD CONSTRAINT media_suggestions_auth_users_id_fkey FOREIGN KEY (auth_users_id) REFERENCES public.auth_users(auth_users_id) ON DELETE SET NULL;


--
-- Name: media_suggestions media_suggestions_mark_auth_users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_suggestions
    ADD CONSTRAINT media_suggestions_mark_auth_users_id_fkey FOREIGN KEY (mark_auth_users_id) REFERENCES public.auth_users(auth_users_id) ON DELETE SET NULL;


--
-- Name: media_suggestions media_suggestions_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_suggestions
    ADD CONSTRAINT media_suggestions_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE SET NULL;


--
-- Name: media_suggestions_tags_map media_suggestions_tags_map_media_suggestions_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_suggestions_tags_map
    ADD CONSTRAINT media_suggestions_tags_map_media_suggestions_id_fkey FOREIGN KEY (media_suggestions_id) REFERENCES public.media_suggestions(media_suggestions_id) ON DELETE CASCADE;


--
-- Name: media_suggestions_tags_map media_suggestions_tags_map_tags_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_suggestions_tags_map
    ADD CONSTRAINT media_suggestions_tags_map_tags_id_fkey FOREIGN KEY (tags_id) REFERENCES public.tags(tags_id) ON DELETE CASCADE;


--
-- Name: media_tags_map media_tags_map_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_tags_map
    ADD CONSTRAINT media_tags_map_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: media_tags_map media_tags_map_tags_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.media_tags_map
    ADD CONSTRAINT media_tags_map_tags_id_fkey FOREIGN KEY (tags_id) REFERENCES public.tags(tags_id) ON DELETE CASCADE;


--
-- Name: nytlabels_annotations nytlabels_annotations_object_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.nytlabels_annotations
    ADD CONSTRAINT nytlabels_annotations_object_id_fkey FOREIGN KEY (object_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: processed_stories processed_stories_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.processed_stories
    ADD CONSTRAINT processed_stories_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: retweeter_groups retweeter_groups_retweeter_scores_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_groups
    ADD CONSTRAINT retweeter_groups_retweeter_scores_id_fkey FOREIGN KEY (retweeter_scores_id) REFERENCES public.retweeter_scores(retweeter_scores_id) ON DELETE CASCADE;


--
-- Name: retweeter_groups_users_map retweeter_groups_users_map_retweeter_groups_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_groups_users_map
    ADD CONSTRAINT retweeter_groups_users_map_retweeter_groups_id_fkey FOREIGN KEY (retweeter_groups_id) REFERENCES public.retweeter_groups(retweeter_groups_id) ON DELETE CASCADE;


--
-- Name: retweeter_groups_users_map retweeter_groups_users_map_retweeter_scores_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_groups_users_map
    ADD CONSTRAINT retweeter_groups_users_map_retweeter_scores_id_fkey FOREIGN KEY (retweeter_scores_id) REFERENCES public.retweeter_scores(retweeter_scores_id) ON DELETE CASCADE;


--
-- Name: retweeter_media retweeter_media_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_media
    ADD CONSTRAINT retweeter_media_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: retweeter_media retweeter_media_retweeter_scores_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_media
    ADD CONSTRAINT retweeter_media_retweeter_scores_id_fkey FOREIGN KEY (retweeter_scores_id) REFERENCES public.retweeter_scores(retweeter_scores_id) ON DELETE CASCADE;


--
-- Name: retweeter_partition_matrix retweeter_partition_matrix_retweeter_groups_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_partition_matrix
    ADD CONSTRAINT retweeter_partition_matrix_retweeter_groups_id_fkey FOREIGN KEY (retweeter_groups_id) REFERENCES public.retweeter_groups(retweeter_groups_id) ON DELETE CASCADE;


--
-- Name: retweeter_partition_matrix retweeter_partition_matrix_retweeter_scores_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_partition_matrix
    ADD CONSTRAINT retweeter_partition_matrix_retweeter_scores_id_fkey FOREIGN KEY (retweeter_scores_id) REFERENCES public.retweeter_scores(retweeter_scores_id) ON DELETE CASCADE;


--
-- Name: retweeter_scores retweeter_scores_group_a; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_scores
    ADD CONSTRAINT retweeter_scores_group_a FOREIGN KEY (group_a_id) REFERENCES public.retweeter_groups(retweeter_groups_id) ON DELETE CASCADE;


--
-- Name: retweeter_scores retweeter_scores_group_b; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_scores
    ADD CONSTRAINT retweeter_scores_group_b FOREIGN KEY (group_b_id) REFERENCES public.retweeter_groups(retweeter_groups_id) ON DELETE CASCADE;


--
-- Name: retweeter_scores retweeter_scores_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_scores
    ADD CONSTRAINT retweeter_scores_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: retweeter_stories retweeter_stories_retweeter_scores_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_stories
    ADD CONSTRAINT retweeter_stories_retweeter_scores_id_fkey FOREIGN KEY (retweeter_scores_id) REFERENCES public.retweeter_scores(retweeter_scores_id) ON DELETE CASCADE;


--
-- Name: retweeter_stories retweeter_stories_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeter_stories
    ADD CONSTRAINT retweeter_stories_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: retweeters retweeters_retweeter_scores_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.retweeters
    ADD CONSTRAINT retweeters_retweeter_scores_id_fkey FOREIGN KEY (retweeter_scores_id) REFERENCES public.retweeter_scores(retweeter_scores_id) ON DELETE CASCADE;


--
-- Name: scraped_feeds scraped_feeds_feeds_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.scraped_feeds
    ADD CONSTRAINT scraped_feeds_feeds_id_fkey FOREIGN KEY (feeds_id) REFERENCES public.feeds(feeds_id) ON DELETE CASCADE;


--
-- Name: scraped_stories scraped_stories_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.scraped_stories
    ADD CONSTRAINT scraped_stories_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: similarweb_estimated_visits similarweb_estimated_visits_similarweb_domains_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.similarweb_estimated_visits
    ADD CONSTRAINT similarweb_estimated_visits_similarweb_domains_id_fkey FOREIGN KEY (similarweb_domains_id) REFERENCES public.similarweb_domains(similarweb_domains_id) ON DELETE CASCADE;


--
-- Name: snapshot_files snapshot_files_snapshots_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.snapshot_files
    ADD CONSTRAINT snapshot_files_snapshots_id_fkey FOREIGN KEY (snapshots_id) REFERENCES public.snapshots(snapshots_id) ON DELETE CASCADE;


--
-- Name: snapshots snapshots_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.snapshots
    ADD CONSTRAINT snapshots_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: solr_import_stories solr_import_stories_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.solr_import_stories
    ADD CONSTRAINT solr_import_stories_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: solr_imported_stories solr_imported_stories_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.solr_imported_stories
    ADD CONSTRAINT solr_imported_stories_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: stories_ap_syndicated stories_ap_syndicated_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories_ap_syndicated
    ADD CONSTRAINT stories_ap_syndicated_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: stories stories_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories
    ADD CONSTRAINT stories_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: stories_tags_map_p_00 stories_tags_map_p_00_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories_tags_map_p_00
    ADD CONSTRAINT stories_tags_map_p_00_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) MATCH FULL ON DELETE CASCADE;


--
-- Name: stories_tags_map_p_00 stories_tags_map_p_00_tags_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.stories_tags_map_p_00
    ADD CONSTRAINT stories_tags_map_p_00_tags_id_fkey FOREIGN KEY (tags_id) REFERENCES public.tags(tags_id) MATCH FULL ON DELETE CASCADE;


--
-- Name: story_enclosures story_enclosures_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_enclosures
    ADD CONSTRAINT story_enclosures_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: story_sentences_p_00 story_sentences_p_00_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_sentences_p_00
    ADD CONSTRAINT story_sentences_p_00_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) MATCH FULL ON DELETE CASCADE;


--
-- Name: story_sentences_p_00 story_sentences_p_00_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_sentences_p_00
    ADD CONSTRAINT story_sentences_p_00_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) MATCH FULL ON DELETE CASCADE;


--
-- Name: story_statistics story_statistics_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_statistics
    ADD CONSTRAINT story_statistics_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: story_statistics_twitter story_statistics_twitter_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_statistics_twitter
    ADD CONSTRAINT story_statistics_twitter_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: story_urls story_urls_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.story_urls
    ADD CONSTRAINT story_urls_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: tags tags_tag_sets_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_tag_sets_id_fkey FOREIGN KEY (tag_sets_id) REFERENCES public.tag_sets(tag_sets_id);


--
-- Name: timespan_files timespan_files_timespans_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.timespan_files
    ADD CONSTRAINT timespan_files_timespans_id_fkey FOREIGN KEY (timespans_id) REFERENCES public.timespans(timespans_id) ON DELETE CASCADE;


--
-- Name: timespan_maps timespan_maps_timespans_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.timespan_maps
    ADD CONSTRAINT timespan_maps_timespans_id_fkey FOREIGN KEY (timespans_id) REFERENCES public.timespans(timespans_id) ON DELETE CASCADE;


--
-- Name: timespans timespans_archive_snapshots_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.timespans
    ADD CONSTRAINT timespans_archive_snapshots_id_fkey FOREIGN KEY (archive_snapshots_id) REFERENCES public.snapshots(snapshots_id) ON DELETE CASCADE;


--
-- Name: timespans timespans_foci_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.timespans
    ADD CONSTRAINT timespans_foci_id_fkey FOREIGN KEY (foci_id) REFERENCES public.foci(foci_id);


--
-- Name: timespans timespans_snapshots_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.timespans
    ADD CONSTRAINT timespans_snapshots_id_fkey FOREIGN KEY (snapshots_id) REFERENCES public.snapshots(snapshots_id) ON DELETE CASCADE;


--
-- Name: timespans timespans_tags_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.timespans
    ADD CONSTRAINT timespans_tags_id_fkey FOREIGN KEY (tags_id) REFERENCES public.tags(tags_id);


--
-- Name: topic_dates topic_dates_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_dates
    ADD CONSTRAINT topic_dates_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: topic_fetch_urls topic_fetch_urls_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_fetch_urls
    ADD CONSTRAINT topic_fetch_urls_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: topic_fetch_urls topic_fetch_urls_topic_links_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_fetch_urls
    ADD CONSTRAINT topic_fetch_urls_topic_links_id_fkey FOREIGN KEY (topic_links_id) REFERENCES public.topic_links(topic_links_id) ON DELETE CASCADE;


--
-- Name: topic_fetch_urls topic_fetch_urls_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_fetch_urls
    ADD CONSTRAINT topic_fetch_urls_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: topic_links topic_links_ref_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_links
    ADD CONSTRAINT topic_links_ref_stories_id_fkey FOREIGN KEY (ref_stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: topic_links topic_links_topic_story_stories_id; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_links
    ADD CONSTRAINT topic_links_topic_story_stories_id FOREIGN KEY (stories_id, topics_id) REFERENCES public.topic_stories(stories_id, topics_id) ON DELETE CASCADE;


--
-- Name: topic_media_codes topic_media_codes_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_media_codes
    ADD CONSTRAINT topic_media_codes_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: topic_media_codes topic_media_codes_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_media_codes
    ADD CONSTRAINT topic_media_codes_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: topic_merged_stories_map topic_merged_stories_map_source_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_merged_stories_map
    ADD CONSTRAINT topic_merged_stories_map_source_stories_id_fkey FOREIGN KEY (source_stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: topic_merged_stories_map topic_merged_stories_map_target_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_merged_stories_map
    ADD CONSTRAINT topic_merged_stories_map_target_stories_id_fkey FOREIGN KEY (target_stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: topic_permissions topic_permissions_auth_users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_permissions
    ADD CONSTRAINT topic_permissions_auth_users_id_fkey FOREIGN KEY (auth_users_id) REFERENCES public.auth_users(auth_users_id) ON DELETE CASCADE;


--
-- Name: topic_permissions topic_permissions_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_permissions
    ADD CONSTRAINT topic_permissions_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: topic_platforms_sources_map topic_platforms_sources_map_topic_platforms_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_platforms_sources_map
    ADD CONSTRAINT topic_platforms_sources_map_topic_platforms_id_fkey FOREIGN KEY (topic_platforms_id) REFERENCES public.topic_platforms(topic_platforms_id) ON DELETE CASCADE;


--
-- Name: topic_platforms_sources_map topic_platforms_sources_map_topic_sources_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_platforms_sources_map
    ADD CONSTRAINT topic_platforms_sources_map_topic_sources_id_fkey FOREIGN KEY (topic_sources_id) REFERENCES public.topic_sources(topic_sources_id) ON DELETE CASCADE;


--
-- Name: topic_post_days topic_post_days_topic_seed_queries_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_post_days
    ADD CONSTRAINT topic_post_days_topic_seed_queries_id_fkey FOREIGN KEY (topic_seed_queries_id) REFERENCES public.topic_seed_queries(topic_seed_queries_id) ON DELETE CASCADE;


--
-- Name: topic_post_urls topic_post_urls_topic_posts_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_post_urls
    ADD CONSTRAINT topic_post_urls_topic_posts_id_fkey FOREIGN KEY (topic_posts_id) REFERENCES public.topic_posts(topic_posts_id) ON DELETE CASCADE;


--
-- Name: topic_posts topic_posts_topic_post_days_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_posts
    ADD CONSTRAINT topic_posts_topic_post_days_id_fkey FOREIGN KEY (topic_post_days_id) REFERENCES public.topic_post_days(topic_post_days_id) ON DELETE CASCADE;


--
-- Name: topic_query_story_searches_imported_stories_map topic_query_story_searches_imported_stories_map_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_query_story_searches_imported_stories_map
    ADD CONSTRAINT topic_query_story_searches_imported_stories_map_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: topic_query_story_searches_imported_stories_map topic_query_story_searches_imported_stories_map_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_query_story_searches_imported_stories_map
    ADD CONSTRAINT topic_query_story_searches_imported_stories_map_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: topic_seed_queries topic_seed_queries_platform_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_seed_queries
    ADD CONSTRAINT topic_seed_queries_platform_fkey FOREIGN KEY (platform) REFERENCES public.topic_platforms(name);


--
-- Name: topic_seed_queries topic_seed_queries_source_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_seed_queries
    ADD CONSTRAINT topic_seed_queries_source_fkey FOREIGN KEY (source) REFERENCES public.topic_sources(name);


--
-- Name: topic_seed_queries topic_seed_queries_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_seed_queries
    ADD CONSTRAINT topic_seed_queries_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: topic_seed_urls topic_seed_urls_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_seed_urls
    ADD CONSTRAINT topic_seed_urls_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: topic_seed_urls topic_seed_urls_topic_post_urls_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_seed_urls
    ADD CONSTRAINT topic_seed_urls_topic_post_urls_id_fkey FOREIGN KEY (topic_post_urls_id) REFERENCES public.topic_post_urls(topic_post_urls_id) ON DELETE CASCADE;


--
-- Name: topic_seed_urls topic_seed_urls_topic_seed_queries_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_seed_urls
    ADD CONSTRAINT topic_seed_urls_topic_seed_queries_id_fkey FOREIGN KEY (topic_seed_queries_id) REFERENCES public.topic_seed_queries(topic_seed_queries_id) ON DELETE CASCADE;


--
-- Name: topic_seed_urls topic_seed_urls_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_seed_urls
    ADD CONSTRAINT topic_seed_urls_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: topic_spider_metrics topic_spider_metrics_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_spider_metrics
    ADD CONSTRAINT topic_spider_metrics_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: topic_stories topic_stories_stories_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_stories
    ADD CONSTRAINT topic_stories_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: topic_stories topic_stories_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topic_stories
    ADD CONSTRAINT topic_stories_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: topics_media_map topics_media_map_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topics_media_map
    ADD CONSTRAINT topics_media_map_media_id_fkey FOREIGN KEY (media_id) REFERENCES public.media(media_id) ON DELETE CASCADE;


--
-- Name: topics_media_map topics_media_map_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topics_media_map
    ADD CONSTRAINT topics_media_map_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: topics_media_tags_map topics_media_tags_map_tags_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topics_media_tags_map
    ADD CONSTRAINT topics_media_tags_map_tags_id_fkey FOREIGN KEY (tags_id) REFERENCES public.tags(tags_id) ON DELETE CASCADE;


--
-- Name: topics_media_tags_map topics_media_tags_map_topics_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topics_media_tags_map
    ADD CONSTRAINT topics_media_tags_map_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: topics topics_media_type_tag_sets_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topics
    ADD CONSTRAINT topics_media_type_tag_sets_id_fkey FOREIGN KEY (media_type_tag_sets_id) REFERENCES public.tag_sets(tag_sets_id);


--
-- Name: topics topics_mode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topics
    ADD CONSTRAINT topics_mode_fkey FOREIGN KEY (mode) REFERENCES public.topic_modes(name);


--
-- Name: topics topics_platform_fkey; Type: FK CONSTRAINT; Schema: public; Owner: mediacloud
--

ALTER TABLE ONLY public.topics
    ADD CONSTRAINT topics_platform_fkey FOREIGN KEY (platform) REFERENCES public.topic_platforms(name);


--
-- Name: live_stories live_stories_stories_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.live_stories
    ADD CONSTRAINT live_stories_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES public.stories(stories_id) ON DELETE CASCADE;


--
-- Name: live_stories live_stories_topic_stories_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.live_stories
    ADD CONSTRAINT live_stories_topic_stories_id_fkey FOREIGN KEY (topic_stories_id) REFERENCES public.topic_stories(topic_stories_id) ON DELETE CASCADE;


--
-- Name: live_stories live_stories_topics_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.live_stories
    ADD CONSTRAINT live_stories_topics_id_fkey FOREIGN KEY (topics_id) REFERENCES public.topics(topics_id) ON DELETE CASCADE;


--
-- Name: media media_snapshots_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.media
    ADD CONSTRAINT media_snapshots_id_fkey FOREIGN KEY (snapshots_id) REFERENCES public.snapshots(snapshots_id) ON DELETE CASCADE;


--
-- Name: media_tags_map media_tags_map_snapshots_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.media_tags_map
    ADD CONSTRAINT media_tags_map_snapshots_id_fkey FOREIGN KEY (snapshots_id) REFERENCES public.snapshots(snapshots_id) ON DELETE CASCADE;


--
-- Name: medium_link_counts medium_link_counts_timespans_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.medium_link_counts
    ADD CONSTRAINT medium_link_counts_timespans_id_fkey FOREIGN KEY (timespans_id) REFERENCES public.timespans(timespans_id) ON DELETE CASCADE;


--
-- Name: medium_links medium_links_timespans_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.medium_links
    ADD CONSTRAINT medium_links_timespans_id_fkey FOREIGN KEY (timespans_id) REFERENCES public.timespans(timespans_id) ON DELETE CASCADE;


--
-- Name: stories stories_snapshots_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.stories
    ADD CONSTRAINT stories_snapshots_id_fkey FOREIGN KEY (snapshots_id) REFERENCES public.snapshots(snapshots_id) ON DELETE CASCADE;


--
-- Name: stories_tags_map stories_tags_map_snapshots_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.stories_tags_map
    ADD CONSTRAINT stories_tags_map_snapshots_id_fkey FOREIGN KEY (snapshots_id) REFERENCES public.snapshots(snapshots_id) ON DELETE CASCADE;


--
-- Name: story_link_counts story_link_counts_timespans_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.story_link_counts
    ADD CONSTRAINT story_link_counts_timespans_id_fkey FOREIGN KEY (timespans_id) REFERENCES public.timespans(timespans_id) ON DELETE CASCADE;


--
-- Name: story_links story_links_timespans_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.story_links
    ADD CONSTRAINT story_links_timespans_id_fkey FOREIGN KEY (timespans_id) REFERENCES public.timespans(timespans_id) ON DELETE CASCADE;


--
-- Name: timespan_posts timespan_posts_timespans_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.timespan_posts
    ADD CONSTRAINT timespan_posts_timespans_id_fkey FOREIGN KEY (timespans_id) REFERENCES public.timespans(timespans_id) ON DELETE CASCADE;


--
-- Name: timespan_posts timespan_posts_topic_posts_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.timespan_posts
    ADD CONSTRAINT timespan_posts_topic_posts_id_fkey FOREIGN KEY (topic_posts_id) REFERENCES public.topic_posts(topic_posts_id) ON DELETE CASCADE;


--
-- Name: topic_links_cross_media topic_links_cross_media_snapshots_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.topic_links_cross_media
    ADD CONSTRAINT topic_links_cross_media_snapshots_id_fkey FOREIGN KEY (snapshots_id) REFERENCES public.snapshots(snapshots_id) ON DELETE CASCADE;


--
-- Name: topic_media_codes topic_media_codes_snapshots_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.topic_media_codes
    ADD CONSTRAINT topic_media_codes_snapshots_id_fkey FOREIGN KEY (snapshots_id) REFERENCES public.snapshots(snapshots_id) ON DELETE CASCADE;


--
-- Name: topic_stories topic_stories_snapshots_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.topic_stories
    ADD CONSTRAINT topic_stories_snapshots_id_fkey FOREIGN KEY (snapshots_id) REFERENCES public.snapshots(snapshots_id) ON DELETE CASCADE;


--
-- Name: word2vec_models_data word2vec_models_data_object_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.word2vec_models_data
    ADD CONSTRAINT word2vec_models_data_object_id_fkey FOREIGN KEY (object_id) REFERENCES snap.word2vec_models(word2vec_models_id) ON DELETE CASCADE;


--
-- Name: word2vec_models word2vec_models_object_id_fkey; Type: FK CONSTRAINT; Schema: snap; Owner: mediacloud
--

ALTER TABLE ONLY snap.word2vec_models
    ADD CONSTRAINT word2vec_models_object_id_fkey FOREIGN KEY (object_id) REFERENCES public.snapshots(snapshots_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

