# FIXME remove unused tables
# FIXME post-init validation of dataclasses (https://docs.python.org/3/library/dataclasses.html#post-init-processing)
# FIXME workflow logger

import dataclasses
import enum
from datetime import timedelta
from typing import Optional

# noinspection PyPackageRequirements
from furl import furl
# noinspection PyPackageRequirements
from temporal.activity_method import activity_method, RetryParameters
# noinspection PyPackageRequirements
from temporal.workflow import workflow_method

from mediawords.util.url import is_http_url

TASK_QUEUE = "podcast-transcribe-episode"
"""Temporal task queue."""

NAMESPACE = "default"
"""Temporal namespace."""

# FIXME different retry parameters for various actions
RETRY_PARAMETERS = RetryParameters(
    initial_interval=timedelta(seconds=1),
    maximum_interval=timedelta(seconds=100),
    backoff_coefficient=2,
    maximum_attempts=500,
)


@enum.unique
class AudioCodec(enum.Enum):
    """
    Audio file codec that's supported by Google Speech API.

    https://cloud.google.com/speech-to-text/docs/reference/rpc/google.cloud.speech.v1p1beta1
    """
    LINEAR16 = 'LINEAR16',
    FLAC = 'FLAC'
    MULAW = 'MULAW'
    OGG_OPUS = 'OGG_OPUS'
    MP3 = 'MP3'


@dataclasses.dataclass(frozen=True)
class EpisodeMetadata(object):
    """Metadata about an episode to be transcribed."""

    duration: int
    """Episode's duration in seconds."""

    codec: AudioCodec
    """Episode's codec."""

    sample_rate: int
    """Episode's sample rate (Hz) as determined by transcoder, e.g. 44100."""


@dataclasses.dataclass
class StoryEnclosure(object):
    """Single story enclosure derived from feed's <enclosure /> element."""

    __MP3_MIME_TYPES = {'audio/mpeg', 'audio/mpeg3', 'audio/mp3', 'audio/x-mpeg-3'}
    """MIME types which MP3 files might have."""

    url: str
    """Enclosure's URL, e.g. 'https://www.example.com/episode.mp3'."""

    mime_type: Optional[str]
    """Enclosure's reported MIME type, or None if it wasn't reported; e.g. 'audio/mpeg'."""

    length: Optional[int]
    """Enclosure's reported length in bytes, or None if it wasn't reported."""

    def mime_type_is_mp3(self) -> bool:
        """Return True if declared MIME type is one of the MP3 ones."""
        if self.mime_type:
            if self.mime_type.lower() in self.__MP3_MIME_TYPES:
                return True
        return False

    def mime_type_is_audio(self) -> bool:
        """Return True if declared MIME type is an audio type."""
        if self.mime_type:
            if self.mime_type.lower().startswith('audio/'):
                return True
        return False

    def mime_type_is_video(self) -> bool:
        """Return True if declared MIME type is a video type."""
        if self.mime_type:
            if self.mime_type.lower().startswith('video/'):
                return True
        return False

    def url_path_has_mp3_extension(self) -> bool:
        """Return True if URL's path has .mp3 extension."""
        if is_http_url(self.url):
            uri = furl(self.url)
            if '.mp3' in str(uri.path).lower():
                return True
        return False


class AbstractPodcastTranscribeActivities(object):
    """Activities interface."""

    # FIXME timeouts and retries of every action

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=5),
        # schedule_to_close_timeout=timedelta(seconds=5),
        retry_parameters=RETRY_PARAMETERS,
    )
    async def identify_story_bcp47_language_code(self, stories_id: int) -> Optional[str]:
        """
        Guess BCP 47 language code of a story, e.g. 'en-US'.

        https://cloud.google.com/speech-to-text/docs/languages
        """
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=5),
        # schedule_to_close_timeout=timedelta(seconds=5),
        retry_parameters=RETRY_PARAMETERS,
    )
    async def determine_best_enclosure(self, stories_id: int) -> Optional[StoryEnclosure]:
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=5),
        # schedule_to_close_timeout=timedelta(seconds=5),
        retry_parameters=RETRY_PARAMETERS,
    )
    async def fetch_store_enclosure(self, stories_id: int, enclosure: StoryEnclosure) -> None:
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=5),
        # schedule_to_close_timeout=timedelta(seconds=5),
        retry_parameters=RETRY_PARAMETERS,
    )
    async def fetch_transcode_store_episode(self, stories_id: int) -> EpisodeMetadata:
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=5),
        # schedule_to_close_timeout=timedelta(seconds=5),
        retry_parameters=RETRY_PARAMETERS,
    )
    async def submit_transcribe_operation(self,
                                          stories_id: int,
                                          episode_metadata: EpisodeMetadata,
                                          bcp47_language_code: str) -> str:
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=5),
        # schedule_to_close_timeout=timedelta(seconds=5),
        retry_parameters=RETRY_PARAMETERS,
    )
    async def fetch_store_raw_transcript_json(self, stories_id: int, speech_operation_id: str) -> None:
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=5),
        # schedule_to_close_timeout=timedelta(seconds=5),
        retry_parameters=RETRY_PARAMETERS,
    )
    async def fetch_store_transcript(self, stories_id: int) -> None:
        raise NotImplementedError


class AbstractPodcastTranscribeWorkflow(object):
    """Workflow interface."""

    @workflow_method(task_queue=TASK_QUEUE)
    async def transcribe_episode(self, stories_id: int) -> None:
        raise NotImplementedError
