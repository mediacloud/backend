#!/usr/bin/env python3

import time

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from extract_and_vector.dbi.stories.extractor_arguments import PyExtractorArguments
from extract_and_vector.dbi.stories.extract import extract_and_process_story
from extract_and_vector.story_vectors import medium_is_locked

log = create_logger(__name__)

QUEUE_NAME = 'MediaWords::Job::ExtractAndVector'
"""Queue name for extractor jobs."""

_SLEEP_AFTER_REQUEUES = 100
"""Sleep for one second if there are more than this number of consecutive requeues"""

_consecutive_requeues = 0
"""(Here and in topics-fetch-link) Number of times this worker had to requeue a job.

See comment in topics_fetch_link.py."""


class McExtractAndVectorException(Exception):
    """ExtractAndVectorJob exception."""
    pass


def run_extract_and_vector(stories_id: int, use_cache: bool = False, use_existing: bool = False) -> None:
    """Extract, vector and process a story."""

    global _consecutive_requeues

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
        _consecutive_requeues += 1

        # Prevent spamming these requeue events if the locked media source is the only one in the queue
        if _consecutive_requeues > _SLEEP_AFTER_REQUEUES:
            log.warning(
                "Story extraction job has been requeued more than {} times, waiting before requeueing...".format(
                    _consecutive_requeues
                )
            )
            time.sleep(1)

        JobBroker(queue_name=QUEUE_NAME).add_to_queue(stories_id=stories_id)

        return

    _consecutive_requeues = 0

    log.info("Extracting story {}...".format(stories_id))

    db.begin()

    try:
        extractor_args = PyExtractorArguments(use_cache=use_cache, use_existing=use_existing)
        extract_and_process_story(db=db, story=story, extractor_args=extractor_args)

    except Exception as ex:
        raise McExtractAndVectorException("Extractor died while extracting story {}: {}".format(stories_id, ex))

    db.commit()

    log.info("Done extracting story {}.".format(stories_id))


if __name__ == '__main__':
    app = JobBroker(queue_name=QUEUE_NAME)
    app.start_worker(handler=run_extract_and_vector)
