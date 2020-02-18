from typing import Optional

import pytest

from mediawords.db import DatabaseHandler

from podcast_fetch_transcript.exceptions import McPodcastFetchTranscriptHardException
from podcast_fetch_transcript.fetch_store import fetch_store_transcript
from podcast_fetch_transcript.handler import AbstractHandler
from podcast_fetch_transcript.transcript import Transcript

from .setup_mock_fetch_store import AbstractMockFetchStoreTestCase


class MockTranscriptErrorWithExceptionHandler(AbstractHandler):
    """Mock handler that fails the transcription with soft error."""

    @classmethod
    def fetch_transcript(cls, db: DatabaseHandler, podcast_episode_transcript_fetches_id: int) -> Optional[Transcript]:
        raise McPodcastFetchTranscriptHardException("Some sort of a permanent problem")

    @classmethod
    def store_transcript(cls, db: DatabaseHandler, transcript: Transcript) -> int:
        raise NotImplemented("Shouldn't be called.")


class MockErrorTestCase(AbstractMockFetchStoreTestCase):

    def test_error(self):
        handler = MockTranscriptErrorWithExceptionHandler()

        with pytest.raises(McPodcastFetchTranscriptHardException):
            fetch_store_transcript(
                db=self.db,
                podcast_episode_transcript_fetches_id=self.podcast_episode_transcript_fetches_id,
                handler=handler,
            )

        transcript_fetches = self.db.select(table='podcast_episode_transcript_fetches', what_to_select='*').hashes()
        assert len(transcript_fetches) == 1

        transcript_fetch = transcript_fetches[0]
        assert transcript_fetch['fetched_at']
        assert transcript_fetch['result'] == 'error'
        assert 'permanent problem' in transcript_fetch['error_message']
