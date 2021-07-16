import multiprocessing
import random

import requests_mock

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic

# noinspection PyProtectedMember
from topics_fetch_twitter_urls.fetch_twitter_urls import _try_fetch_tweets_chunk

from .mock_lookups import mock_statuses_lookup


def test_try_fetch_tweets_chunk_multiple():
    def _try_fetch_tweets_chunk_parallel(topic_: dict, tfus_: list) -> None:
        db_ = connect_to_db()

        with requests_mock.Mocker() as m:
            m.get("https://api.twitter.com/1.1/statuses/lookup.json", text=mock_statuses_lookup)
            _try_fetch_tweets_chunk(db_, topic_, tfus_)

    num_jobs = 20

    db = connect_to_db()

    topic = create_test_topic(db, 'test')
    topics_id = topic['topics_id']

    num_urls_per_job = 100

    jobs = []
    for j in range(num_jobs):
        tfus = []
        for i in range(num_urls_per_job):
            url = 'https://twitter.com/foo/status/%d' % i
            tfu = db.create('topic_fetch_urls', {'topics_id': topics_id, 'url': url, 'state': 'pending'})
            tfus.append(tfu)

        random.shuffle(tfus)

        job = multiprocessing.Process(target=_try_fetch_tweets_chunk_parallel, args=(topic, tfus))
        job.start()
        jobs.append(job)

    [job.join() for job in jobs]

    [num_topic_stories] = db.query(
        "SELECT COUNT(*) FROM topic_stories WHERE topics_id = %(topics_id)s",
        {'topics_id': topics_id}
    ).flat()
    assert num_urls_per_job == num_topic_stories
