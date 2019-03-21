

drop index topic_tweet_urls_tt;
create unique index topic_tweet_urls_tt on topic_tweet_urls ( topic_tweets_id, url );




