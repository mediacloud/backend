from typing import List
from mediawords.util.config import env_value


class TopicsMineConfig(object):
    """Topic miner configuration."""

    @staticmethod
    def crimson_hexagon_api_key() -> str:
        """Crimson Hexagon API key."""
        return env_value('MC_CRIMSON_HEXAGON_API_KEY')

    @staticmethod
    def topic_alert_emails() -> List[str]:
        """List of emails to which to send all topic alerts."""
        env_value = env_value('MC_TOPIC_ALERT_EMAILS', allow_empty_string=True)
        emails = env_value.split(',')
        emails = [email.strip() for email in emails]
        if len(emails) == 0 and emails[0] == '':
            emails = []
        return emails

