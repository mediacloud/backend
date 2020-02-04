import time

from mediawords.dbi.downloads.store import fetch_content
from mediawords.util.log import create_logger

from podcast_fetch_transcript.fetch import fetch_transcript
from podcast_fetch_transcript.store import store_transcript

from .setup_fetch import AbstractFetchTranscriptTestCase

log = create_logger(__name__)


class FullChainTestCase(AbstractFetchTranscriptTestCase):
    """Test the full chain against a small audio file."""

    @classmethod
    def input_media_path(cls) -> str:
        # Run the test with AAC file to test out both transcoding to FLAC and whether Speech API can transcribe audio
        # files after lossy -> lossless transcoding
        return '/opt/mediacloud/tests/data/media-samples/samples/kim_kardashian-aac.m4a'

    @classmethod
    def input_media_mime_type(cls) -> str:
        return 'audio/mp4'

    @classmethod
    def story_title_description(cls) -> str:
        # 'label' is important as it will be stored in both stories.title and stories.description, which in turn will be
        # used to guess the probable language of the podcast episode
        return 'keeping up with Kardashians'

    @classmethod
    def retries_per_step(cls) -> int:
        return 120

    @classmethod
    def seconds_between_retries(cls) -> float:
        return 0.5

    def test_full_chain(self):
        transcript = None
        for x in range(1, 60 + 1):
            log.info(f"Waiting for transcript to be finished (#{x})...")

            podcast_episode_transcript_fetches_id = self.transcript_fetches[0]['podcast_episode_transcript_fetches_id']
            transcript = fetch_transcript(
                db=self.db,
                podcast_episode_transcript_fetches_id=podcast_episode_transcript_fetches_id
            )
            if transcript:
                log.info("Transcript is here!")
                break

            time.sleep(2)

        assert transcript
        assert transcript.stories_id
        assert len(transcript.utterances) == 1
        assert len(transcript.utterances[0].alternatives) == 1
        assert 'kim kardashian' in transcript.utterances[0].alternatives[0].text.lower()

        downloads_id = store_transcript(db=self.db, transcript=transcript)

        download = self.db.find_by_id(table='downloads', object_id=downloads_id)

        raw_download = fetch_content(db=self.db, download=download)
        assert raw_download
        assert 'kim kardashian' in raw_download.lower()
