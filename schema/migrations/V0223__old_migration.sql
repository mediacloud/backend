

ALTER TABLE feeds
    RENAME COLUMN last_download_time TO last_attempted_download_time;
ALTER TABLE feeds
    ADD COLUMN last_successful_download_time TIMESTAMP WITH TIME ZONE;
UPDATE feeds
    SET last_new_story_time = GREATEST( last_attempted_download_time, last_new_story_time );
ALTER INDEX feeds_last_download_time
    RENAME TO feeds_last_attempted_download_time;
CREATE INDEX feeds_last_successful_download_time
    ON feeds(last_successful_download_time);


