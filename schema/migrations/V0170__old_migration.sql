-- "media.content_delay" should have been added in "mediawords-4504-4505.sql"
-- schema migration file, but it wasn't there
--
-- Additionally, the column is live on the production database, so we test if
-- it's there before trying to add it

DO $$ 
    BEGIN
        ALTER TABLE media
            -- Delay content downloads for this media source this many hours
            ADD COLUMN content_delay int;
    EXCEPTION
        WHEN duplicate_column THEN
            RAISE NOTICE 'Column "media.content_delay" already exists.';
    END
$$;
