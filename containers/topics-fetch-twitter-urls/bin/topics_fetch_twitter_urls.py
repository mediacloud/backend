#!/usr/bin/env python3

"""Topic Mapper job that fetches twitter status and user urls from the twitter api and adds them to the topic
if they match the topic pattern.
."""

from mediawords.db import connect_to_db
from mediawords.job import AbstractJob, McAbstractJobException, JobBrokerApp
from mediawords.tm.fetch_twitter_urls import fetch_twitter_urls_update_state
from mediawords.util.log import create_logger

log = create_logger(__name__)


class McFetchTwitterUrlsJobException(McAbstractJobException):
    """Exceptions dealing with job setup and routing."""

    pass


class FetchTwitterUrlsJob(AbstractJob):
    """Fetch a set of twitter urls from the twitter api and add each as a topic story if it matches.

    All of the interesting logic is in mediawords.tm.fetch_twitter_urls."""

    @classmethod
    def run_job(cls, topic_fetch_urls_ids: list):
        """Call fetch_twitter_urls and requeue the job of the request has been domain throttled.

        Arguments:
        topic_fetch_urls_ids - ids of topic_fetch_urls

        Returns:
        None

        """
        if topic_fetch_urls_ids is None:
            raise McFetchTwitterUrlsJobException("'topic_fetch_urls_ids' is None.")

        log.info("Start fetch twitter urls for %d topic_fetch_urls" % len(topic_fetch_urls_ids))

        db = connect_to_db()

        fetch_twitter_urls_update_state(db=db, topic_fetch_urls_ids=topic_fetch_urls_ids)

        log.info("Finished fetching twitter urls")

    @classmethod
    def queue_name(cls) -> str:
        """Set queue name."""
        return 'MediaWords::Job::TM::FetchTwitterUrls'


if __name__ == '__main__':
    app = JobBrokerApp(queue_name=FetchTwitterUrlsJob.queue_name())
    app.start_worker()
