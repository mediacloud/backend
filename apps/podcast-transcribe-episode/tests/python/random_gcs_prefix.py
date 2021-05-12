import abc
import datetime

from podcast_transcribe_episode.config import AbstractGCBucketConfig


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
        self.__random_prefix = f'tests-{date}'

    def path_prefix(self) -> str:
        return self.__random_prefix
