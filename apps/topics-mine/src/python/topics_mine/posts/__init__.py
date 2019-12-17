import abc
import datetime

from mediawords.util.log import create_logger

log = create_logger(__name__)


class AbstractPostFetcher(object, metaclass=abc.ABCMeta):

    def __init__(self):
        self._mock_enabled = False

    @abc.abstractmethod
    def fetch_posts(self, query: dict, start_date: datetime, end_date: datetime) -> list:
        raise NotImplemented("Abstract method")

    @abc.abstractmethod
    def enable_mock(self) -> None:
        raise NotImplemented("Abstract method")

