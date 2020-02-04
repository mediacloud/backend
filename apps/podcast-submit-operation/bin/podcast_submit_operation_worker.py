#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import fatal_error

from podcast_submit_operation.exceptions import McPodcastSubmitOperationSoftException
from podcast_submit_operation.submit_operation import get_podcast_episode, submit_transcribe_operation

log = create_logger(__name__)

ADD_TO_QUEUE_AT_DURATION_MULTIPLIER = 1.1
"""
How soon to expect the transcription results to become available in relation to episode's duration.

For example, if the episode's duration is 60 minutes, and the multiplier is 1.1, the transcription results fetch will
first be attempted after 60 * 1.1 = 66 minutes.
"""


def run_podcast_submit_operation(stories_id: int) -> None:
    """Submit a podcast episode to the Speech API."""

    if isinstance(stories_id, bytes):
        stories_id = decode_object_from_bytes_if_needed(stories_id)
    stories_id = int(stories_id)

    db = connect_to_db()

    log.info(f"Submitting story's {stories_id} podcast episode for transcription...")

    try:
        episode = get_podcast_episode(db=db, stories_id=stories_id)
        speech_operation_id = submit_transcribe_operation(episode=episode)

        db.query("""
            UPDATE podcast_episodes
            SET speech_operation_id = %(speech_operation_id)s
            WHERE podcast_episodes_id = %(podcast_episodes_id)s
        """, {
            'podcast_episodes_id': episode.podcast_episodes_id,
            'speech_operation_id': speech_operation_id,
        })

        add_to_queue_interval = f"{int(episode.duration + ADD_TO_QUEUE_AT_DURATION_MULTIPLIER)} seconds"
        db.query("""
            INSERT INTO podcast_episode_transcript_fetches (
                podcast_episodes_id,
                add_to_queue_at
            ) VALUES (
                %(podcast_episodes_id)s,
                NOW() + INTERVAL %(add_to_queue_interval)s
            )
        """, {
            'podcast_episodes_id': episode.podcast_episodes_id,
            'add_to_queue_interval': add_to_queue_interval,
        })

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
