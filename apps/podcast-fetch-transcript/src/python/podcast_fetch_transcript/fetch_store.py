from typing import Optional

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger

from podcast_fetch_transcript.exceptions import (
    McDatabaseErrorException,
    McDatabaseNotFoundException,
)
from podcast_fetch_transcript.handler import AbstractHandler, DefaultHandler

log = create_logger(__name__)

NOT_READY_RETRY_INTERVAL = 60 * 10
"""If the transcript is not ready yet, how many seconds to wait until retrying the fetch."""


def fetch_store_transcript(
        db: DatabaseHandler,
        podcast_episode_transcript_fetches_id: int,
        handler: Optional[AbstractHandler] = None,
) -> Optional[int]:
    """
    Try fetching and storing the transcript and update "podcast_episode_transcript_fetches" depending on how well it
    went.

    :param db: Database handler.
    :param podcast_episode_transcript_fetches_id: Transcript fetch ID.
    :param handler: Object of a AbstractHandler subclass which implements fetching and storing (useful for testing).
    :return: Story ID if transcript was fetched and stored, None otherwise.
    """

    if not handler:
        handler = DefaultHandler()

    transcript_fetch = db.query("""
        UPDATE podcast_episode_transcript_fetches
        SET fetched_at = NOW()
        WHERE podcast_episode_transcript_fetches_id = %(podcast_episode_transcript_fetches_id)s
        RETURNING *
    """, {
        'podcast_episode_transcript_fetches_id': podcast_episode_transcript_fetches_id,
    }).hash()
    if not transcript_fetch:
        raise McDatabaseNotFoundException(
            f"Transcript fetch for ID {podcast_episode_transcript_fetches_id} was not found."
        )

    try:

        transcript = handler.fetch_transcript(
            db=db,
            podcast_episode_transcript_fetches_id=podcast_episode_transcript_fetches_id,
        )

        if transcript:
            log.info(f"Transcript fetched, storing...")

            handler.store_transcript(db=db, transcript=transcript)

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
            raise McDatabaseErrorException((
                f"Error while executing transcript fetch for ID {podcast_episode_transcript_fetches_id}: {ex}; "
                f"further, I wasn't able to log it to database because: {ex2}"
            ))

        raise ex

    if transcript:
        return transcript.stories_id
    else:
        return None
