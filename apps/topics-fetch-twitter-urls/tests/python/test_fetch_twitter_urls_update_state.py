import random

import requests_mock

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic

from topics_fetch_twitter_urls.fetch_twitter_urls import fetch_twitter_urls_update_state
from .mock_lookups import mock_statuses_lookup, mock_users_lookup


def test_fetch_twitter_urls_update_state():
    """Test fetch_100_tweets using mock."""

    db = connect_to_db()

    topic = create_test_topic(db, 'test')
    topics_id = topic['topics_id']

    tfus = []

    num_tweets = 150
    for i in range(num_tweets):
        url = f'https://twitter.com/foo/status/{i}'
        tfu = db.create('topic_fetch_urls', {'topics_id': topics_id, 'url': url, 'state': 'pending'})
        tfus.append(tfu)

    num_users = 150
    for i in range(num_users):
        url = f'https://twitter.com/test_user_{i}'
        tfu = db.create('topic_fetch_urls', {'topics_id': topics_id, 'url': url, 'state': 'pending'})
        tfus.append(tfu)

    tfu_ids = [u['topic_fetch_urls_id'] for u in tfus]
    random.shuffle(tfu_ids)

    with requests_mock.Mocker() as m:
        m.get("https://api.twitter.com/1.1/statuses/lookup.json", text=mock_statuses_lookup)
        m.post("https://api.twitter.com/1.1/users/lookup.json", text=mock_users_lookup)

        fetch_twitter_urls_update_state(db=db, topics_id=topics_id, topic_fetch_urls_ids=tfu_ids)

    [num_tweet_stories] = db.query("""
        WITH stories_from_topic AS (
            SELECT stories_id
            FROM topic_stories
            WHERE topics_id = %(topics_id)s
        )
        
        SELECT COUNT(*)
        FROM stories
        WHERE
            stories_id IN (
                SELECT stories_id
                FROM stories_from_topic
            ) AND
            url ~ '/status/[0-9]+'
    """, {
        'topics_id': topics_id,
    }).flat()
    assert num_tweet_stories == num_tweets

    [num_user_stories] = db.query("""
        WITH stories_from_topic AS (
            SELECT stories_id
            FROM topic_stories
            WHERE topics_id = %(topics_id)s
        )
        
        SELECT COUNT(*)
        FROM stories
        WHERE
            stories_id IN (
                SELECT stories_id
                FROM stories_from_topic
            ) AND
            url !~ '/status/[0-9]+' 
    """, {
        'topics_id': topics_id
    }).flat()
    assert num_user_stories == num_users
