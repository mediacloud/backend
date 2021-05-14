import os
import tempfile
from typing import Optional

# noinspection PyPackageRequirements
from temporal.workflow import Workflow

from mediawords.dbi.downloads.store import store_content
from mediawords.job import JobBroker
from mediawords.util.parse_json import encode_json, decode_json
from mediawords.util.config.common import RabbitMQConfig
from mediawords.util.identify_language import identification_would_be_reliable, language_code_for_text
from mediawords.util.log import create_logger
from mediawords.util.parse_html import html_strip
from mediawords.util.url import get_url_host

from .config import (
    RawEnclosuresBucketConfig,
    TranscodedEpisodesBucketConfig,
    TranscriptsBucketConfig,
    MAX_ENCLOSURE_SIZE,
    MAX_DURATION,
)
from .db_or_raise import connect_to_db_or_raise
from .exceptions import McProgrammingError, McTransientError, McPermanentError
from .enclosure import viable_story_enclosure, StoryEnclosure, StoryEnclosureDict
from .fetch_url import fetch_big_file
from .gcs_store import GCSStore
from .bcp47_lang import iso_639_1_code_to_bcp_47_identifier
from .media_info import MediaFileInfoAudioStream, media_file_info, MediaFileInfoAudioStreamDict
from .speech_api import submit_transcribe_operation, fetch_transcript
from .transcode import maybe_transcode_file
from .transcript import Transcript
from .workflow_interface import AbstractPodcastTranscribeWorkflow, AbstractPodcastTranscribeActivities

log = create_logger(__name__)


class PodcastTranscribeActivities(AbstractPodcastTranscribeActivities):
    """Activities implementation."""

    async def identify_story_bcp47_language_code(self, stories_id: int) -> Optional[str]:
        log.info(f"Identifying story language for story {stories_id}...")

        db = connect_to_db_or_raise()

        story = db.find_by_id(table='stories', object_id=stories_id)
        if not story:
            raise McPermanentError(f"Story {stories_id} was not found.")

        # Podcast episodes typically come with title and description set so try guessing from that
        story_title = story['title']
        story_description = html_strip(story['description'])
        sample_text = f"{story_title}\n{story_description}"

        bcp_47_language_code = None
        if identification_would_be_reliable(text=sample_text):
            iso_639_1_language_code = language_code_for_text(text=sample_text)

            # Convert to BCP 47 identifier
            bcp_47_language_code = iso_639_1_code_to_bcp_47_identifier(
                iso_639_1_code=iso_639_1_language_code,
                url_hint=story['url'],
            )

        log.info(f"Language code for story {stories_id} is {bcp_47_language_code}")

        return bcp_47_language_code

    async def determine_best_enclosure(self, stories_id: int) -> Optional[StoryEnclosureDict]:

        log.info(f"Determining best enclosure for story {stories_id}...")

        db = connect_to_db_or_raise()

        # Find the enclosure that might work the best
        best_enclosure = viable_story_enclosure(db=db, stories_id=stories_id)
        if not best_enclosure:
            raise McPermanentError(f"There were no viable enclosures found for story {stories_id}")

        if best_enclosure.length:
            if best_enclosure.length > MAX_ENCLOSURE_SIZE:
                raise McPermanentError(f"Chosen enclosure {best_enclosure} is too big.")

        log.info(f"Done determining best enclosure for story {stories_id}")
        log.debug(f"Best enclosure for story {stories_id}: {best_enclosure}")

        return best_enclosure.to_dict()

    async def fetch_enclosure_to_gcs(self, stories_id: int, enclosure: StoryEnclosureDict) -> None:

        log.info(f"Fetching enclosure to GCS for story {stories_id}")
        log.debug(f"Best enclosure for story {stories_id}: {enclosure}")

        enclosure = StoryEnclosure.from_dict(enclosure)

        with tempfile.TemporaryDirectory(prefix='fetch_enclosure_to_gcs') as temp_dir:
            raw_enclosure_path = os.path.join(temp_dir, 'raw_enclosure')
            fetch_big_file(url=enclosure.url, dest_file=raw_enclosure_path, max_size=MAX_ENCLOSURE_SIZE)

            if os.stat(raw_enclosure_path).st_size == 0:
                # Might happen with misconfigured webservers
                raise McPermanentError(f"Fetched file {raw_enclosure_path} is empty.")

            gcs = GCSStore(bucket_config=RawEnclosuresBucketConfig())
            gcs.upload_object(local_file_path=raw_enclosure_path, object_id=str(stories_id))

        log.info(f"Done fetching enclosure to GCS for story {stories_id}")

    async def fetch_transcode_store_episode(self, stories_id: int) -> MediaFileInfoAudioStreamDict:

        log.info(f"Fetching, transcoding, storing episode for story {stories_id}...")

        with tempfile.TemporaryDirectory(prefix='fetch_transcode_store_episode') as temp_dir:
            raw_enclosure_path = os.path.join(temp_dir, 'raw_enclosure')

            gcs_raw_enclosures = GCSStore(bucket_config=RawEnclosuresBucketConfig())
            gcs_raw_enclosures.download_object(
                object_id=str(stories_id),
                local_file_path=raw_enclosure_path,
            )
            del gcs_raw_enclosures

            if os.stat(raw_enclosure_path).st_size == 0:
                # If somehow the file from GCS ended up being of zero length, then this is very much unexpected
                raise McProgrammingError(f"Fetched file {raw_enclosure_path} is empty.")

            transcoded_episode_path = os.path.join(temp_dir, 'transcoded_episode')

            raw_enclosure_transcoded = maybe_transcode_file(
                input_file=raw_enclosure_path,
                maybe_output_file=transcoded_episode_path,
            )
            if not raw_enclosure_transcoded:
                transcoded_episode_path = raw_enclosure_path

            del raw_enclosure_path

            gcs_transcoded_episodes = GCSStore(bucket_config=TranscodedEpisodesBucketConfig())
            gcs_transcoded_episodes.upload_object(local_file_path=transcoded_episode_path, object_id=str(stories_id))

            # (Re)read the properties of either the original or the transcoded file
            media_info = media_file_info(media_file_path=transcoded_episode_path)
            best_audio_stream = media_info.best_supported_audio_stream()

            if not best_audio_stream.audio_codec_class:
                raise McProgrammingError("Best audio stream doesn't have audio class set")

        log.info(f"Done fetching, transcoding, storing episode for story {stories_id}")
        log.debug(f"Best audio stream for story {stories_id}: {best_audio_stream}")

        return best_audio_stream.to_dict()

    async def submit_transcribe_operation(self,
                                          stories_id: int,
                                          episode_metadata: MediaFileInfoAudioStreamDict,
                                          bcp47_language_code: str) -> str:

        log.info(f"Submitting transcribe operation for story {stories_id}...")
        log.debug(f"Episode metadata for story {stories_id}: {episode_metadata}")
        log.debug(f"Language code for story {stories_id}: {bcp47_language_code}")

        episode_metadata = MediaFileInfoAudioStream.from_dict(episode_metadata)

        if not episode_metadata.audio_codec_class:
            raise McProgrammingError("Best audio stream doesn't have audio class set")

        gcs_transcoded_episodes = GCSStore(bucket_config=TranscodedEpisodesBucketConfig())
        gs_uri = gcs_transcoded_episodes.object_uri(object_id=str(stories_id))

        speech_operation_id = submit_transcribe_operation(
            gs_uri=gs_uri,
            episode_metadata=episode_metadata,
            bcp47_language_code=bcp47_language_code,
        )

        log.info(f"Done submitting transcribe operation for story {stories_id}")
        log.debug(f"Speech operation ID for story {stories_id}: {speech_operation_id}")

        return speech_operation_id

    async def fetch_store_raw_transcript_json(self, stories_id: int, speech_operation_id: str) -> None:

        log.info(f"Fetching and storing raw transcript JSON for story {stories_id}...")
        log.debug(f"Speech operation ID: {speech_operation_id}")

        transcript = fetch_transcript(speech_operation_id=speech_operation_id)
        if transcript is None:
            raise McTransientError(f"Speech operation with ID '{speech_operation_id}' hasn't been completed yet.")

        transcript_json = encode_json(transcript.to_dict())

        with tempfile.TemporaryDirectory(prefix='fetch_store_raw_transcript_json') as temp_dir:
            transcript_json_path = os.path.join(temp_dir, 'transcript.json')

            with open(transcript_json_path, 'w') as f:
                f.write(transcript_json)

            gcs = GCSStore(bucket_config=TranscriptsBucketConfig())
            gcs.upload_object(local_file_path=transcript_json_path, object_id=str(stories_id))

        log.info(f"Done fetching and storing raw transcript JSON for story {stories_id}")

    async def fetch_store_transcript(self, stories_id: int) -> None:

        log.info(f"Fetching and storing transcript for story {stories_id}...")

        with tempfile.TemporaryDirectory(prefix='fetch_store_transcript') as temp_dir:
            transcript_json_path = os.path.join(temp_dir, 'transcript.json')

            gcs = GCSStore(bucket_config=TranscriptsBucketConfig())
            gcs.download_object(object_id=str(stories_id), local_file_path=transcript_json_path)

            with open(transcript_json_path, 'r') as f:
                transcript_json = f.read()

        transcript = Transcript.from_dict(decode_json(transcript_json))

        db = connect_to_db_or_raise()

        story = db.find_by_id(table='stories', object_id=stories_id)

        feed = db.query("""
            SELECT *
            FROM feeds
            WHERE feeds_id = (
                SELECT feeds_id
                FROM feeds_stories_map
                WHERE stories_id = %(stories_id)s
            )
        """, {
            'stories_id': stories_id,
        }).hash()

        # Just like create_download_for_new_story(), it creates a new download except that it tests if such a download
        # exists first
        download = db.find_or_create(
            table='downloads',
            insert_hash={
                'feeds_id': feed['feeds_id'],
                'stories_id': story['stories_id'],
                'url': story['url'],
                'host': get_url_host(story['url']),
                'type': 'content',
                'sequence': 1,
                'state': 'success',
                'path': 'content:pending',
                'priority': 1,
                'extracted': 'f'
            },
        )

        text = transcript.download_text_from_transcript()

        # Store as a raw download and then let "extract-and-vector" app "extract" the stored text later
        store_content(db=db, download=download, content=text)

        log.info(f"Done fetching and storing transcript for story {stories_id}")

    async def add_to_extraction_queue(self, stories_id: int) -> None:

        log.info(f"Adding an extraction job for story {stories_id}...")

        job_broker = JobBroker(
            queue_name='MediaWords::Job::ExtractAndVector',
            rabbitmq_config=RabbitMQConfig(

                # Keep RabbitMQ's timeout smaller than the action's "start_to_close_timeout"
                timeout=60,

                # Disable retries as Temporal will be the one that does all the retrying
                retries=None,
            ),
        )

        # add_to_queue() is not idempotent but it's not a big deal to extract a single story twice
        job_broker.add_to_queue(stories_id=stories_id)

        log.info(f"Done adding an extraction job for story {stories_id}")


class PodcastTranscribeWorkflow(AbstractPodcastTranscribeWorkflow):
    """Workflow implementation."""

    def __init__(self):
        self.activities: AbstractPodcastTranscribeActivities = Workflow.new_activity_stub(
            activities_cls=AbstractPodcastTranscribeActivities,
            # No retry_parameters here as they get set individually in @activity_method()
        )

    async def transcribe_episode(self, stories_id: int) -> None:

        bcp47_language_code = await self.activities.identify_story_bcp47_language_code(stories_id)
        if bcp47_language_code is None:
            # Default to English in case there wasn't enough sizable text in title / description to make a good guess
            bcp47_language_code = 'en'

        enclosure = await self.activities.determine_best_enclosure(stories_id)
        if not enclosure:
            raise McPermanentError(f"No viable enclosure found for story {stories_id}")

        await self.activities.fetch_enclosure_to_gcs(stories_id, enclosure)

        episode_metadata_dict = await self.activities.fetch_transcode_store_episode(stories_id)

        episode_metadata = MediaFileInfoAudioStream.from_dict(episode_metadata_dict)

        if episode_metadata.duration > MAX_DURATION:
            raise McPermanentError(
                f"Episode's duration ({episode_metadata.duration} s) exceeds max. duration ({MAX_DURATION} s)"
            )

        speech_operation_id = await self.activities.submit_transcribe_operation(
            stories_id,
            episode_metadata_dict,
            bcp47_language_code,
        )

        # Wait for Google Speech API to finish up transcribing
        await Workflow.sleep(int(episode_metadata.duration * 1.1))

        await self.activities.fetch_store_raw_transcript_json(stories_id, speech_operation_id)

        await self.activities.fetch_store_transcript(stories_id)

        await self.activities.add_to_extraction_queue(stories_id)
