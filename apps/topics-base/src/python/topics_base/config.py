from typing import List
from mediawords.util.config import env_value


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
