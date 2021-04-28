import abc

from mediawords.util.config import env_value, file_with_env_value

MAX_ENCLOSURE_SIZE = 1024 * 1024 * 500
"""Max. enclosure size (in bytes) that we're willing to download."""

MAX_DURATION = 60 * 60 * 2
"""Max. podcast episode duration (in seconds) to submit for transcription."""


class AbstractGCBucketConfig(object, metaclass=abc.ABCMeta):
    """
    Configuration of a single GCS bucket.
    """

    @abc.abstractmethod
    def bucket_name(self) -> str:
        """Bucket name to upload objects to / download from."""
        raise NotImplementedError

    @abc.abstractmethod
    def path_prefix(self) -> str:
        """Path prefix under which the objects are to be found."""
        raise NotImplementedError


class GCAuthConfig(object):
    """Google Cloud (both Storage and Speech API) authentication configuration."""

    @classmethod
    def gc_auth_json_file(cls) -> str:
        """Return path to Google Cloud authentication JSON file."""
        return file_with_env_value(name='MC_PODCAST_GC_AUTH_JSON_BASE64', encoded_with_base64=True)


class RawEnclosuresBucketConfig(AbstractGCBucketConfig):
    """Configuration for GCS bucket where raw enclosures will be stored."""

    def bucket_name(self) -> str:
        return env_value(name='MC_PODCAST_RAW_ENCLOSURES_BUCKET_NAME')

    def path_prefix(self) -> str:
        return env_value(name='MC_PODCAST_RAW_ENCLOSURES_PATH_PREFIX')


class TranscodedEpisodesBucketConfig(AbstractGCBucketConfig):
    """Configuration for GCS bucket where transcoded, Speech API-ready episodes will be stored."""

    def bucket_name(self) -> str:
        return env_value(name='MC_PODCAST_TRANSCODED_EPISODES_BUCKET_NAME')

    def path_prefix(self) -> str:
        return env_value(name='MC_PODCAST_TRANSCODED_EPISODES_PATH_PREFIX')


class TranscriptsBucketConfig(AbstractGCBucketConfig):
    """Configuration for GCS bucket where JSON transcripts will be stored."""

    def bucket_name(self) -> str:
        return env_value(name='MC_PODCAST_TRANSCRIPTS_BUCKET_NAME')

    def path_prefix(self) -> str:
        return env_value(name='MC_PODCAST_TRANSCRIPTS_PATH_PREFIX')
