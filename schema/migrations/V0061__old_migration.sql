


-- Helper to purge object caches
CREATE OR REPLACE FUNCTION cache.purge_object_caches()
RETURNS VOID AS
$$
BEGIN

    RAISE NOTICE 'Purging "s3_raw_downloads_cache" table...';
    EXECUTE '
        DELETE FROM cache.s3_raw_downloads_cache
        WHERE db_row_last_updated <= NOW() - INTERVAL ''3 days'';
    ';

    RAISE NOTICE 'Purging "s3_bitly_processing_results_cache" table...';
    EXECUTE '
        DELETE FROM cache.s3_bitly_processing_results_cache
        WHERE db_row_last_updated <= NOW() - INTERVAL ''3 days'';
    ';

END;
$$
LANGUAGE plpgsql;



