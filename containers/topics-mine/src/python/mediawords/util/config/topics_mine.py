from typing import List
from mediawords.util.config import env_value_or_raise


class TopicsMineConfig(object):
    """Topic miner configuration."""

    @staticmethod
    def twitter_consumer_key() -> str:
        """Twitter API consumer key."""
        return env_value_or_raise('MC_TWITTER_CONSUMER_KEY')

    @staticmethod
    def twitter_consumer_secret() -> str:
        """Twitter API consumer secret."""
        return env_value_or_raise('MC_TWITTER_CONSUMER_SECRET')

    @staticmethod
    def twitter_access_token() -> str:
        """Twitter API access token."""
        return env_value_or_raise('MC_TWITTER_ACCESS_TOKEN')

    @staticmethod
    def twitter_access_token_secret() -> str:
        """Twitter API access token secret."""
        return env_value_or_raise('MC_TWITTER_ACCESS_TOKEN_SECRET')

    @staticmethod
    def crimson_hexagon_api_key() -> str:
        """Crimson Hexagon API key."""
        return env_value_or_raise('MC_CRIMSON_HEXAGON_API_KEY')

    @staticmethod
    def topic_alert_emails() -> List[str]:
        """List of emails to which to send all topic alerts."""
        env_value = env_value_or_raise('MC_TOPIC_ALERT_EMAILS', allow_empty_string=True)
        emails = env_value.split(',')
        emails = [email.strip() for email in emails]
        if len(emails) == 0 and emails[0] == '':
            emails = []
        return emails

