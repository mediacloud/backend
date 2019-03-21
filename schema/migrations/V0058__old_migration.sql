

-- stats for various externally dervied statistics about a story.  keeping this separate for now
-- from the bitly stats for simplicity sake during implementatino and testing
create table story_statistics (
    story_statistics_id             serial  primary key,
    stories_id                      int     not null references stories on delete cascade,
    twitter_url_tweet_count         int     null,
    twitter_url_tweet_count_error   text    null,
    facebook_share_count            int     null,
    facebook_share_count_error      text    null
);

create unique index story_statistics_story on story_statistics ( stories_id );





