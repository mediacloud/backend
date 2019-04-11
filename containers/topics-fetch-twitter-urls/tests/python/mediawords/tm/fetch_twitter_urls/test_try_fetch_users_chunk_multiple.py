#!/usr/bin/env py.test

import random
import threading

import httpretty

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic
# noinspection PyProtectedMember
from mediawords.tm.fetch_twitter_urls import _try_fetch_users_chunk

from mediawords.tm.fetch_twitter_urls.mock_lookups import mock_users_lookup


def test_try_fetch_users_chunk_multiple():
    """Test fetch_100_users using mock. Run in parallel threads to test for race conditions."""

    def _try_fetch_users_chunk_threaded(topic_: dict, tfus_: list) -> None:
        """Call ftu._try_fetch_users_chunk with a newly created db handle for thread safety."""
        db_ = connect_to_db()
        _try_fetch_users_chunk(db_, topic_, tfus_)

    num_threads = 20

    httpretty.enable()  # enable HTTPretty so that it will monkey patch the socket module
    httpretty.register_uri(
        httpretty.POST, "https://api.twitter.com/1.1/users/lookup.json", body=mock_users_lookup)

    db = connect_to_db()

    topic = create_test_topic(db, 'test')
    topics_id = topic['topics_id']

    num_urls_per_thread = 100

    threads = []
    for j in range(num_threads):
        tfus = []
        for i in range(num_urls_per_thread):
            url = 'https://twitter.com/test_user_%s' % i
            tfu = db.create('topic_fetch_urls', {'topics_id': topics_id, 'url': url, 'state': 'pending'})
            tfus.append(tfu)

        random.shuffle(tfus)

        t = threading.Thread(target=_try_fetch_users_chunk_threaded, args=(topic, tfus))
        t.start()
        threads.append(t)

    [t.join() for t in threads]

    [num_topic_stories] = db.query(
        "select count(*) from topic_stories where topics_id = %(a)s", {'a': topics_id}).flat()
    assert num_urls_per_thread == num_topic_stories

    httpretty.disable()
    httpretty.reset()
