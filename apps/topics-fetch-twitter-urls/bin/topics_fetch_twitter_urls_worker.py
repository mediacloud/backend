#!/usr/bin/env python3

"""
Topic Mapper job that fetches twitter status and user urls from the twitter api and adds them to the topic
if they match the topic pattern.
"""
from typing import List

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger

from topics_fetch_twitter_urls.fetch_twitter_urls import fetch_twitter_urls_update_state

log = create_logger(__name__)


class McFetchTwitterUrlsJobException(Exception):
    """Exceptions dealing with job setup and routing."""
    pass


def run_topics_fetch_twitter_urls(topic_fetch_urls_ids: List[int]):
    """Fetch a set of twitter urls from the twitter api and add each as a topic story if it matches."""
    if not topic_fetch_urls_ids:
        raise McFetchTwitterUrlsJobException("'topic_fetch_urls_ids' is None or empty.")

    db = connect_to_db()

    # FIXME pass topics_id as an argument
    topics_id = db.query("""
        SELECT topics_id
        FROM topic_fetch_urls
        WHERE topic_fetch_urls_id = %(topic_fetch_urls_id)s
    """, {'topic_fetch_urls_id': topic_fetch_urls_ids[0]}).flat()[0]

    log.info(f"Starting to fetch Twitter URLs for {len(topic_fetch_urls_ids)} topic_fetch_urls")

    fetch_twitter_urls_update_state(db=db, topics_id=topics_id, topic_fetch_urls_ids=topic_fetch_urls_ids)

    log.info(f"Finished fetching Twitter URLs for {len(topic_fetch_urls_ids)} topic_fetch_urls")


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::TM::FetchTwitterUrls')
    app.start_worker(handler=run_topics_fetch_twitter_urls)
