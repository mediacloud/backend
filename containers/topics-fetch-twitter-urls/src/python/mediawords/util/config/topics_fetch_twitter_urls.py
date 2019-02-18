from typing import List
from mediawords.util.config import env_value


class TopicsFetchTwitterURLsConfig(object):
    """Topic fetch Twitter URLs configuration."""

    @staticmethod
    def twitter_consumer_key() -> str:
        """Twitter API consumer key."""
        return env_value('MC_TWITTER_CONSUMER_KEY')

    @staticmethod
    def twitter_consumer_secret() -> str:
        """Twitter API consumer secret."""
        return env_value('MC_TWITTER_CONSUMER_SECRET')

    @staticmethod
    def twitter_access_token() -> str:
        """Twitter API access token."""
        return env_value('MC_TWITTER_ACCESS_TOKEN')

    @staticmethod
    def twitter_access_token_secret() -> str:
        """Twitter API access token secret."""
        return env_value('MC_TWITTER_ACCESS_TOKEN_SECRET')
