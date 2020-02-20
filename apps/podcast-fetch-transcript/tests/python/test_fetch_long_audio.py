import os
import time

import pytest

from mediawords.util.log import create_logger

from podcast_fetch_transcript.handler import DefaultHandler

from .setup_fetch import AbstractFetchTranscriptTestCase

log = create_logger(__name__)


@pytest.mark.skipif('MC_PODCAST_FETCH_TRANSCRIPT_RUN_COSTLY_TEST' not in os.environ,
                    reason="Costly; each run costs about 60 / 4 * 0.009 = $0.04")
class LongAudioTestCase(AbstractFetchTranscriptTestCase):
    """Test the full chain against a long audio file to try out whether podcast-fetch-transcript manages to back off."""

    @classmethod
    def input_media_path(cls) -> str:
        return '/opt/mediacloud/tests/data/media-samples/samples/nixon_speech-vorbis-1m.ogg'

    @classmethod
    def input_media_mime_type(cls) -> str:
        return 'audio/ogg'

    @classmethod
    def story_title_description(cls) -> str:
        return 'Resignation speech of United States President Richard Nixon'

    @classmethod
    def retries_per_step(cls) -> int:
        # Try more often and wait for longer as this is a bigger file
        return 60

    @classmethod
    def seconds_between_retries(cls) -> float:
        return 1.0

    def test_long_audio(self):
        transcript = None

        handler = DefaultHandler()

        # Input audio file is 1m0s, so wait for at least two minutes
        for x in range(1, 12 + 1):
            log.info(f"Waiting for transcript to be finished (#{x})...")

            podcast_episode_transcript_fetches_id = self.transcript_fetches[0]['podcast_episode_transcript_fetches_id']
            transcript = handler.fetch_transcript(
                db=self.db,
                podcast_episode_transcript_fetches_id=podcast_episode_transcript_fetches_id
            )

            if transcript:
                log.info("Transcript is here!")
                break

            time.sleep(5)

        print(transcript)

        assert transcript
        assert transcript.stories_id
        assert len(transcript.utterances) > 0
        assert len(transcript.utterances[0].alternatives) > 0
        assert 'evening' in transcript.utterances[0].alternatives[0].text.lower()
