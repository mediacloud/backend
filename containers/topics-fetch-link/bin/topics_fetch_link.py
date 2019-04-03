#!/usr/bin/env python3

"""Topic Mapper job that fetches a link and either matches it to an existing story or generates a story from it."""

import time
from typing import Optional

from mediawords.db import connect_to_db
from mediawords.job import AbstractJob, McAbstractJobException, JobBrokerApp, JobManager
from mediawords.tm.fetch_link import fetch_topic_url_update_state
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)

REQUEUES_UNTIL_SLEEP = 200
"""After requeueing this many times in a rows, start sleeping one second before each requeue."""


class McFetchLinkJobException(McAbstractJobException):
    """Exceptions dealing with job setup and routing."""
    pass


class FetchLinkJob(AbstractJob):
    """Fetch a link for a topic and either match it to an existing story or generate a story from it.

    Almost all of the interesting functionality here happens in fetch_topic_url(). The code here just deals with
    routing, including requeueing responses throttled by mediawords.util.web.user_agent.throttled."""

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
    jobs locked on a given media source. It does happen, though -- I added that nonblocking / requeueing code in the
    first place because the extractor pool was sometimes getting all stuck waiting for a single media source.
    """

    @classmethod
    def run_job(
            cls,
            topic_fetch_urls_id: int,
            domain_timeout: Optional[int] = None) -> None:
        """Call fetch_topic_url and requeue the job of the request has been domain throttled.

        Arguments:
        topic_fetch_urls_id - id of topic_fetch_urls row
        domain_timeout - pass down to ThrottledUserAgent to set the timeout for each domain

        Returns:
        None

        """
        if isinstance(topic_fetch_urls_id, bytes):
            topic_fetch_urls_id = decode_object_from_bytes_if_needed(topic_fetch_urls_id)
        topic_fetch_urls_id = int(topic_fetch_urls_id)

        if topic_fetch_urls_id is None:
            raise McFetchLinkJobException("'topic_fetch_urls_id' is None.")

        log.info("Start fetch for topic_fetch_url %d" % topic_fetch_urls_id)

        db = connect_to_db()

        try:
            if not fetch_topic_url_update_state(db=db,
                                                topic_fetch_urls_id=topic_fetch_urls_id,
                                                domain_timeout=domain_timeout):
                JobManager.add_to_queue(name='MediaWords::Job::TM::FetchLink', topic_fetch_urls_id=topic_fetch_urls_id)

                cls._consecutive_requeues += 1
                if cls._consecutive_requeues > REQUEUES_UNTIL_SLEEP:
                    log.info("sleeping after %d consecutive retries ..." % cls._consecutive_requeues)
                    time.sleep(1)

        except Exception as ex:
            # Error has already been logged by fetch_topic_url_update_state(), so we only need to work out the
            # "consecutive retries" here
            log.error(f"Fetching URL for ID {topic_fetch_urls_id} failed: {ex}")
            cls._consecutive_requeues = 0

        log.info("Finished fetch for topic_fetch_url %d" % topic_fetch_urls_id)

    @classmethod
    def queue_name(cls) -> str:
        """Set queue name."""
        return 'MediaWords::Job::TM::FetchLink'


if __name__ == '__main__':
    app = JobBrokerApp(queue_name=FetchLinkJob.queue_name())
    app.start_worker()
