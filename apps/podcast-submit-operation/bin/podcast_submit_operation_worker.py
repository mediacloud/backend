#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import fatal_error

from podcast_submit_operation.exceptions import McPodcastSubmitOperationSoftException
from podcast_submit_operation.submit_operation import submit_transcribe_operation

log = create_logger(__name__)


def run_podcast_submit_operation(stories_id: int) -> None:
    """Submit a podcast episode to the Speech API."""

    if isinstance(stories_id, bytes):
        stories_id = decode_object_from_bytes_if_needed(stories_id)
    stories_id = int(stories_id)

    db = connect_to_db()

    log.info(f"Submitting story's {stories_id} podcast episode for transcription...")

    try:
        submit_transcribe_operation(db=db, stories_id=stories_id)

        # Nothing to add to the job queue, "podcast-poll-due-operations" will do it itself when it's time

    except McPodcastSubmitOperationSoftException as ex:
        # Soft exceptions
        log.error(f"Unable to submit podcast episode for story {stories_id}: {ex}")
        raise ex

    except Exception as ex:
        # Hard and other exceptions
        fatal_error(f"Fatal / unknown error while submitting podcast episode for story {stories_id}: {ex}")

    log.info(f"Done submitting story's {stories_id} podcast episode for transcription")


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::Podcast::SubmitOperation')
    app.start_worker(handler=run_podcast_submit_operation)
