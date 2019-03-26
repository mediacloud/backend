from typing import List
from mediawords.util.config import env_value


class TopicsBaseConfig(object):
    """Topic base configuration."""

    @staticmethod
    def topic_alert_emails() -> List[str]:
        """List of emails to which to send all topic alerts."""
        env_value = env_value('MC_BASE_TOPIC_ALERT_EMAILS', allow_empty_string=True)
        emails = env_value.split(',')
        emails = [email.strip() for email in emails]
        if len(emails) == 0 and emails[0] == '':
            emails = []
        return emails

