from typing import List
from mediawords.util.config import env_value


class TwitterAPIConfig(object):
    """Twitter API configuration."""

    @staticmethod
    def consumer_key() -> str:
        """Consumer key."""
        return env_value('MC_TWITTER_CONSUMER_KEY')

    @staticmethod
    def consumer_secret() -> str:
        """Consumer secret."""
        return env_value('MC_TWITTER_CONSUMER_SECRET')

    @staticmethod
    def access_token() -> str:
        """Access token."""
        return env_value('MC_TWITTER_ACCESS_TOKEN')

    @staticmethod
    def access_token_secret() -> str:
        """Access token secret."""
        return env_value('MC_TWITTER_ACCESS_TOKEN_SECRET')


class TopicsBaseConfig(object):
    """Topic base configuration."""

    @staticmethod
    def topic_alert_emails() -> List[str]:
        """List of emails to which to send all topic alerts."""
        emails = env_value('MC_TOPICS_BASE_TOPIC_ALERT_EMAILS', required=False, allow_empty_string=True)
        if emails is None:
            emails = "topicupdates@testmediacloud.ml, slackupdates@testmediacloud.ml"
        emails = emails.split(',')
        emails = [email.strip() for email in emails]
        if len(emails) == 0 and emails[0] == '':
            emails = []
        return emails

    @staticmethod
    def twitter_api() -> TwitterAPIConfig:
        """Return Twitter API configuration."""
        return TwitterAPIConfig()
