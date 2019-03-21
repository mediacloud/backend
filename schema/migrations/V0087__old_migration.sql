


--
-- Schema to hold object caches
--

CREATE SCHEMA cache;

CREATE OR REPLACE LANGUAGE plpgsql;


-- Upsert helper to INSERT or UPDATE an object to object cache
CREATE OR REPLACE FUNCTION cache.upsert_cache_object (
    param_table_name VARCHAR,
    param_object_id BIGINT,
    param_raw_data BYTEA
) RETURNS VOID AS
$$
DECLARE
    _cache_object_found INT;
BEGIN

    -- Unsure how to pass BYTEA objects as EXECUTE parameters
    CREATE TEMPORARY TABLE cache_object_to_upsert (
        object_id BIGINT NOT NULL,
        raw_data BYTEA NOT NULL
    ) ON COMMIT DROP;
    INSERT INTO cache_object_to_upsert (object_id, raw_data)
    VALUES (param_object_id, param_raw_data);

    LOOP
        -- Try UPDATing
        EXECUTE '
            UPDATE ' || param_table_name || '
            SET raw_data = cache_object_to_upsert.raw_data
            FROM (
                SELECT object_id, raw_data
                FROM cache_object_to_upsert
            ) AS cache_object_to_upsert
            WHERE ' || param_table_name || '.object_id = cache_object_to_upsert.object_id
            RETURNING *
        ' INTO _cache_object_found;

        IF _cache_object_found IS NOT NULL THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN

            EXECUTE '
                INSERT INTO ' || param_table_name || ' (object_id, raw_data)
                SELECT object_id, raw_data FROM cache_object_to_upsert
            ';

            RETURN;

        EXCEPTION WHEN UNIQUE_VIOLATION THEN
            -- If someone else INSERTs the same key concurrently,
            -- we will get a unique-key failure. In that case, do
            -- nothing and loop to try the UPDATE again.
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;


-- Trigger to update "db_row_last_updated" for cache tables
CREATE OR REPLACE FUNCTION cache.update_cache_db_row_last_updated()
RETURNS TRIGGER AS $$
BEGIN
    NEW.db_row_last_updated = NOW();
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';


-- Helper to purge object caches
CREATE OR REPLACE FUNCTION cache.purge_object_caches()
RETURNS VOID AS
$$
BEGIN

    RAISE NOTICE 'Purging "s3_raw_downloads_cache" table...';
    EXECUTE '
        DELETE FROM cache.s3_raw_downloads_cache
        WHERE db_row_last_updated <= NOW() - INTERVAL ''7 days'';
    ';

    RAISE NOTICE 'Purging "s3_bitly_processing_results_cache" table...';
    EXECUTE '
        DELETE FROM cache.s3_bitly_processing_results_cache
        WHERE db_row_last_updated <= NOW() - INTERVAL ''7 days'';
    ';

END;
$$
LANGUAGE plpgsql;


--
-- Raw downloads from S3 cache
--

CREATE UNLOGGED TABLE cache.s3_raw_downloads_cache (
    s3_raw_downloads_cache_id SERIAL    PRIMARY KEY,
    object_id                 BIGINT    NOT NULL
                                            REFERENCES public.downloads (downloads_id)
                                            ON DELETE CASCADE,

    -- Will be used to purge old cache objects;
    -- don't forget to update cache.purge_object_caches()
    db_row_last_updated       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    raw_data                  BYTEA     NOT NULL
);
CREATE UNIQUE INDEX s3_raw_downloads_cache_object_id
    ON cache.s3_raw_downloads_cache (object_id);
CREATE INDEX s3_raw_downloads_cache_db_row_last_updated
    ON cache.s3_raw_downloads_cache (db_row_last_updated);

ALTER TABLE cache.s3_raw_downloads_cache
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;

CREATE TRIGGER s3_raw_downloads_cache_db_row_last_updated_trigger
    BEFORE INSERT OR UPDATE ON cache.s3_raw_downloads_cache
    FOR EACH ROW EXECUTE PROCEDURE cache.update_cache_db_row_last_updated();


--
-- Raw Bit.ly processing results from S3 cache
--

CREATE UNLOGGED TABLE cache.s3_bitly_processing_results_cache (
    s3_bitly_processing_results_cache_id  SERIAL    PRIMARY KEY,
    object_id                             BIGINT    NOT NULL
                                                        REFERENCES public.stories (stories_id)
                                                        ON DELETE CASCADE,

    -- Will be used to purge old cache objects;
    -- don't forget to update cache.purge_object_caches()
    db_row_last_updated       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    raw_data                  BYTEA     NOT NULL
);
CREATE UNIQUE INDEX s3_bitly_processing_results_cache_object_id
    ON cache.s3_bitly_processing_results_cache (object_id);
CREATE INDEX s3_bitly_processing_results_cache_db_row_last_updated
    ON cache.s3_bitly_processing_results_cache (db_row_last_updated);

ALTER TABLE cache.s3_bitly_processing_results_cache
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;

CREATE TRIGGER s3_bitly_processing_results_cache_db_row_last_updated_trigger
    BEFORE INSERT OR UPDATE ON cache.s3_bitly_processing_results_cache
    FOR EACH ROW EXECUTE PROCEDURE cache.update_cache_db_row_last_updated();



