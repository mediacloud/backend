#!/usr/bin/env python3

"""
Topic Mapper job that fetches twitter status and user urls from the twitter api and adds them to the topic
if they match the topic pattern.
"""

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger

from topics_fetch_twitter_urls.fetch_twitter_urls import fetch_twitter_urls_update_state

log = create_logger(__name__)


class McFetchTwitterUrlsJobException(Exception):
    """Exceptions dealing with job setup and routing."""
    pass


def run_topics_fetch_twitter_urls(topic_fetch_urls_ids: list):
    """Fetch a set of twitter urls from the twitter api and add each as a topic story if it matches.

    All of the interesting logic is in mediawords.tm.fetch_twitter_urls."""
    if topic_fetch_urls_ids is None:
        raise McFetchTwitterUrlsJobException("'topic_fetch_urls_ids' is None.")

    log.info("Start fetch twitter urls for %d topic_fetch_urls" % len(topic_fetch_urls_ids))

    db = connect_to_db()

    fetch_twitter_urls_update_state(db=db, topic_fetch_urls_ids=topic_fetch_urls_ids)

    log.info("Finished fetching twitter urls")


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::TM::FetchTwitterUrls')
    app.start_worker(handler=run_topics_fetch_twitter_urls)
