from typing import Optional

from mediawords.db import DatabaseHandler

from podcast_fetch_transcript.fetch_store import fetch_store_transcript
from podcast_fetch_transcript.handler import AbstractHandler
from podcast_fetch_transcript.transcript import Transcript

from .setup_mock_fetch_store import AbstractMockFetchStoreTestCase


class MockTranscriptNotDoneHandler(AbstractHandler):
    """Mock handler that reports that the transcript is not yet done."""

    @classmethod
    def fetch_transcript(cls, db: DatabaseHandler, podcast_episode_transcript_fetches_id: int) -> Optional[Transcript]:
        return None

    @classmethod
    def store_transcript(cls, db: DatabaseHandler, transcript: Transcript) -> int:
        raise NotImplemented("Shouldn't be called.")


class MockFailedTestCase(AbstractMockFetchStoreTestCase):

    def test_not_done(self):
        handler = MockTranscriptNotDoneHandler()

        stories_id = fetch_store_transcript(
            db=self.db,
            podcast_episode_transcript_fetches_id=self.podcast_episode_transcript_fetches_id,
            handler=handler,
        )
        assert stories_id is None

        transcript_fetches = self.db.query("""
            SELECT *
            FROM podcast_episode_transcript_fetches
            ORDER BY podcast_episode_transcript_fetches_id
        """).hashes()
        assert len(transcript_fetches) == 2, "One fetch that's still in progress, another one added for the future."

        transcript_fetch_in_progress = transcript_fetches[0]
        assert transcript_fetch_in_progress['fetched_at']
        assert transcript_fetch_in_progress['result'] == 'in_progress'
        assert not transcript_fetch_in_progress['error_message']

        transcript_fetch_readded = transcript_fetches[1]
        assert transcript_fetch_readded['add_to_queue_at']
        assert not transcript_fetch_readded['added_to_queue_at']
        assert not transcript_fetch_readded['fetched_at']
        assert not transcript_fetch_readded['result']
        assert not transcript_fetch_readded['error_message']
