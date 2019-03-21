


-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE raw_downloads
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;



