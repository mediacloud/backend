#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import fatal_error

from podcast_transcribe_episode.fetch_episode.exceptions import McPodcastFetchEpisodeSoftException
from podcast_transcribe_episode.fetch_episode.fetch_and_store import fetch_and_store_episode

log = create_logger(__name__)


def run_podcast_fetch_episode(stories_id: int) -> None:
    """Fetch podcast episode for story, upload it to GCS."""

    if isinstance(stories_id, bytes):
        stories_id = decode_object_from_bytes_if_needed(stories_id)
    stories_id = int(stories_id)

    db = connect_to_db()

    log.info(f"Fetching podcast episode for story {stories_id}...")

    try:
        fetch_and_store_episode(db=db, stories_id=stories_id)

    except McPodcastFetchEpisodeSoftException as ex:
        # Soft exceptions
        log.error(f"Unable to fetch podcast episode for story {stories_id}: {ex}")
        raise ex
    except Exception as ex:
        # Hard and other exceptions
        fatal_error(f"Fatal / unknown error while fetching podcast episode for story {stories_id}: {ex}")

    log.info(f"Done fetching podcast episode for story {stories_id}")


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::Podcast::TranscribeEpisode')
    app.start_worker(handler=run_podcast_fetch_episode)
