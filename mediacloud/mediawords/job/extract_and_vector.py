#!/usr/bin/env python3

import time

from mediawords.db import connect_to_db
from mediawords.dbi.stories.extractor_arguments import PyExtractorArguments
from mediawords.dbi.stories.stories import extract_and_process_story
from mediawords.job import AbstractJob, McAbstractJobException, JobBrokerApp
from mediawords.story_vectors import medium_is_locked
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McExtractAndVectorException(McAbstractJobException):
    """ExtractAndVectorJob exception."""
    pass


class ExtractAndVectorJob(AbstractJob):
    """

    Extract, vector and process a story.

    Start this worker script by running:

        ./script/run_in_env.sh ./mediacloud/mediawords/job/extract_and_vector.py

    """

    # Sleep for one second if there are more than this number of consecutive requeues
    _SLEEP_AFTER_REQUEUES = 100

    # Count the number of consecutive requeues
    _consecutive_requeues = 0

    @classmethod
    def run_job(cls, stories_id: int, use_cache: bool = False) -> None:

        # MC_REWRITE_TO_PYTHON: remove after Python rewrite
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)
        stories_id = int(stories_id)

        if not stories_id:
            raise McExtractAndVectorException("'stories_id' is not set.")

        db = connect_to_db()

        story = db.find_by_id(table='stories', object_id=stories_id)
        if not story:
            raise McExtractAndVectorException("Story with ID {} was not found.".format(stories_id))

        if medium_is_locked(db=db, media_id=story['media_id']):
            log.warning("Requeueing job for story {} in locked medium {}...".format(stories_id, story['media_id']))
            ExtractAndVectorJob._consecutive_requeues += 1

            # Prevent spamming these requeue events if the locked media source is the only one in the queue
            if ExtractAndVectorJob._consecutive_requeues > ExtractAndVectorJob._SLEEP_AFTER_REQUEUES:
                time.sleep(1)

            ExtractAndVectorJob.add_to_queue(stories_id=stories_id)

            return

        ExtractAndVectorJob._consecutive_requeues = 0

        db.begin()

        try:
            extractor_args = PyExtractorArguments(use_cache=use_cache)
            extract_and_process_story(db=db, story=story, extractor_args=extractor_args)

        except Exception as ex:
            raise McExtractAndVectorException("Extractor died while extracting story {}: {}".format(stories_id, ex))

        db.commit()

    @classmethod
    def queue_name(cls) -> str:
        return 'MediaWords::Job::ExtractAndVector'


if __name__ == '__main__':
    app = JobBrokerApp(job_class=ExtractAndVectorJob)
    app.start_worker()
