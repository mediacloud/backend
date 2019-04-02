#!/usr/bin/env python3

"""Topic Mapper job that fetches a link and either matches it to an existing story or generates a story from it."""

from typing import Optional

from mediawords.db import connect_to_db
from mediawords.job import AbstractJob, McAbstractJobException, JobBrokerApp, JobManager
from mediawords.tm.fetch_link import fetch_topic_url_update_state
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McFetchLinkJobException(McAbstractJobException):
    """Exceptions dealing with job setup and routing."""

    pass


class FetchLinkJob(AbstractJob):
    """Fetch a link for a topic and either match it to an existing story or generate a story from it.

    Almost all of the interesting functionality here happens in fetch_topic_url().
    The code here just deals with routing, including requeueing responses throttled by
    mediawords.util.web.user_agent.throttled."""

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

        if not fetch_topic_url_update_state(db=db,
                                            topic_fetch_urls_id=topic_fetch_urls_id,
                                            domain_timeout=domain_timeout):
            JobManager.add_to_queue(name='MediaWords::Job::TM::FetchLink', topic_fetch_urls_id=topic_fetch_urls_id)

        log.info("Finished fetch for topic_fetch_url %d" % topic_fetch_urls_id)

    @classmethod
    def queue_name(cls) -> str:
        """Set queue name."""
        return 'MediaWords::Job::TM::FetchLink'


if __name__ == '__main__':
    app = JobBrokerApp(queue_name=FetchLinkJob.queue_name())
    app.start_worker()
