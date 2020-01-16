import time
from typing import Dict, Any

# noinspection PyPackageRequirements
from google.api_core.exceptions import ServiceUnavailable
# noinspection PyPackageRequirements
from google.cloud.speech_v1p1beta1 import SpeechClient
# noinspection PyPackageRequirements
from google.cloud.speech_v1p1beta1.proto.cloud_speech_pb2 import RecognitionConfig

from mediawords.db import DatabaseHandler
from mediawords.util.config.common import CommonConfig
from mediawords.util.log import create_logger

from podcast_submit_operation.exceptions import (
    McPodcastNoEpisodesException,
    McPodcastDatabaseErrorException,
    McPodcastInvalidInputException,
    McPodcastMisconfiguredSpeechAPIException,
    McPodcastEpisodeTooLongException,
    McPodcastSpeechAPIRequestFailedException,
)

log = create_logger(__name__)

MAX_DURATION = 60 * 60 * 2
"""Max. podcast episode duration (in seconds) to submit for transcription."""

MAX_RETRIES = 10
"""Max. number of retries for submitting a Speech API long running operation."""

DELAY_BETWEEN_RETRIES = 5
"""How long to wait (in seconds) between retries."""

FETCH_RESULTS_AT_DURATION_MULTIPLIER = 1.1
"""
How soon to expect the transcription results to become available in relation to episode's duration.

For example, if the episode's duration is 60 minutes, and the multiplier is 1.1, the transcription results fetch will
first be attempted after 60 * 1.1 = 66 minutes.
"""


class PodcastEpisode(object):
    """
    Podcast episode object.

    Postprocesses database row from "podcast_episodes" and does some extra checks.
    """
    __slots__ = [
        '__podcast_episodes_id',
        '__gcs_uri',
        '__duration',
        '__codec',
        '__audio_channel_count',
        '__sample_rate',
        '__bcp47_language_code',
    ]

    def __init__(self, db_row: Dict[str, Any]):
        self.__podcast_episodes_id = db_row['podcast_episodes_id']
        self.__gcs_uri = db_row['gcs_uri']
        self.__duration = db_row['duration']
        self.__codec = db_row['codec']
        self.__audio_channel_count = db_row['audio_channel_count']
        self.__sample_rate = db_row['sample_rate']
        self.__bcp47_language_code = db_row['bcp47_language_code']

    @property
    def podcast_episodes_id(self) -> int:
        return self.__podcast_episodes_id

    @property
    def gcs_uri(self) -> str:
        if not self.__gcs_uri.startswith('gs://'):
            raise McPodcastInvalidInputException("Google Cloud Storage URI doesn't have gs:// prefix.")
        return self.__gcs_uri

    @property
    def duration(self) -> int:
        if not self.__duration:
            raise McPodcastInvalidInputException("Duration is unset or zero.")
        return self.__duration

    @property
    def codec(self) -> RecognitionConfig.AudioEncoding:
        if self.__codec not in RecognitionConfig.AudioEncoding:
            raise McPodcastInvalidInputException(f"Invalid codec '{self.__codec}'.")
        return RecognitionConfig.AudioEncoding[self.__codec]

    @property
    def audio_channel_count(self) -> int:
        if not self.__audio_channel_count:
            raise McPodcastInvalidInputException("Audio channel count is unset or zero.")
        return self.__audio_channel_count

    @property
    def sample_rate(self) -> int:
        if not self.__sample_rate:
            raise McPodcastInvalidInputException("Sample rate is unset or zero.")
        return self.__sample_rate

    @property
    def bcp47_language_code(self) -> str:
        if '-' not in self.__bcp47_language_code and self.__bcp47_language_code != 'zh':
            raise McPodcastInvalidInputException(f"Invalid BCP 47 language code '{self.__bcp47_language_code}'.")
        return self.__bcp47_language_code


def submit_transcribe_operation(db: DatabaseHandler, stories_id: int) -> None:
    # Try to fetch the episode
    try:
        podcast_episodes = db.select(
            table='podcast_episodes',
            what_to_select='*',
            condition_hash={'stories_id': stories_id},
        ).hashes()

    except Exception as ex:
        raise McPodcastDatabaseErrorException(f"Unable to fetch story's {stories_id} podcast episodes: {ex}")

    if not podcast_episodes:
        raise McPodcastNoEpisodesException(f"There are no podcast episodes for story {stories_id}")

    if len(podcast_episodes) > 1:
        # That's very weird, there should be only one episode per story
        raise McPodcastDatabaseErrorException(f"There's more than one podcast episode for story {stories_id}")

    try:
        episode = PodcastEpisode(db_row=podcast_episodes[0])
    except Exception as ex:
        raise McPodcastInvalidInputException(f"Invalid episode for story {stories_id}: {ex}")

    if episode.duration > MAX_DURATION:
        raise McPodcastEpisodeTooLongException(
            f"Story's {stories_id} podcast episode is too long ({episode.duration} seconds)."
        )

    try:
        common_config = CommonConfig()
        google_cloud_config = common_config.google_cloud()
        client = SpeechClient.from_service_account_json(google_cloud_config.auth_json_path())
    except Exception as ex:
        raise McPodcastMisconfiguredSpeechAPIException(f"Unable to create Speech API client: {ex}")

    try:
        config = RecognitionConfig(
            encoding=episode.codec,
            sample_rate_hertz=episode.sample_rate,
            # We always set the channel count to 1 and disable separate recognition per channel as our inputs are simply
            # stereo audio files and do not have separate speakers per audio channel.
            audio_channel_count=1,
            enable_separate_recognition_per_channel=False,
            language_code=episode.bcp47_language_code,
            alternative_language_codes=[
                # FIXME add all Chinese variants
                # FIXME add Mexican Spanish variants
            ],

            speech_contexts=[
                # Speech API works pretty well without custom contexts
            ],
            # Don't care that much about word confidence
            enable_word_confidence=False,
            # Punctuation doesn't work that well but we still enable it here
            enable_automatic_punctuation=True,
            # Not setting 'model' as 'use_enhanced' will then choose the best model for us
            # Using enhanced (more expensive) model, where available
            use_enhanced=True,
        )
    except Exception as ex:
        raise McPodcastMisconfiguredSpeechAPIException(f"Unable to initialize Speech API configuration: {ex}")

    log.info(f"Submitting a Speech API operation for story {stories_id}...")
    speech_operation = None
    for attempt in range(1, MAX_RETRIES + 1):

        if attempt > 1:
            log.warning(f"Waiting for {DELAY_BETWEEN_RETRIES} seconds and retrying #{attempt}...")
            time.sleep(DELAY_BETWEEN_RETRIES)

        try:
            speech_operation = client.long_running_recognize(config=config, audio={"uri": episode.gcs_uri})
        except ServiceUnavailable as ex:
            # Speech API sometimes throws:
            #
            #   google.api_core.exceptions.ServiceUnavailable: 503 failed to connect to all addresses
            #
            log.error(f"Unable to submit an operation because service is unavailable: {ex}")
        except Exception as ex:
            raise McPodcastSpeechAPIRequestFailedException(f"Unable to submit a Speech API operation: {ex}")
        else:
            break

    if not speech_operation:
        raise McPodcastSpeechAPIRequestFailedException(f"Ran out of retries while submitting Speech API operation.")

    try:
        # We get the operation name in a try-except block because accessing it is not that well documented, so Google
        # might change the property names whenever they please and we wouldn't necessarily notice otherwise
        operation_id = speech_operation.operation.name
        if not operation_id:
            raise McPodcastMisconfiguredSpeechAPIException(f"Operation name is empty.")
    except Exception as ex:
        raise McPodcastMisconfiguredSpeechAPIException(f"Unable to get operation name: {ex}")

    log.info(f"Submitted Speech API operation '{operation_id}' for story {stories_id}")

    try:
        fetch_results_interval = f"{int(episode.duration + FETCH_RESULTS_AT_DURATION_MULTIPLIER)} seconds"
        db.query("""
            INSERT INTO podcast_episode_operations (
                stories_id,
                podcast_episodes_id,
                speech_operation_id,
                fetch_results_at
            ) VALUES (
                %(stories_id)s,
                %(podcast_episodes_id)s,
                %(speech_operation_id)s,
                NOW() + INTERVAL %(fetch_results_interval)s
            )
        """, {
            'stories_id': stories_id,
            'podcast_episodes_id': episode.podcast_episodes_id,
            'speech_operation_id': operation_id,
            'fetch_results_interval': fetch_results_interval,
        })
    except Exception as ex:
        raise McPodcastDatabaseErrorException(f"Unable to add operation to the database: {ex}")
