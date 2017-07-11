from abc import ABC, abstractmethod
from typing import Dict


class BaseTopicModel(ABC):
    """
    An abstract base topic model class for all topic models
    """

    @abstractmethod
    def add_stories(self, stories: dict) -> None:
        """
        Adding new stories into the model
        :param stories: a dictionary of new stories
        """
        pass

    @abstractmethod
    def summarize_topic(self) -> Dict[int, list]:
        """
        summarize the topic of each story based on the frequency of occurrence of each word
        :return: a dictionary of article_id : topics
        """
        pass
