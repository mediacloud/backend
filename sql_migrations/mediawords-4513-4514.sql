--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4513 and 4514.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4513, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4514, import this SQL file:
--
--     psql mediacloud < mediawords-4513-4514.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


--
-- Print out a diff between "feeds" and "feeds_from_yesterday"
--
CREATE OR REPLACE FUNCTION rescraping_changes() RETURNS VOID AS
$$
DECLARE
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
                    SELECT feeds_id, media_id, feed_type, feed_status, url FROM feeds_from_yesterday
                    EXCEPT
                    SELECT feeds_id, media_id, feed_type, feed_status, url FROM feeds
                ) UNION ALL (
                    SELECT feeds_id, media_id, feed_type, feed_status, url FROM feeds
                    EXCEPT
                    SELECT feeds_id, media_id, feed_type, feed_status, url FROM feeds_from_yesterday
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
               feeds_before.feed_type AS before_feed_type,
               feeds_before.feed_status AS before_feed_status,

               feeds_after.name AS after_name,
               feeds_after.url AS after_url,
               feeds_after.feed_type AS after_feed_type,
               feeds_after.feed_status AS after_feed_status

        FROM feeds_from_yesterday AS feeds_before
            INNER JOIN feeds AS feeds_after ON (
                feeds_before.feeds_id = feeds_after.feeds_id
                AND (
                    -- Don't compare "name" because it's insignificant
                    feeds_before.url != feeds_after.url
                 OR feeds_before.feed_type != feeds_after.feed_type
                 OR feeds_before.feed_status != feeds_after.feed_status
                )
            )

        WHERE feeds_before.media_id IN (
            SELECT media_id
            FROM rescraping_changes_media
        );

    -- Print out changes
    RAISE NOTICE 'Changes between "feeds" and "feeds_from_yesterday":';
    RAISE NOTICE '';

    FOR r_media IN
        SELECT *
        FROM rescraping_changes_media
        ORDER BY media_id
    LOOP
        RAISE NOTICE 'MODIFIED media: media_id=%, name="%", url="%"',
            r_media.media_id,
            r_media.name,
            r_media.url;

        FOR r_feed IN
            SELECT *
            FROM rescraping_changes_feeds_added
            WHERE media_id = r_media.media_id
        LOOP
            RAISE NOTICE '    ADDED feed: feeds_id=%, feed_type=%, feed_status=%, name="%", url="%"',
                r_feed.feeds_id,
                r_feed.feed_type,
                r_feed.feed_status,
                r_feed.name,
                r_feed.url;
        END LOOP;

        -- Feeds shouldn't get deleted but we're checking anyways
        FOR r_feed IN
            SELECT *
            FROM rescraping_changes_feeds_deleted
            WHERE media_id = r_media.media_id
        LOOP
            RAISE NOTICE '    DELETED feed: feeds_id=%, feed_type=%, feed_status=%, name="%", url="%"',
                r_feed.feeds_id,
                r_feed.feed_type,
                r_feed.feed_status,
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
            RAISE NOTICE '        BEFORE: feed_type=%, feed_status=%, name="%", url="%"',
                r_feed.before_feed_type,
                r_feed.before_feed_status,
                r_feed.before_name,
                r_feed.before_url;
            RAISE NOTICE '        AFTER:  feed_type=%, feed_status=%, name="%", url="%"',
                r_feed.after_feed_type,
                r_feed.after_feed_status,
                r_feed.after_name,
                r_feed.after_url;
        END LOOP;

        RAISE NOTICE '';

    END LOOP;

END;
$$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4514;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

