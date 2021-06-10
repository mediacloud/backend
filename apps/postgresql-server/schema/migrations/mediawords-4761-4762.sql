--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4761 and 4762.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4761, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4762, import this SQL file:
--
--     psql mediacloud < mediawords-4761-4762.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--


-- Kill all autovacuums before proceeding with DDL changes
SELECT pid
FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
WHERE backend_type = 'autovacuum worker'
  AND query ~ 'stories';


-- Get rid of a table which doesn't exist in production nor gets created via
-- migrations but is mentioned in mediawords.sql
DROP TABLE IF EXISTS topic_query_story_searches_imported_stories_map;



-- Rename "stories" to "stories_unpartitioned"
ALTER TABLE stories
    RENAME TO stories_unpartitioned;
-- Leave "stories_id" not renamed because triggers reference it directly
ALTER SEQUENCE stories_stories_id_seq
    RENAME TO stories_unpartitioned_stories_id_seq;
ALTER INDEX stories_pkey
    RENAME TO stories_unpartitioned_pkey;
ALTER INDEX stories_collect_date
    RENAME TO stories_unpartitioned_collect_date;
ALTER INDEX stories_guid
    RENAME TO stories_unpartitioned_guid;
ALTER INDEX stories_language
    RENAME TO stories_unpartitioned_language;
ALTER INDEX stories_md
    RENAME TO stories_unpartitioned_md;
ALTER INDEX stories_media_id
    RENAME TO stories_unpartitioned_media_id;
ALTER INDEX stories_normalized_title_hash
    RENAME TO stories_unpartitioned_normalized_title_hash;
ALTER INDEX stories_publish_date
    RENAME TO stories_unpartitioned_publish_date;
ALTER INDEX stories_publish_day
    RENAME TO stories_unpartitioned_publish_day;
ALTER INDEX stories_title_hash
    RENAME TO stories_unpartitioned_title_hash;
ALTER INDEX stories_url
    RENAME TO stories_unpartitioned_url;
ALTER TABLE stories_unpartitioned
    RENAME CONSTRAINT stories_media_id_fkey
    TO stories_unpartitioned_media_id_fkey;
ALTER TRIGGER stories_add_normalized_title
    ON stories_unpartitioned
    RENAME TO stories_unpartitioned_add_normalized_title;

-- These triggers will be recreated on a view and later moved to a
-- partitioned table
DROP TRIGGER stories_insert_solr_import_story
    ON stories_unpartitioned;
DROP TRIGGER stories_update_live_story
    ON stories_unpartitioned;


-- Drop foreign keys to an unpartitioned table because we'll be moving rows
-- from an unpartitioned table to the partitioned one; these are later to be
-- recreated
ALTER TABLE cliff_annotations
    DROP CONSTRAINT cliff_annotations_object_id_fkey;
ALTER TABLE downloads
    DROP CONSTRAINT downloads_stories_id_fkey;
ALTER TABLE snap.live_stories
    DROP CONSTRAINT live_stories_stories_id_fkey;
ALTER TABLE nytlabels_annotations
    DROP CONSTRAINT nytlabels_annotations_object_id_fkey;
ALTER TABLE processed_stories
    DROP CONSTRAINT processed_stories_stories_id_fkey;
ALTER TABLE retweeter_stories
    DROP CONSTRAINT retweeter_stories_stories_id_fkey;
ALTER TABLE scraped_stories
    DROP CONSTRAINT scraped_stories_stories_id_fkey;
ALTER TABLE solr_import_stories
    DROP CONSTRAINT solr_import_stories_stories_id_fkey;
ALTER TABLE solr_imported_stories
    DROP CONSTRAINT solr_imported_stories_stories_id_fkey;
ALTER TABLE stories_ap_syndicated
    DROP CONSTRAINT stories_ap_syndicated_stories_id_fkey;
ALTER TABLE story_enclosures
    DROP CONSTRAINT story_enclosures_stories_id_fkey;
ALTER TABLE story_statistics
    DROP CONSTRAINT story_statistics_stories_id_fkey;
ALTER TABLE story_statistics_twitter
    DROP CONSTRAINT story_statistics_twitter_stories_id_fkey;
ALTER TABLE story_urls
    DROP CONSTRAINT story_urls_stories_id_fkey;
ALTER TABLE topic_fetch_urls
    DROP CONSTRAINT topic_fetch_urls_stories_id_fkey;

-- Some constraints might not be renamed in migrations
ALTER TABLE topic_links
    DROP CONSTRAINT IF EXISTS topic_links_ref_stories_id_fkey;
ALTER TABLE topic_links
    DROP CONSTRAINT IF EXISTS controversy_links_ref_stories_id_fkey;

ALTER TABLE topic_merged_stories_map
    DROP CONSTRAINT IF EXISTS topic_merged_stories_map_source_stories_id_fkey;
ALTER TABLE topic_merged_stories_map
    DROP CONSTRAINT IF EXISTS controversy_merged_stories_map_source_stories_id_fkey;

ALTER TABLE topic_merged_stories_map
    DROP CONSTRAINT IF EXISTS topic_merged_stories_map_target_stories_id_fkey;
ALTER TABLE topic_merged_stories_map
    DROP CONSTRAINT IF EXISTS controversy_merged_stories_map_target_stories_id_fkey;

ALTER TABLE topic_seed_urls
    DROP CONSTRAINT IF EXISTS topic_seed_urls_stories_id_fkey;
ALTER TABLE topic_seed_urls
    DROP CONSTRAINT IF EXISTS controversy_seed_urls_stories_id_fkey;

ALTER TABLE topic_stories
    DROP CONSTRAINT IF EXISTS topic_stories_stories_id_fkey;
ALTER TABLE topic_stories
    DROP CONSTRAINT IF EXISTS controversy_stories_stories_id_fkey;

DO $$
DECLARE

    tables CURSOR FOR
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public' AND (
            tablename LIKE 'feeds_stories_map_p_%' OR
            tablename LIKE 'stories_tags_map_p_%' OR
            tablename LIKE 'story_sentences_p_%'
        )

        ORDER BY tablename;

BEGIN
    FOR table_record IN tables LOOP

        EXECUTE '
            ALTER TABLE ' || table_record.tablename || '
                DROP CONSTRAINT ' || table_record.tablename || '_stories_id_fkey
        ';

    END LOOP;
END
$$;



-- Create partitioned table

-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE stories_partitioned (
    stories_id              BIGSERIAL   PRIMARY KEY,
    media_id                INT         NOT NULL
                                            REFERENCES media (media_id) MATCH FULL
                                            ON DELETE CASCADE,
    url                     TEXT        NOT NULL,
    guid                    TEXT        NOT NULL,
    title                   TEXT        NOT NULL,
    normalized_title_hash   UUID        NOT NULL,
    description             TEXT        NULL,
    publish_date            TIMESTAMP   NULL,
    collect_date            TIMESTAMP   NOT NULL DEFAULT NOW(),
    full_text_rss           BOOLEAN     NOT NULL DEFAULT 'f',

    -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
    language                VARCHAR(3)  NULL
) PARTITION BY RANGE (stories_id);


-- "language" column will always be short so no need to TOAST it
ALTER TABLE stories_partitioned
    ALTER COLUMN language
    SET STORAGE PLAIN;


CREATE INDEX stories_partitioned_media_id
    ON stories_partitioned (media_id);

-- This used to be an UNIQUE index but we can't enforce index uniqueness across
-- partitions so it's not a unique index, and uniqueness is enforced by an
-- AFTER INSERT trigger instead
CREATE INDEX stories_partitioned_guid
    ON stories_partitioned (guid, media_id);

CREATE INDEX stories_partitioned_url
    ON stories_partitioned USING HASH (url);

CREATE INDEX stories_partitioned_publish_date
    ON stories_partitioned (publish_date);

CREATE INDEX stories_partitioned_collect_date
    ON stories_partitioned (collect_date);

CREATE INDEX stories_partitioned_media_id_publish_day
    ON stories_partitioned (media_id, date_trunc('day'::text, publish_date));

CREATE INDEX stories_partitioned_language
    ON stories_partitioned USING HASH (language);

CREATE INDEX stories_partitioned_title
    ON stories_partitioned USING HASH (title);

-- Crawler currently queries for md5(title) so we have to keep this extra index
-- here while migrating rows from an unpartitioned table
CREATE INDEX stories_partitioned_title_md5
    ON stories_partitioned USING HASH (md5(title));

CREATE INDEX stories_partitioned_publish_day
    ON stories_partitioned (date_trunc('day'::text, publish_date));

CREATE INDEX stories_partitioned_normalized_title_hash
    ON stories_partitioned (media_id, normalized_title_hash);


CREATE TRIGGER stories_partitioned_add_normalized_title
    BEFORE INSERT OR UPDATE ON stories_partitioned
    FOR EACH ROW
    EXECUTE procedure add_normalized_title_hash();


-- Make the partitioned table continue the sequence where the unpartitioned
-- table left off
SELECT setval(
    pg_get_serial_sequence('stories_partitioned', 'stories_id'),
    (SELECT MAX(stories_id) FROM stories_unpartitioned)
);



-- View that joins the unpartitioned and partitioned tables while the data is
-- being migrated
CREATE OR REPLACE VIEW stories AS

    SELECT *
    FROM (
        SELECT
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
        FROM stories_partitioned

        UNION ALL

        SELECT
            stories_id::bigint,
            media_id,
            url::text,
            guid::text,
            title,
            normalized_title_hash,
            description,
            publish_date,
            collect_date,
            full_text_rss,
            language
        FROM stories_unpartitioned

    ) AS s;


-- Make RETURNING work with an updatable view
-- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
ALTER VIEW stories
    ALTER COLUMN stories_id
    SET DEFAULT nextval(pg_get_serial_sequence('stories_partitioned', 'stories_id')) + 1;


-- Trigger that implements INSERT / UPDATE / DELETE behavior on "stories" view
CREATE OR REPLACE FUNCTION stories_view_insert_update_delete() RETURNS trigger AS $$

BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- All new INSERTs go to partitioned table only

        INSERT INTO stories_partitioned (
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
        )
        SELECT
            NEW.stories_id,
            NEW.media_id,
            NEW.url,
            NEW.guid,
            NEW.title,
            NEW.normalized_title_hash,
            NEW.description,
            NEW.publish_date,

            -- Imitate default value
            COALESCE(NEW.collect_date, NOW()),
            COALESCE(NEW.full_text_rss, 'f'),

            NEW.language;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        -- UPDATE on both tables

        UPDATE stories_partitioned
            SET stories_id = NEW.stories_id,
                media_id = NEW.media_id,
                url = NEW.url,
                guid = NEW.guid,
                title = NEW.title,
                normalized_title_hash = NEW.normalized_title_hash,
                description = NEW.description,
                publish_date = NEW.publish_date,
                collect_date = COALESCE(NEW.collect_date, NOW()),
                full_text_rss = COALESCE(NEW.full_text_rss, 'f'),
                language = NEW.language
            WHERE stories_id = OLD.stories_id;

        UPDATE stories_unpartitioned
            SET stories_id = NEW.stories_id,
                media_id = NEW.media_id,
                url = NEW.url,
                guid = NEW.guid,
                title = NEW.title,
                normalized_title_hash = NEW.normalized_title_hash,
                description = NEW.description,
                publish_date = NEW.publish_date,
                collect_date = COALESCE(NEW.collect_date, NOW()),
                full_text_rss = COALESCE(NEW.full_text_rss, 'f'),
                language = NEW.language
            WHERE stories_id = OLD.stories_id;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        -- DELETE from both tables

        DELETE FROM stories_partitioned WHERE stories_id = OLD.stories_id;
        DELETE FROM stories_unpartitioned WHERE stories_id = OLD.stories_id;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER stories_view_insert_update_delete_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE ON stories
    FOR EACH ROW EXECUTE PROCEDURE stories_view_insert_update_delete();



-- Adding triggers to the view and not to the partitioned table because we
-- don't want them to fire while we're moving rows
CREATE TRIGGER stories_insert_solr_import_story
    AFTER INSERT OR UPDATE OR DELETE ON stories
    FOR EACH ROW
    EXECUTE PROCEDURE insert_solr_import_story();

CREATE TRIGGER stories_update_live_story
    AFTER UPDATE ON stories
    FOR EACH ROW
    EXECUTE PROCEDURE update_live_story();


-- Update the function to accept some extra arguments for declarative partitioning
DROP FUNCTION IF EXISTS partition_by_stories_id_create_partitions(TEXT);
CREATE OR REPLACE FUNCTION partition_by_stories_id_create_partitions(

    -- Base table name for the partition to be created, e.g. "story_sentences_p"
    base_table_name TEXT,

    -- If true, an inheritance-based partitioning will be used; if false,
    -- declarative partitioning will be used
    inheritance_partitioning BOOLEAN DEFAULT 't',

    -- If true, a foreign key to "stories" will get created; if false,
    -- a foreign key to "stories" won't get created; works only with
    -- inheritance-based partitioning because with declarative partitioning one
    -- should add a foreign key on a base table instead
    fk_stories BOOLEAN DEFAULT 't'

) RETURNS SETOF TEXT AS
$$
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

    -- Primary key column, e.g. "story_sentences_p_id"
    primary_key_column TEXT;

    -- Foreign key to "stories" clause
    fk_clause TEXT;

BEGIN

    IF inheritance_partitioning = 'f' AND fk_stories = 't' THEN
        RAISE EXCEPTION 'Function does not support foreign keys from individual declarative partitions.';
    END IF;

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

            IF inheritance_partitioning THEN

                IF fk_stories THEN
                    primary_key_column := base_table_name || '_id';
                    fk_clause := '
                        -- Foreign key to stories.stories_id
                        , CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id_fkey
                            FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL ON DELETE CASCADE
                    ';
                ELSE
                    primary_key_column := 'stories_id';
                    fk_clause := '';
                END IF;

                EXECUTE '
                    CREATE TABLE ' || target_table_name || ' (

                        PRIMARY KEY (' || primary_key_column || '),

                        -- Partition by stories_id
                        CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id CHECK (
                            stories_id >= ''' || stories_id_start || '''
                        AND stories_id <  ''' || stories_id_end   || ''')

                        ' || fk_clause || '

                    ) INHERITS (' || base_table_name || ');
                ';

            ELSE

                EXECUTE '
                    CREATE TABLE ' || target_table_name || '
                        PARTITION OF ' || base_table_name || '
                        FOR VALUES FROM (' || stories_id_start || ') TO (' || stories_id_end || ');
                ';

            END IF;

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
$$
LANGUAGE plpgsql;


-- Update create_missing_partitions() for it to create partitions for "stories_partitioned" too
CREATE OR REPLACE FUNCTION create_missing_partitions()
RETURNS VOID AS
$$
BEGIN

    -- We have to create "downloads" partitions before "download_texts" ones
    -- because "download_texts" will have a foreign key reference to
    -- "downloads_success_content"

    RAISE NOTICE 'Creating partitions in "stories_partitioned" table...';
    PERFORM partition_by_stories_id_create_partitions(
        base_table_name := 'stories_partitioned',
        inheritance_partitioning := false,
        fk_stories := false
    );

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
$$
LANGUAGE plpgsql;


-- Create initial "stories" partitions
SELECT create_missing_partitions();


-- Migrate a huge chunk of stories to the partitioned table
--
-- This should help upgrade the dev environments by copying *all* stories in
-- small test datasets while not blocking the migration in production due to a
-- small chunk size.
WITH rows_to_move AS (
    DELETE FROM stories_unpartitioned
    WHERE stories_id IN (
        SELECT stories_id
        FROM stories_unpartitioned
        ORDER BY stories_id
        LIMIT 50000
    )
    RETURNING stories_unpartitioned.*
)
-- INSERT into view to hit the partitioning trigger
INSERT INTO stories_partitioned (
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
)
    SELECT
        stories_id::bigint,
        media_id,
        url::text,
        guid::text,
        title,
        normalized_title_hash,
        description,
        publish_date,
        collect_date,
        full_text_rss,
        language
    FROM rows_to_move;



-- Given that the unique index on (guid, media_id) is going to be valid only
-- per-partition, add a trigger that will check for uniqueness after each INSERT.
-- We add the trigger after migrating a chunk of stories first to increase
-- performance of the copy.
CREATE OR REPLACE FUNCTION stories_partitioned_ensure_unique_guid() RETURNS trigger AS $$

DECLARE
    guid_row_count INT;

BEGIN

    SELECT COUNT(*)
    FROM stories
    INTO guid_row_count
    WHERE media_id = NEW.media_id
      AND guid = NEW.guid;

    IF guid_row_count > 1 THEN

        -- The exception has to mention 'unique constraint "stories_guid'
        -- because add_story() is expecting it
        RAISE EXCEPTION 'Duplicate (media_id, guid); unique constraint "stories_guid"';

    END IF;

    -- "INSERT ... RETURNING *" kind of works with this trigger, i.e. one can
    -- get the INSERTed "stories_id" but not, for example,
    -- "normalized_title_hash" as it's a column computed by a AFTER trigger
    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER stories_partitioned_ensure_unique_guid
    AFTER INSERT ON stories_partitioned
    FOR EACH ROW
    EXECUTE PROCEDURE stories_partitioned_ensure_unique_guid();


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4762;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
