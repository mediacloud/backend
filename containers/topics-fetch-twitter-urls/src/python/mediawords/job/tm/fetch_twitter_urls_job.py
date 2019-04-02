#!/usr/bin/env python
"""Topic Maapper job that fetches twitter status and user urls from the twitter api and adds them to the topic
if they match the topic pattern.
."""

import traceback

from mediawords.db import connect_to_db
from mediawords.job import AbstractJob, McAbstractJobException, JobBrokerApp
import mediawords.tm.fetch_twitter_urls
from mediawords.util.log import create_logger

log = create_logger(__name__)


class McFetchTwitterUrlsJobException(McAbstractJobException):
    """Exceptions dealing with job setup and routing."""

    pass


class FetchTwitterUrlsJob(AbstractJob):
    """
    Fetch a set of twitter urls from the twitter api and add each as a topic story if it matches.

    All of the interesting logic is in mediawords.tm.fetch_twitter_urls.

    Start this worker script by running:

        ./script/run_in_env.sh ./mediacloud/mediawords/job/tm/fetch_link_job.py
    """

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

        try:
            mediawords.tm.fetch_twitter_urls.fetch_twitter_urls(db=db, topic_fetch_urls_ids=topic_fetch_urls_ids)
        except Exception as ex:
            log.error("Error while fetching URL with ID {}: {}".format(topic_fetch_urls_ids, str(ex)))
            db.query(
                """
                update topic_fetch_urls set state = %(a)s, message = %(b)s, fetch_date = now()
                    where topic_fetch_urls_id = any(%(c)s)
                """,
                {
                    'a': mediawords.tm.fetch_link.FETCH_STATE_PYTHON_ERROR,
                    'b': traceback.format_exc(),
                    'c': topic_fetch_urls_ids
                })

        db.disconnect()

        log.info("Finished fetching twitter url")

    @classmethod
    def queue_name(cls) -> str:
        """Set queue name."""
        return 'MediaWords::Job::TM::FetchTwitterUrls'


if __name__ == '__main__':
    app = JobBrokerApp(queue_name=FetchTwitterUrlsJob.queue_name())
    app.start_worker()
