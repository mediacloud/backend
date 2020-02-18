from typing import Optional

from mediawords.db import DatabaseHandler
from podcast_fetch_transcript.fetch_store import fetch_store_transcript

from podcast_fetch_transcript.handler import AbstractHandler
from podcast_fetch_transcript.transcript import Transcript, Utterance, UtteranceAlternative

from .setup_mock_fetch_store import AbstractMockFetchStoreTestCase


class MockTranscriptSuccessHandler(AbstractHandler):
    """Mock handler that fetches the transcription successfully."""

    @classmethod
    def fetch_transcript(cls, db: DatabaseHandler, podcast_episode_transcript_fetches_id: int) -> Optional[Transcript]:
        return Transcript(
            stories_id=42,
            utterances=[
                Utterance(
                    alternatives=[
                        UtteranceAlternative(
                            text='Kim Kardashian.',
                            confidence=1.00,
                        )
                    ],
                    bcp47_language_code='en-US',
                ),
            ]
        )

    @classmethod
    def store_transcript(cls, db: DatabaseHandler, transcript: Transcript) -> int:
        return transcript.stories_id


class MockSuccessTestCase(AbstractMockFetchStoreTestCase):

    def test_success(self):
        handler = MockTranscriptSuccessHandler()

        stories_id = fetch_store_transcript(
            db=self.db,
            podcast_episode_transcript_fetches_id=self.podcast_episode_transcript_fetches_id,
            handler=handler,
        )
        assert stories_id

        transcript_fetches = self.db.select(table='podcast_episode_transcript_fetches', what_to_select='*').hashes()
        assert len(transcript_fetches) == 1

        transcript_fetch = transcript_fetches[0]
        assert transcript_fetch['fetched_at']
        assert transcript_fetch['result'] == 'success'
        assert not transcript_fetch['error_message']
