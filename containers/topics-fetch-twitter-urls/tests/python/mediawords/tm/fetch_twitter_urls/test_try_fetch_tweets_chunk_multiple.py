import random
import threading

import httpretty

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic
# noinspection PyProtectedMember
from mediawords.tm.fetch_twitter_urls import _try_fetch_tweets_chunk

from mediawords.tm.fetch_twitter_urls.mock_lookups import mock_statuses_lookup


def test_try_fetch_tweets_chunk_multiple():
    def _try_fetch_tweets_chunk_threaded(topic_: dict, tfus_: list) -> None:
        """Call ftu._try_fetch_tweets_chunk with a newly created db handle for thread safety."""
        db_ = connect_to_db()
        _try_fetch_tweets_chunk(db_, topic_, tfus_)

    num_threads = 20

    httpretty.enable()
    httpretty.register_uri(
        httpretty.GET, "https://api.twitter.com/1.1/statuses/lookup.json", body=mock_statuses_lookup)

    db = connect_to_db()

    topic = create_test_topic(db, 'test')
    topics_id = topic['topics_id']

    num_urls_per_thread = 100

    threads = []
    for j in range(num_threads):
        tfus = []
        for i in range(num_urls_per_thread):
            url = 'https://twitter.com/foo/status/%d' % i
            tfu = db.create('topic_fetch_urls', {'topics_id': topics_id, 'url': url, 'state': 'pending'})
            tfus.append(tfu)

        random.shuffle(tfus)

        t = threading.Thread(target=_try_fetch_tweets_chunk_threaded, args=(topic, tfus))
        t.start()
        threads.append(t)

    [t.join() for t in threads]

    [num_topic_stories] = db.query(
        "select count(*) from topic_stories where topics_id = %(a)s", {'a': topics_id}).flat()
    assert num_urls_per_thread == num_topic_stories

    httpretty.disable()
    httpretty.reset()
