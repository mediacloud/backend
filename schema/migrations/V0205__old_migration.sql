


-- ALTER TABLE raw_downloads ADD column might have worked too, but the table is
-- empty in production or very small in development environments, so to
-- preserve the column order let's just recreate everything

-- Kill all autovacuums before proceeding with DDL changes
SELECT pid
FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
WHERE backend_type = 'autovacuum worker'
  AND query ~ 'raw_downloads';

-- Rename "raw_downloads" to "raw_downloads_int"
ALTER TABLE raw_downloads
    RENAME TO raw_downloads_int;
ALTER SEQUENCE raw_downloads_raw_downloads_id_seq
    RENAME TO raw_downloads_int_raw_downloads_id_seq;
ALTER INDEX raw_downloads_pkey
    RENAME TO raw_downloads_int_pkey;
ALTER INDEX raw_downloads_object_id
    RENAME TO raw_downloads_int_object_id;
ALTER TRIGGER raw_downloads_test_referenced_download_trigger
    ON raw_downloads_int
    RENAME TO raw_downloads_int_test_referenced_download_trigger;

-- Create "raw_downloads" with a BIGINT "object_id"
CREATE TABLE raw_downloads (
    raw_downloads_id    BIGSERIAL   PRIMARY KEY,

    -- "downloads_id" from "downloads"
    object_id           BIGINT      NOT NULL,

    raw_data            BYTEA       NOT NULL
);
CREATE UNIQUE INDEX raw_downloads_object_id
    ON raw_downloads (object_id);
ALTER TABLE raw_downloads
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;
CREATE TRIGGER raw_downloads_test_referenced_download_trigger
    BEFORE INSERT OR UPDATE ON raw_downloads
    FOR EACH ROW
    EXECUTE PROCEDURE test_referenced_download_trigger('object_id');

-- Copy the data
INSERT INTO raw_downloads (object_id, raw_data)
    SELECT object_id::bigint, raw_data
    FROM raw_downloads_int;

-- Drop old table
DROP TABLE raw_downloads_int;




