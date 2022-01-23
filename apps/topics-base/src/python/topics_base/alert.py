from mediawords.util.log import create_logger
log = create_logger(__name__)

import mediawords.util.mail
import topics_base.config
import topics_base.messages

def send_topic_alert(db, topic, message):
    """ send an alert about significant activity on the topic to all users with at least write access to the topic"""

    emails = db.query(
        """
        select distinct au.email
            from auth_users au
                join topic_permissions tp using (auth_users_id)
            where
                tp.permission in ('admin', 'write') and
                tp.topics_id = %(a)s
        """,
        {'a': topic['topics_id']}).flat()

    emails.extend(topics_base.config.TopicsBaseConfig.topic_alert_emails())

    emails = set(emails)

    for email in emails:
        message = topics_base.messages.TopicSpiderUpdateMessage(
                to=email,
                topic_name=topic['name'],
                topic_url="https://topics.mediacloud.org/#/topics/topic['topics_id']/summary",
                topic_spider_status=message,
        )
        mediawords.util.mail.send_email(message)
