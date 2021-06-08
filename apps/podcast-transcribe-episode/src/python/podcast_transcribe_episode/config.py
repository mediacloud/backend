import abc

from mediawords.util.config import env_value, file_with_env_value


class AbstractGCBucketConfig(object, metaclass=abc.ABCMeta):
    """
    Configuration of a single GCS bucket.
    """

    __slots__ = [
        '__bucket_name',
        '__path_prefix',
    ]

    def __init__(self, bucket_name: str = None, path_prefix: str = None):
        """
        Constructor.

        Test classes might decide to override those.
        """
        self.__bucket_name = bucket_name or self._default_bucket_name()
        self.__path_prefix = path_prefix or self._default_path_prefix()

    def bucket_name(self) -> str:
        return self.__bucket_name

    def path_prefix(self) -> str:
        return self.__path_prefix

    @abc.abstractmethod
    def _default_bucket_name(self) -> str:
        """Default bucket name to upload objects to / download from."""
        raise NotImplementedError

    @abc.abstractmethod
    def _default_path_prefix(self) -> str:
        """Default path prefix under which the objects are to be found."""
        raise NotImplementedError


class RawEnclosuresGCBucketConfig(AbstractGCBucketConfig):

    def _default_bucket_name(self) -> str:
        return env_value(name='MC_PODCAST_RAW_ENCLOSURES_BUCKET_NAME')

    def _default_path_prefix(self) -> str:
        return env_value(name='MC_PODCAST_RAW_ENCLOSURES_PATH_PREFIX')


class TranscodedEpisodesGCBucketConfig(AbstractGCBucketConfig):

    def _default_bucket_name(self) -> str:
        return env_value(name='MC_PODCAST_TRANSCODED_EPISODES_BUCKET_NAME')

    def _default_path_prefix(self) -> str:
        return env_value(name='MC_PODCAST_TRANSCODED_EPISODES_PATH_PREFIX')


class TranscriptsGCBucketConfig(AbstractGCBucketConfig):

    def _default_bucket_name(self) -> str:
        return env_value(name='MC_PODCAST_TRANSCRIPTS_BUCKET_NAME')

    def _default_path_prefix(self) -> str:
        return env_value(name='MC_PODCAST_TRANSCRIPTS_PATH_PREFIX')


class GCAuthConfig(object):

    # noinspection PyMethodMayBeStatic
    def json_file(self) -> str:
        """Path to Google Cloud authentication JSON file."""
        return file_with_env_value(name='MC_PODCAST_AUTH_JSON_BASE64', encoded_with_base64=True)


class PodcastTranscribeEpisodeConfig(object):
    """Podcast transcription configuration."""

    # noinspection PyMethodMayBeStatic
    def max_enclosure_size(self) -> int:
        """Max. enclosure size (in bytes) that we're willing to download."""
        return 1024 * 1024 * 500

    # noinspection PyMethodMayBeStatic
    def max_duration(self) -> int:
        """Max. podcast episode duration (in seconds) to submit for transcription."""
        return 60 * 60 * 2

    # noinspection PyMethodMayBeStatic
    def gc_auth(self) -> GCAuthConfig:
        """Google Cloud (both Storage and Speech API) authentication configuration."""
        return GCAuthConfig()

    # noinspection PyMethodMayBeStatic
    def raw_enclosures(self) -> AbstractGCBucketConfig:
        """Configuration for GCS bucket where raw enclosures will be stored."""
        return RawEnclosuresGCBucketConfig()

    # noinspection PyMethodMayBeStatic
    def transcoded_episodes(self) -> AbstractGCBucketConfig:
        """Configuration for GCS bucket where transcoded, Speech API-ready episodes will be stored."""
        return TranscodedEpisodesGCBucketConfig()

    # noinspection PyMethodMayBeStatic
    def transcripts(self) -> AbstractGCBucketConfig:
        """Configuration for GCS bucket where JSON transcripts will be stored."""
        return TranscriptsGCBucketConfig()
