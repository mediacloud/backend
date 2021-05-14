import abc
import datetime

from mediawords.util.text import random_string

from podcast_transcribe_episode.config import (
    AbstractGCBucketConfig,
    RawEnclosuresBucketConfig,
    TranscodedEpisodesBucketConfig,
    TranscriptsBucketConfig,
)


class RandomGCSPrefixMixin(AbstractGCBucketConfig, metaclass=abc.ABCMeta):
    """
    Generates a random path prefix to store the objects at.

    Makes it easier to debug what gets written to GCS and get rid of said objects afterwards.
    """

    __slots__ = [
        '__random_prefix',
    ]

    def __init__(self):
        super().__init__()

        date = datetime.datetime.utcnow().isoformat()
        date = date.replace(':', '_')
        self.__random_prefix = f'tests-{date}-{random_string(length=32)}'

    def path_prefix(self) -> str:
        return self.__random_prefix


class RandomPrefixRawEnclosuresBucketConfig(RandomGCSPrefixMixin, RawEnclosuresBucketConfig):
    pass


class RandomPrefixTranscodedEpisodesBucketConfig(RandomGCSPrefixMixin, TranscodedEpisodesBucketConfig):
    pass


class RandomPrefixTranscriptsBucketConfig(RandomGCSPrefixMixin, TranscriptsBucketConfig):
    pass
