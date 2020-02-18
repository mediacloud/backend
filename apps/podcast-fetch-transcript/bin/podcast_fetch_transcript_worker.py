#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import fatal_error

from podcast_fetch_transcript.exceptions import McPodcastFetchTranscriptSoftException

from podcast_fetch_transcript.fetch_store import fetch_store_transcript

log = create_logger(__name__)


def run_podcast_fetch_transcript(podcast_episode_transcript_fetches_id: int) -> None:
    """Fetch a completed episode transcripts from Speech API for story."""

    if isinstance(podcast_episode_transcript_fetches_id, bytes):
        podcast_episode_transcript_fetches_id = decode_object_from_bytes_if_needed(
            podcast_episode_transcript_fetches_id)
    podcast_episode_transcript_fetches_id = int(podcast_episode_transcript_fetches_id)

    if not podcast_episode_transcript_fetches_id:
        fatal_error("'podcast_episode_transcript_fetches_id' is unset.")

    db = connect_to_db()

    log.info(f"Fetching transcript for fetch ID {podcast_episode_transcript_fetches_id}...")

    try:
        stories_id = fetch_store_transcript(
            db=db,
            podcast_episode_transcript_fetches_id=podcast_episode_transcript_fetches_id,
        )

        if stories_id:
            JobBroker(queue_name='MediaWords::Job::ExtractAndVector').add_to_queue(stories_id=stories_id)

    except McPodcastFetchTranscriptSoftException as ex:
        # Soft exceptions
        log.error(f"Unable to fetch transcript for fetch ID {podcast_episode_transcript_fetches_id}: {ex}")
        raise ex

    except Exception as ex:
        # Hard and other exceptions
        fatal_error((
            f"Fatal / unknown error while fetching transcript "
            f"for ID {podcast_episode_transcript_fetches_id}: {ex}"
        ))

    log.info(f"Done fetching transcript for ID {podcast_episode_transcript_fetches_id}")


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::Podcast::FetchTranscript')
    app.start_worker(handler=run_podcast_fetch_transcript)
