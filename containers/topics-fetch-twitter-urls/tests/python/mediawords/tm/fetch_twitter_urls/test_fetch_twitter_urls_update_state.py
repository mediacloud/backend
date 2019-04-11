#!/usr/bin/env py.test

import random

import httpretty

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic

from mediawords.tm.fetch_twitter_urls import fetch_twitter_urls_update_state
from mediawords.tm.fetch_twitter_urls.mock_lookups import mock_statuses_lookup, mock_users_lookup


def test_fetch_twitter_urls_update_state():
    """Test fetch_100_tweets using mock."""
    httpretty.enable()
    httpretty.register_uri(
        httpretty.GET, "https://api.twitter.com/1.1/statuses/lookup.json", body=mock_statuses_lookup)
    httpretty.register_uri(
        httpretty.POST, "https://api.twitter.com/1.1/users/lookup.json", body=mock_users_lookup)

    db = connect_to_db()

    topic = create_test_topic(db, 'test')
    topics_id = topic['topics_id']

    tfus = []

    num_tweets = 150
    for i in range(num_tweets):
        url = 'https://twitter.com/foo/status/%d' % i
        tfu = db.create('topic_fetch_urls', {'topics_id': topics_id, 'url': url, 'state': 'pending'})
        tfus.append(tfu)

    num_users = 150
    for i in range(num_users):
        url = 'https://twitter.com/test_user_%s' % i
        tfu = db.create('topic_fetch_urls', {'topics_id': topics_id, 'url': url, 'state': 'pending'})
        tfus.append(tfu)

    tfu_ids = [u['topic_fetch_urls_id'] for u in tfus]
    random.shuffle(tfu_ids)

    fetch_twitter_urls_update_state(db=db, topic_fetch_urls_ids=tfu_ids)

    [num_tweet_stories] = db.query(
        """
        select count(*)
            from topic_stories ts
                join stories s using ( stories_id )
            where topics_id = %(a)s and url ~ '/status/[0-9]+'
        """,
        {'a': topics_id}).flat()
    assert num_tweet_stories == num_tweets

    [num_user_stories] = db.query(
        """
        select count(*)
            from topic_stories ts
                join stories s using ( stories_id )
            where topics_id = %(a)s and url !~ '/status/[0-9]+'
        """,
        {'a': topics_id}).flat()
    assert num_user_stories == num_users

    httpretty.disable()
    httpretty.reset()
