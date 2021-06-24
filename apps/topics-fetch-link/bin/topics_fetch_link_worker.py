#!/usr/bin/env python3

"""Topic Mapper job that fetches a link and either matches it to an existing story or generates a story from it."""

import time
from typing import Optional

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from topics_fetch_link.fetch_link import fetch_topic_url_update_state
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)

QUEUE_NAME = 'MediaWords::Job::TM::FetchLink'
"""Queue name for topics_fetch_link jobs."""

REQUEUES_UNTIL_SLEEP = 200
"""After requeueing this many times in a rows, start sleeping one second before each requeue."""

_consecutive_requeues = 0
"""(Here and in extract-and-vector) Number of times this worker had to requeue a job.

Both of the extract_and_vector and fetch_link jobs have locking (of the media id for extract_and_vector and for the
web fetching domain locking for fetch_link). The locks in both cases are handled by a non-blocking query to postgres
(for extract_and_vector of an advisory lock, for fetch_link of the domain_requests table). It's easy for the jobs to
get into a tight loop of trying and failing to obtain the lock and in the process putting a lot of load onto
postgres (through the lock queries) and rabbitmq (through the job fetches and requeues).

So in both cases I keep count of how many times in a row the job has failed to get the lock and immediately requeued
the job. Once that count hits some limit, I start throttling by waiting a second between attempts. To my knowledge,
this has worked well. It is much more important for the fetch_link job, since that queue often consists entirely of
requests that are being throttled. If we remove this check, that fetch_link pool will often enter a tight loop of
postgres queries and requeues (or 64 tight loops!).

It is less important for the extract_and_vector jobs because it is not as common for that queue to be filled up with
jobs locked on a given media source. It does happen, though -- I added that non-blocking / requeueing code in the
first place because the extractor pool was sometimes getting all stuck waiting for a single media source.
"""


class McFetchLinkJobException(Exception):
    """Exceptions dealing with job setup and routing."""
    pass


def run_topics_fetch_link(topic_fetch_urls_id: int, domain_timeout: Optional[int] = None) -> None:
    """Fetch a link for a topic and either match it to an existing story or generate a story from it.

    Almost all of the interesting functionality here happens in fetch_topic_url(). The code here just deals with
    routing, including requeueing responses throttled by mediawords.util.web.user_agent.throttled."""
    global _consecutive_requeues

    if isinstance(topic_fetch_urls_id, bytes):
        topic_fetch_urls_id = decode_object_from_bytes_if_needed(topic_fetch_urls_id)
    topic_fetch_urls_id = int(topic_fetch_urls_id)

    if topic_fetch_urls_id is None:
        raise McFetchLinkJobException("'topic_fetch_urls_id' is None.")

    # FIXME topics_id could be passed as an argument
    topics_id = db.query("""
        SELECT topics_id
        FROM topic_fetch_urls
        WHERE topic_fetch_urls_id = %(topic_fetch_urls_id)s
    """, {'topic_fetch_urls_id': topic_fetch_urls_id}).flat()[0]

    log.info(f"Starting fetch for topic {topics_id}, topic_fetch_url {topic_fetch_urls_id}")

    db = connect_to_db()

    try:
        if not fetch_topic_url_update_state(db=db,
                                            topics_id=topics_id,
                                            topic_fetch_urls_id=topic_fetch_urls_id,
                                            domain_timeout=domain_timeout):
            JobBroker(queue_name=QUEUE_NAME).add_to_queue(topic_fetch_urls_id=topic_fetch_urls_id)

            _consecutive_requeues += 1
            if _consecutive_requeues > REQUEUES_UNTIL_SLEEP:
                log.info("sleeping after %d consecutive retries ..." % _consecutive_requeues)
                time.sleep(1)

    except Exception as ex:
        # Error has already been logged by fetch_topic_url_update_state(), so we only need to work out the
        # "consecutive retries" here
        log.error(f"Fetching URL for ID {topic_fetch_urls_id} failed: {ex}")
        _consecutive_requeues = 0

    log.info(f"Finished fetch for topic {topics_id}, topic_fetch_url {topic_fetch_urls_id}")


if __name__ == '__main__':
    app = JobBroker(queue_name=QUEUE_NAME)
    app.start_worker(handler=run_topics_fetch_link)
