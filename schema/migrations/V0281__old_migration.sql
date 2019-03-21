--
-- Kill all autovacuums before proceeding with DDL changes
--
SELECT pid
FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
WHERE backend_type = 'autovacuum worker'
  AND query ~ 'download_texts';


-- Proxy view to join partitioned and non-partitioned "download_texts" tables
CREATE OR REPLACE VIEW download_texts AS

    -- Non-partitioned table
    SELECT
        download_texts_np_id::bigint AS download_texts_id,
        downloads_id::bigint,
        download_text,
        download_text_length
    FROM download_texts_np

    UNION ALL

    -- Partitioned table
    SELECT
        download_texts_p_id AS download_texts_id,
        downloads_id,
        download_text,
        download_text_length
    FROM download_texts_p;
