


-- stats for deprecated Twitter share counts
create table story_statistics_twitter (
    story_statistics_id         serial      primary key,
    stories_id                  int         not null references stories on delete cascade,

    twitter_url_tweet_count     int         null,
    twitter_api_collect_date    timestamp   null,
    twitter_api_error           text        null
);

create unique index story_statistics_twitter_story on story_statistics_twitter ( stories_id );


-- Migrate Twitter stats collected so far to the new table
INSERT INTO story_statistics_twitter (stories_id, twitter_url_tweet_count, twitter_api_collect_date, twitter_api_error)
    SELECT stories_id, twitter_url_tweet_count, twitter_api_collect_date, twitter_api_error
    FROM story_statistics;


ALTER TABLE story_statistics
    DROP COLUMN twitter_url_tweet_count,
    DROP COLUMN twitter_api_collect_date,
    DROP COLUMN twitter_api_error;


