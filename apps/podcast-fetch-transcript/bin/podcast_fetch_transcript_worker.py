#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import fatal_error

from podcast_fetch_transcript.exceptions import McPodcastFetchTranscriptSoftException
from podcast_fetch_transcript.fetch import fetch_transcript
from podcast_fetch_transcript.store import store_transcript

log = create_logger(__name__)

NOT_READY_RETRY_INTERVAL = 60 * 10
"""If the transcript is not ready yet, how many seconds to wait until retrying the fetch."""


def run_podcast_fetch_transcript(podcast_episode_transcript_fetches_id: int) -> None:
    """Fetch a completed episode transcripts from Speech API for story."""

    if isinstance(podcast_episode_transcript_fetches_id, bytes):
        podcast_episode_transcript_fetches_id = decode_object_from_bytes_if_needed(
            podcast_episode_transcript_fetches_id)
    podcast_episode_transcript_fetches_id = int(podcast_episode_transcript_fetches_id)

    if not podcast_episode_transcript_fetches_id:
        fatal_error("'podcast_episode_transcript_fetches_id' is unset.")

    db = connect_to_db()

    transcript_fetch = db.query("""
        UPDATE podcast_episode_transcript_fetches
        SET fetched_at = NOW()
        WHERE podcast_episode_transcript_fetches_id = %(podcast_episode_transcript_fetches_id)s
        RETURNING *
    """, {
        'podcast_episode_transcript_fetches_id': podcast_episode_transcript_fetches_id,
    }).hash()
    if not transcript_fetch:
        fatal_error(f"Transcript fetch for ID {podcast_episode_transcript_fetches_id} was not found.")

    log.info(f"Executing transcript fetch for ID {podcast_episode_transcript_fetches_id}...")

    try:

        transcript = fetch_transcript(
            db=db,
            podcast_episode_transcript_fetches_id=podcast_episode_transcript_fetches_id,
        )

        if transcript:
            log.info(f"Transcript fetched, storing...")

            store_transcript(db=db, transcript=transcript)

            JobBroker(queue_name='MediaWords::Job::ExtractAndVector').add_to_queue(stories_id=transcript.stories_id)

            db.query("""
                UPDATE podcast_episode_transcript_fetches
                SET result = 'success'
                WHERE podcast_episode_transcript_fetches_id = %(podcast_episode_transcript_fetches_id)s
            """, {
                'podcast_episode_transcript_fetches_id': podcast_episode_transcript_fetches_id,
            })

        else:
            log.info(f"Transcript is not done yet, will retry in {NOT_READY_RETRY_INTERVAL} seconds...")

            db.query("""
                INSERT INTO podcast_episode_transcript_fetches (
                    podcast_episodes_id,
                    add_to_queue_at
                ) VALUES (
                    %(podcast_episodes_id)s,
                    NOW() + INTERVAL %(add_to_queue_interval)s
                )
            """, {
                'podcast_episodes_id': transcript_fetch['podcast_episodes_id'],
                'add_to_queue_interval': f"{NOT_READY_RETRY_INTERVAL} seconds",
            })

            db.query("""
                UPDATE podcast_episode_transcript_fetches
                SET result = 'in_progress'
                WHERE podcast_episode_transcript_fetches_id = %(podcast_episode_transcript_fetches_id)s
            """, {
                'podcast_episode_transcript_fetches_id': podcast_episode_transcript_fetches_id,
            })

    except Exception as ex:

        # Try logging exception to the database
        try:
            db.query("""
                UPDATE podcast_episode_transcript_fetches
                SET
                    result = 'error',
                    error_message = %(error_message)s
                WHERE podcast_episode_transcript_fetches_id = %(podcast_episode_transcript_fetches_id)s
            """, {
                'podcast_episode_transcript_fetches_id': podcast_episode_transcript_fetches_id,
                'error_message': str(ex),
            })
        except Exception as ex2:
            fatal_error((
                f"Error while executing transcript fetch for ID {podcast_episode_transcript_fetches_id}: {ex}; "
                f"further, I wasn't able to log it to database because: {ex2}"
            ))

        if isinstance(ex, McPodcastFetchTranscriptSoftException):
            # Soft exceptions
            log.error(f"Unable to execute transcript fetch for ID {podcast_episode_transcript_fetches_id}: {ex}")
            raise ex

        else:
            # Hard and other exceptions
            fatal_error((
                f"Fatal / unknown error while executing transcript fetch "
                f"for ID {podcast_episode_transcript_fetches_id}: {ex}"
            ))

    log.info(f"Done executing transcript fetch for ID {podcast_episode_transcript_fetches_id}")


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::Podcast::FetchTranscript')
    app.start_worker(handler=run_podcast_fetch_transcript)
