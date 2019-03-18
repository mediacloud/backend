--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4712 and 4713.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4712, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4713, import this SQL file:
--
--     psql mediacloud < mediawords-4712-4713.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Kill all autovacuums before proceeding with DDL changes
SELECT pid
FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
WHERE backend_type = 'autovacuum worker'
  AND query ~ 'download_texts';


-- To be recreated later
DROP VIEW daily_stats;
DROP VIEW downloads_media;
DROP VIEW downloads_non_media;
DROP VIEW downloads_to_be_extracted;
DROP VIEW downloads_with_error_in_past_day;
DROP VIEW downloads_in_past_day;


DROP FUNCTION move_chunk_of_nonpartitioned_downloads_to_partitions(start_downloads_id INT, end_downloads_id INT);


DROP VIEW downloads;


DROP FUNCTION downloads_view_insert_update_delete();


TRUNCATE downloads_np_with_no_matching_story;
DROP TABLE downloads_np_with_no_matching_story;


TRUNCATE downloads_np;
DROP TABLE downloads_np;


DROP FUNCTION download_np_type_to_download_p_type(p_type download_np_type);
DROP FUNCTION download_np_state_to_download_p_state(p_state download_np_state);

DROP FUNCTION to_bigint(p_integer INT);


DROP TYPE download_np_state;
DROP TYPE download_np_type;


ALTER TYPE download_p_state
    RENAME TO download_state;

ALTER TYPE download_p_type
    RENAME TO download_type;


ALTER TABLE downloads_p
    RENAME TO downloads;

ALTER TABLE downloads
    RENAME COLUMN downloads_p_id TO downloads_id;

ALTER TABLE downloads
    RENAME CONSTRAINT downloads_p_feeds_id_fkey
    TO downloads_feeds_id_fkey;

ALTER TABLE downloads
    RENAME CONSTRAINT downloads_p_stories_id_fkey
    TO downloads_stories_id_fkey;

ALTER INDEX downloads_p_pkey
    RENAME TO downloads_pkey;

ALTER INDEX downloads_p_feed_download_time
    RENAME TO downloads_feed_download_time;

ALTER INDEX downloads_p_parent
    RENAME TO downloads_parent;

ALTER INDEX downloads_p_story
    RENAME TO downloads_story;

ALTER INDEX downloads_time_p
    RENAME TO downloads_time;

ALTER SEQUENCE downloads_p_downloads_p_id_seq
    RENAME TO downloads_downloads_id_seq;


-- UPDATE / DELETE "downloads" trigger that enforces foreign keys on referencing tables
CREATE FUNCTION cascade_ref_downloads_trigger() RETURNS trigger AS $$
BEGIN

    IF (TG_OP = 'UPDATE') THEN

        UPDATE downloads
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

        UPDATE downloads
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


DO $$
DECLARE
    tables CURSOR FOR
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename LIKE 'downloads_p_%'
        ORDER BY tablename;
    new_table_name TEXT;
BEGIN
    FOR table_record IN tables LOOP

        SELECT REPLACE(table_record.tablename, 'downloads_p_', 'downloads_') INTO new_table_name;

        EXECUTE '
            ALTER TABLE ' || table_record.tablename || '
                RENAME TO ' || new_table_name || ';';

        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_pkey
                RENAME TO ' || new_table_name || '_pkey;';
        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_download_time_idx
                RENAME TO ' || new_table_name || '_download_time_idx;';
        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_feeds_id_download_time_idx
                RENAME TO ' || new_table_name || '_feeds_id_download_time_idx;';
        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_parent_idx
                RENAME TO ' || new_table_name || '_parent_idx;';
        EXECUTE '
            ALTER INDEX ' || table_record.tablename || '_stories_id_idx
                RENAME TO ' || new_table_name || '_stories_id_idx;';

        EXECUTE '
            ALTER TABLE ' || new_table_name || '
                RENAME CONSTRAINT downloads_p_feeds_id_fkey
                TO downloads_feeds_id_fkey';
        EXECUTE '
            ALTER TABLE ' || new_table_name || '
                RENAME CONSTRAINT downloads_p_stories_id_fkey
                TO downloads_stories_id_fkey';

        IF new_table_name = 'downloads_success' THEN
            EXECUTE '
                ALTER TABLE ' || new_table_name || '
                    RENAME CONSTRAINT downloads_p_success_path_not_null
                    TO downloads_success_path_not_null';
        END IF;

        IF new_table_name = 'downloads_success_content' THEN
            EXECUTE '
                ALTER INDEX ' || table_record.tablename || '_extracted
                    RENAME TO ' || new_table_name || '_extracted;';

            EXECUTE '
                ALTER TABLE ' || new_table_name || '
                    RENAME CONSTRAINT downloads_p_success_content_stories_id_not_null
                    TO downloads_success_content_stories_id_not_null';
        END IF;

        IF new_table_name LIKE 'downloads_success_content_%' THEN
            EXECUTE '
                ALTER INDEX ' || table_record.tablename || '_extracted_idx
                    RENAME TO ' || new_table_name || '_extracted_idx;';

        END IF;

        IF new_table_name = 'downloads_success_feed' THEN
            EXECUTE '
                ALTER TABLE ' || new_table_name || '
                    RENAME CONSTRAINT downloads_p_success_feed_stories_id_null
                    TO downloads_success_feed_stories_id_null';
        END IF;

        IF new_table_name SIMILAR TO 'downloads_(error|feed_error|fetching|pending|success_content_%|success_feed_%)' THEN

            EXECUTE '
                ALTER TRIGGER ' || table_record.tablename || '_test_referenced_download_trigger
                    ON ' || new_table_name || '
                    RENAME TO ' || new_table_name || '_test_referenced_download_trigger';

            EXECUTE '
                CREATE TRIGGER ' || new_table_name || '_cascade_ref_downloads_trigger
                    AFTER UPDATE OR DELETE ON ' || new_table_name || '
                    FOR EACH ROW
                    EXECUTE PROCEDURE cascade_ref_downloads_trigger();
            ';

        END IF;

    END LOOP;
END
$$;


CREATE VIEW downloads_non_media AS
    SELECT d.*
    FROM downloads AS d
    WHERE d.feeds_id IS NULL;

CREATE VIEW downloads_to_be_extracted AS
    SELECT *
    FROM downloads
    WHERE extracted = 'f'
      AND state = 'success'
      AND type = 'content';

CREATE VIEW downloads_in_past_day AS
    SELECT *
    FROM downloads
    WHERE download_time > NOW() - interval '1 day';

CREATE VIEW downloads_with_error_in_past_day AS
    SELECT *
    FROM downloads_in_past_day
    WHERE state = 'error';


CREATE VIEW daily_stats AS
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

CREATE VIEW downloads_media AS
    SELECT
        d.*,
        f.media_id AS _media_id
    FROM
        downloads AS d,
        feeds AS f
    WHERE d.feeds_id = f.feeds_id;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4713;
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
