#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import fatal_error

from podcast_fetch_transcript.exceptions import McPodcastFetchTranscriptSoftException

log = create_logger(__name__)


def run_podcast_fetch_transcript(stories_id: int, speech_operation_id: str) -> None:
    """Fetch a completed episode transcripts from Speech API for story."""

    if isinstance(stories_id, bytes):
        stories_id = decode_object_from_bytes_if_needed(stories_id)
    stories_id = int(stories_id)

    speech_operation_id = decode_object_from_bytes_if_needed(speech_operation_id)

    if not stories_id:
        fatal_error("'stories_id' is unset.")
    if not speech_operation_id:
        fatal_error("'speech_operation_id' is unset.")

    db = connect_to_db()

    log.info(f"Fetching podcast episode transcript for story {stories_id}...")
    log.debug(f"Speech API operation ID: {speech_operation_id}")

    try:
        fetch_and_store_episode(db=db, stories_id=stories_id)

    except McPodcastFetchTranscriptSoftException as ex:
        # Soft exceptions
        log.error(f"Unable to fetch podcast episode for story {stories_id}: {ex}")
        raise ex
    except Exception as ex:
        # Hard and other exceptions
        fatal_error(f"Fatal / unknown error while fetching podcast episode for story {stories_id}: {ex}")

    log.info(f"Done fetching podcast episode transcript for story {stories_id}")


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::Podcast::FetchTranscript')
    app.start_worker(handler=run_podcast_fetch_transcript)
