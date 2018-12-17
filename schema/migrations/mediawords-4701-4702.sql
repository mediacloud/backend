--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4701 and 4702.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4701, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4702, import this SQL file:
--
--     psql mediacloud < mediawords-4701-4702.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- It's just some cache in it so we can just drop and recreate the table
DROP TABLE cached_extractor_results;

CREATE UNLOGGED TABLE cache.extractor_results_cache (
    extractor_results_cache_id  SERIAL  PRIMARY KEY,
    extracted_html              TEXT    NULL,
    extracted_text              TEXT    NULL,
    downloads_id                BIGINT  NOT NULL,

    -- Will be used to purge old cache objects;
    -- don't forget to update cache.purge_object_caches()
    db_row_last_updated         TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX extractor_results_cache_downloads_id
    ON cache.extractor_results_cache (downloads_id);
CREATE INDEX extractor_results_cache_db_row_last_updated
    ON cache.extractor_results_cache (db_row_last_updated);

ALTER TABLE cache.extractor_results_cache
    ALTER COLUMN extracted_html SET STORAGE EXTERNAL,
    ALTER COLUMN extracted_text SET STORAGE EXTERNAL;

CREATE TRIGGER extractor_results_cache_db_row_last_updated_trigger
    BEFORE INSERT OR UPDATE ON cache.extractor_results_cache
    FOR EACH ROW EXECUTE PROCEDURE cache.update_cache_db_row_last_updated();

CREATE TRIGGER extractor_results_cache_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON cache.extractor_results_cache
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('downloads_id');


-- Recreate helper that purges caches
CREATE OR REPLACE FUNCTION cache.purge_object_caches()
RETURNS VOID AS
$$
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
$$
LANGUAGE plpgsql;


-- Recreate trigger on "downloads" view
CREATE OR REPLACE FUNCTION downloads_view_insert_update_delete() RETURNS trigger AS $$
BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- New rows go into the partitioned table only
        INSERT INTO downloads_p (
            downloads_p_id,
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
        ) SELECT
            NEW.downloads_id,
            NEW.feeds_id,
            NEW.stories_id,
            NEW.parent,
            NEW.url,
            NEW.host,
            COALESCE(NEW.download_time, NOW()),
            NEW.type,
            NEW.state,
            NEW.path,
            NEW.error_message,
            NEW.priority,
            NEW.sequence,
            COALESCE(NEW.extracted, 'f');

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        -- Update both tables as one of them will have the row
        UPDATE downloads_np SET
            downloads_np_id = NEW.downloads_id,
            feeds_id = NEW.feeds_id,
            stories_id = NEW.stories_id,
            parent = NEW.parent,
            url = NEW.url,
            host = NEW.host,
            download_time = NEW.download_time,
            type = NEW.type::text::download_np_type,
            state = NEW.state::text::download_np_state,
            path = NEW.path,
            error_message = NEW.error_message,
            priority = NEW.priority,
            sequence = NEW.sequence,
            extracted = NEW.extracted
        WHERE downloads_np_id = OLD.downloads_id;

        UPDATE downloads_p SET
            downloads_p_id = NEW.downloads_id,
            feeds_id = NEW.feeds_id,
            stories_id = NEW.stories_id,
            parent = NEW.parent,
            url = NEW.url,
            host = NEW.host,
            download_time = NEW.download_time,
            type = NEW.type,
            state = NEW.state,
            path = NEW.path,
            error_message = NEW.error_message,
            priority = NEW.priority,
            sequence = NEW.sequence,
            extracted = NEW.extracted
        WHERE downloads_p_id = OLD.downloads_id;

        -- Update record in tables that reference "downloads" with a given ID
        UPDATE downloads_np
        SET parent = NEW.downloads_id
        WHERE parent = OLD.downloads_id;

        UPDATE downloads_p
        SET parent = NEW.downloads_id
        WHERE parent = OLD.downloads_id;

        UPDATE raw_downloads
        SET object_id = NEW.downloads_id
        WHERE object_id = OLD.downloads_id;

        UPDATE download_texts
        SET downloads_id = NEW.downloads_id
        WHERE downloads_id = OLD.downloads_id;

        UPDATE cache.extractor_results_cache
        SET downloads_id = NEW.downloads_id
        WHERE downloads_id = OLD.downloads_id;

        UPDATE cache.s3_raw_downloads_cache
        SET object_id = NEW.downloads_id
        WHERE object_id = OLD.downloads_id;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        -- Delete from both tables as one of them will have the row
        DELETE FROM downloads_np
            WHERE downloads_np_id = OLD.downloads_id;

        DELETE FROM downloads_p
            WHERE downloads_p_id = OLD.downloads_id;

        -- Update / delete record in tables that reference "downloads" with a
        -- given ID
        UPDATE downloads_np
        SET parent = NULL
        WHERE parent = OLD.downloads_id;

        UPDATE downloads_p
        SET parent = NULL
        WHERE parent = OLD.downloads_id;

        DELETE FROM raw_downloads
        WHERE object_id = OLD.downloads_id;

        DELETE FROM download_texts
        WHERE downloads_id = OLD.downloads_id;

        DELETE FROM cache.extractor_results_cache
        WHERE downloads_id = OLD.downloads_id;

        DELETE FROM cache.s3_raw_downloads_cache
        WHERE object_id = OLD.downloads_id;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4702;
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
