

ALTER TABLE story_statistics
    RENAME COLUMN twitter_url_tweet_count_error TO twitter_api_error;
ALTER TABLE story_statistics
    RENAME COLUMN facebook_share_count_error TO facebook_api_error;

ALTER TABLE story_statistics
    ADD COLUMN facebook_comment_count INT NULL,
    ADD COLUMN twitter_api_collect_date TIMESTAMP NULL,
    ADD COLUMN facebook_api_collect_date TIMESTAMP NULL;



