import os
import tempfile
from typing import Optional

# noinspection PyPackageRequirements
from temporal.workflow import Workflow

from mediawords.db import connect_to_db, DatabaseHandler
from mediawords.dbi.downloads import create_download_for_new_story
from mediawords.dbi.downloads.store import store_content
from mediawords.job import JobBroker
from mediawords.util.parse_json import encode_json, decode_json
from mediawords.util.config.common import DatabaseConfig, ConnectRetriesConfig, RabbitMQConfig
from mediawords.util.identify_language import identification_would_be_reliable, language_code_for_text
from mediawords.util.parse_html import html_strip

from .config import (
    PodcastGCRawEnclosuresBucketConfig,
    PodcastGCTranscodedEpisodesBucketConfig,
    MAX_ENCLOSURE_SIZE,
    MAX_DURATION, PodcastGCTranscriptsBucketConfig,
)
from .exceptions import SoftException, HardException
from .fetch_episode.enclosure import podcast_viable_enclosure_for_story, StoryEnclosure
from .fetch_episode.fetch_url import fetch_big_file
from .fetch_episode.gcs_store import GCSStore
from .fetch_episode.bcp47_lang import iso_639_1_code_to_bcp_47_identifier
from .fetch_episode.media_info import MediaFileInfoAudioStream, media_file_info
from .fetch_episode.speech_api import submit_transcribe_operation, fetch_transcript
from .fetch_episode.transcode import maybe_transcode_file
from .fetch_episode.transcript import Transcript
from .shared import (
    AbstractPodcastTranscribeWorkflow,
    AbstractPodcastTranscribeActivities,
    DEFAULT_RETRY_PARAMETERS,
)


def connect_to_db_or_raise() -> DatabaseHandler:
    """
    Shorthand for connect_to_db() with its own retries and fatal_error() disabled.

    By default, connect_to_db() will attempt connecting to PostgreSQL a few times and would call fatal_error() on
    failures and stop the whole process.

    We leave retrying and failure handling to Temporal here so we disable all of this functionality.

    FIXME probably move to "common".
    """
    return connect_to_db(
        db_config=DatabaseConfig(
            retries=ConnectRetriesConfig(
                max_attempts=1,
                fatal_error_on_failure=False,
            )
        )
    )


# FIXME in the example the activities implementation *was not* inheriting from the interface
class PodcastTranscribeActivities(AbstractPodcastTranscribeActivities):
    """Activities implementation."""

    async def identify_story_bcp47_language_code(self, stories_id: int) -> Optional[str]:
        db = connect_to_db_or_raise()

        try:
            story = db.find_by_id(table='stories', object_id=stories_id)
        except Exception as ex:
            raise SoftException(f"Database failed when fetching story {stories_id}: {ex}")

        if not story:
            raise SoftException(f"Story {stories_id} was not found.")

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

        return bcp_47_language_code

    async def determine_best_enclosure(self, stories_id: int) -> Optional[StoryEnclosure]:

        db = connect_to_db_or_raise()

        # Find the enclosure that might work the best
        best_enclosure = podcast_viable_enclosure_for_story(db=db, stories_id=stories_id)
        if not best_enclosure:
            # FIXME possibly return None here?
            raise SoftException(f"There were no viable enclosures found for story {stories_id}")

        if best_enclosure.length:
            if best_enclosure.length > MAX_ENCLOSURE_SIZE:
                # FIXME possibly return None here?
                raise SoftException(f"Chosen enclosure {best_enclosure} is too big.")

        return best_enclosure

    async def fetch_enclosure_to_gcs(self, stories_id: int, enclosure: StoryEnclosure) -> None:

        with tempfile.TemporaryDirectory(prefix='fetch_enclosure_to_gcs') as temp_dir:
            raw_enclosure_path = os.path.join(temp_dir, 'raw_enclosure')
            fetch_big_file(url=enclosure.url, dest_file=raw_enclosure_path, max_size=MAX_ENCLOSURE_SIZE)

            if os.stat(raw_enclosure_path).st_size == 0:
                # Might happen with misconfigured webservers
                raise SoftException(f"Fetched file {raw_enclosure_path} is empty.")

            gcs = GCSStore(bucket_config=PodcastGCRawEnclosuresBucketConfig())
            gcs.upload_object(local_file_path=raw_enclosure_path, object_id=str(stories_id))

    async def fetch_transcode_store_episode(self, stories_id: int) -> MediaFileInfoAudioStream:

        with tempfile.TemporaryDirectory(prefix='fetch_transcode_store_episode') as temp_dir:
            raw_enclosure_path = os.path.join(temp_dir, 'raw_enclosure')

            gcs_raw_enclosures = GCSStore(bucket_config=PodcastGCRawEnclosuresBucketConfig())
            gcs_raw_enclosures.download_object(
                object_id=str(stories_id),
                local_file_path=raw_enclosure_path,
            )
            del gcs_raw_enclosures

            if os.stat(raw_enclosure_path).st_size == 0:
                # If somehow the file from GCS ended up being of zero length, then this is very much unexpected
                raise HardException(f"Fetched file {raw_enclosure_path} is empty.")

            transcoded_episode_path = os.path.join(temp_dir, 'transcoded_episode')

            raw_enclosure_transcoded = maybe_transcode_file(
                input_file=raw_enclosure_path,
                maybe_output_file=transcoded_episode_path,
            )
            if not raw_enclosure_transcoded:
                transcoded_episode_path = raw_enclosure_path

            del raw_enclosure_path

            gcs_transcoded_episodes = GCSStore(bucket_config=PodcastGCTranscodedEpisodesBucketConfig())
            gcs_transcoded_episodes.upload_object(local_file_path=transcoded_episode_path, object_id=str(stories_id))

            # (Re)read the properties of either the original or the transcoded file
            media_info = media_file_info(media_file_path=transcoded_episode_path)
            best_audio_stream = media_info.best_supported_audio_stream()

            if not best_audio_stream.audio_codec_class:
                raise HardException("Best audio stream doesn't have audio class set")

            return best_audio_stream

    async def submit_transcribe_operation(self,
                                          stories_id: int,
                                          episode_metadata: MediaFileInfoAudioStream,
                                          bcp47_language_code: str) -> str:

        if not episode_metadata.audio_codec_class:
            raise HardException("Best audio stream doesn't have audio class set")

        gcs_transcoded_episodes = GCSStore(bucket_config=PodcastGCTranscodedEpisodesBucketConfig())
        gs_uri = gcs_transcoded_episodes.object_uri(object_id=str(stories_id))

        speech_operation_id = submit_transcribe_operation(
            gs_uri=gs_uri,
            episode_metadata=episode_metadata,
            bcp47_language_code=bcp47_language_code,
        )

        return speech_operation_id

    async def fetch_store_raw_transcript_json(self, stories_id: int, speech_operation_id: str) -> None:
        transcript = fetch_transcript(speech_operation_id=speech_operation_id)
        if transcript is None:
            raise SoftException(f"Speech operation with ID '{speech_operation_id}' hasn't been completed yet.")

        transcript_json = encode_json(transcript.to_dict())

        with tempfile.TemporaryDirectory(prefix='fetch_store_raw_transcript_json') as temp_dir:
            transcript_json_path = os.path.join(temp_dir, 'transcript.json')

            with open(transcript_json_path, 'w') as f:
                f.write(transcript_json)

            gcs = GCSStore(bucket_config=PodcastGCTranscriptsBucketConfig())
            gcs.upload_object(local_file_path=transcript_json_path, object_id=str(stories_id))

    async def fetch_store_transcript(self, stories_id: int) -> None:
        with tempfile.TemporaryDirectory(prefix='fetch_store_transcript') as temp_dir:
            transcript_json_path = os.path.join(temp_dir, 'transcript.json')

            gcs = GCSStore(bucket_config=PodcastGCTranscriptsBucketConfig())
            gcs.download_object(object_id=str(stories_id), local_file_path=transcript_json_path)

            with open(transcript_json_path, 'w') as f:
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

        download = create_download_for_new_story(db=db, story=story, feed=feed)

        text = transcript.download_text_from_transcript()

        # Store as a raw download and then let "extract-and-vector" app "extract" the stored text later
        store_content(db=db, download=download, content=text)

    async def add_to_extraction_queue(self, stories_id: int) -> None:
        job_broker = JobBroker(
            queue_name='MediaWords::Job::ExtractAndVector',
            rabbitmq_config=RabbitMQConfig(

                # Keep RabbitMQ's timeout smaller than the action's "start_to_close_timeout"
                timeout=60,

                # Disable retries as Temporal will be the one that does all the retrying
                retries=None,
            ),
        )
        job_broker.add_to_queue(stories_id=stories_id)


class PodcastTranscribeWorkflow(AbstractPodcastTranscribeWorkflow):
    """Workflow implementation."""

    def __init__(self):
        self.activities: AbstractPodcastTranscribeActivities = Workflow.new_activity_stub(
            activities_cls=AbstractPodcastTranscribeActivities,
            retry_parameters=DEFAULT_RETRY_PARAMETERS,
        )

    async def transcribe_episode(self, stories_id: int) -> None:

        bcp47_language_code = await self.activities.identify_story_bcp47_language_code(stories_id=stories_id)
        if bcp47_language_code is None:
            # Default to English in case there wasn't enough sizable text in title / description to make a good guess
            bcp47_language_code = 'en'

        enclosure = await self.activities.determine_best_enclosure(stories_id=stories_id)
        if not enclosure:
            # FIXME what do we do if there's no viable enclosure? Nothing?
            return

        await self.activities.fetch_enclosure_to_gcs(stories_id=stories_id, enclosure=enclosure)

        episode_metadata = await self.activities.fetch_transcode_store_episode(stories_id=stories_id)

        if episode_metadata.duration > MAX_DURATION:
            # FIXME log that the episode duration exceeded the maximum allowed duration
            # f"Story's {stories_id} podcast episode is too long ({episode_metadata.duration} seconds)."
            return

        speech_operation_id = await self.activities.submit_transcribe_operation(
            stories_id=stories_id,
            episode_metadata=episode_metadata,
            bcp47_language_code=bcp47_language_code,
        )

        await Workflow.sleep(int(episode_metadata.duration * 1.1))

        # FIXME get the retries right here
        # FIXME if the operation with a given ID is not found, re-submit the transcription operation
        await self.activities.fetch_store_raw_transcript_json(
            stories_id=stories_id,
            speech_operation_id=speech_operation_id,
        )

        await self.activities.fetch_store_transcript(stories_id=stories_id)

        await self.activities.add_to_extraction_queue(stories_id=stories_id)
