

create table snap.tweet_stories (
    snapshots_id        int not null references snapshots on delete cascade,
    topic_tweets_id     int not null references topic_tweets on delete cascade,
    publish_date        date not null,
    twitter_user        varchar( 1024 ) not null,
    stories_id          int not null,
    media_id            int not null,
    num_ch_tweets       int not null,
    tweet_count         int not null
);

create index snap_tweet_stories on snap.tweet_stories ( snapshots_id );



