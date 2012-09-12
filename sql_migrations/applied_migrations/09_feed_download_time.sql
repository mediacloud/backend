
-- Add column to allow more active feeds to be downloaded more frequently.
ALTER TABLE feeds ADD COLUMN last_new_story_time timestamp without time zone;
UPDATE feeds SET last_new_story_time = greatest( last_download_time, last_new_story_time );
ALTER TABLE feeds ALTER COLUMN last_download_time TYPE timestamp with time zone;
ALTER TABLE feeds ALTER COLUMN last_new_story_time TYPE timestamp with time zone;

