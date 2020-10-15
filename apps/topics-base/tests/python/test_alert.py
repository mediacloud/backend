import hashlib

from mediawords.db import connect_to_db
import mediawords.test.db.create
import mediawords.util.mail
import topics_base.alert
from topics_base.config import TopicsBaseConfig

from mediawords.util.log import create_logger

log = create_logger(__name__)

def _create_permission(db, topic, permission):
     au = {
         'email': f'{permission}@bar.com',
         'password_hash': 'x' * 137,
         'full_name': 'foo bar'}
     au = db.create('auth_users', au)

     tp = {
         'topics_id': topic['topics_id'],
         'auth_users_id': au['auth_users_id'],
         'permission': permission}
     tp = db.create('topic_permissions', tp)

     return au


def test_topic_alert():
    db = mediawords.db.connect_to_db()

    topic = mediawords.test.db.create.create_test_topic(db, 'test')

    au_admin = _create_permission(db, topic, 'admin')
    au_read = _create_permission(db, topic, 'read')
    au_write = _create_permission(db, topic, 'write')

    mediawords.util.mail.enable_test_mode()

    test_message = 'foobarbat'

    topics_base.alert.send_topic_alert(db, topic, test_message)
    
    sent_mails = mediawords.util.mail.sent_test_messages()

    expected_emails = [au['email'] for au in (au_admin, au_write)] + TopicsBaseConfig.topic_alert_emails()
    got_emails = [m.to[0] for m in sent_mails]

    assert len(sent_mails) == len(expected_emails)

    assert set(got_emails) == set(expected_emails)

    
