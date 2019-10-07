import abc
import datetime


class AbstractPostFetcher(object, metaclass=abc.ABCMeta):

    @abc.abstractmethod
    def fetch_posts(self, query: dict, start_date: datetime, end_date: datetime) -> list:
        raise NotImplemented("Abstract method")
