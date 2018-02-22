#!/usr/bin/env python3.5
"""Topic Maapper job that fetches a link and either matches it to an existing story or generates a story from it."""

import datetime
import time
import traceback
import typing

from mediawords.db import connect_to_db
from mediawords.job import AbstractJob, McAbstractJobException, JobBrokerApp
import mediawords.tm.fetch_link
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.web.user_agent.throttled import McThrottledDomainException


log = create_logger(__name__)


# after requeueing this many times in a rows, start sleeping one second before each requeue
REQUEUES_UNTIL_SLEEP = 20


class McFetchLinkJobException(McAbstractJobException):
    """Exceptions dealing with job setup and routing."""

    pass


class FetchLinkJob(AbstractJob):
    """
    Fetch a link for a topic and either match it to an existing story or generate a story from it.

    Almost all of the interesting functionality here happens in mediawords.tm.fetch_link.fetch_topic_url().  The code
    here just deals with routing, including requeueing responses throttled by mediawords.util.web.user_agent.throttled.

    Start this worker script by running:

        ./script/run_in_env.sh ./mediacloud/mediawords/job/tm/fetch_link_job.py
    """

    _consecutive_requeues = 0

    @classmethod
    def run_job(
            cls,
            topic_fetch_urls_id: int,
            dummy_requeue: bool=False,
            domain_timeout: typing.Optional[int]=None) -> None:
        """Call fetch_topic_url and requeue the job of the request has been domain throttled.

        Arguments:
        topic_fetch_urls_id - id of topic_fetch_urls row
        dummy_requeue - if True, set state to FETCH_STATE_REQUEUED as normal but do not actually requeue
        domain_timeout - pass down to ThrottledUserAgent to set the timeout for each domain

        Returns:
        None

        """
        if isinstance(topic_fetch_urls_id, bytes):
            topic_fetch_urls_id = decode_object_from_bytes_if_needed(topic_fetch_urls_id)
        if topic_fetch_urls_id is None:
            raise McFetchLinkJobException("'topic_fetch_urls_id' is None.")

        log.info("Start fetch for topic_fetch_url %d" % topic_fetch_urls_id)

        try:
            db = connect_to_db()
            mediawords.tm.fetch_link.fetch_topic_url(
                db=db,
                topic_fetch_urls_id=topic_fetch_urls_id,
                domain_timeout=domain_timeout)
            cls._consecutive_requeues = 0
        except McThrottledDomainException:
            # if a domain has been throttled, just add it back to the end of the queue
            log.info("Fetch for topic_fetch_url %d domain throttled.  Requeueing ..." % topic_fetch_urls_id)

            cls._consecutive_requeues += 1
            if cls._consecutive_requeues > REQUEUES_UNTIL_SLEEP:
                log.info("sleeping after %d consecutive retries ..." % cls._consecutive_requeues)
                time.sleep(1)

            db.update_by_id(
                'topic_fetch_urls',
                topic_fetch_urls_id,
                {'state': mediawords.tm.fetch_link.FETCH_STATE_REQUEUED, 'fetch_date': datetime.datetime.now()})
            if not dummy_requeue:
                FetchLinkJob.add_to_queue(topic_fetch_urls_id)
        except Exception as ex:
            cls._consecutive_requeues = 0
            raise McFetchLinkJobException(
                "Unable to process topic_fetch_url %d: %s" % (topic_fetch_urls_id, traceback.format_exc()))

        db.disconnect()

        log.info("Finished fetch for topic_fetch_url %d" % topic_fetch_urls_id)

    @classmethod
    def queue_name(cls) -> str:
        """Set queue name."""
        return 'MediaWords::Job::TM::FetchLink'


if __name__ == '__main__':
    app = JobBrokerApp(job_class=FetchLinkJob)
    app.start_worker()
