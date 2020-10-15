from unittest import TestCase

from mediawords.util.mail import (
    Message,
    send_email,
    send_text_email,
    sent_test_messages,
    enable_test_mode as enable_mail_test_mode,
    disable_test_mode as disable_mail_test_mode,
)


class TestMail(TestCase):
    """Class instead of a module in order to be able to toggle email's test mode."""

    def setUp(self):
        enable_mail_test_mode()

    def tearDown(self):
        disable_mail_test_mode()

    def test_send_mail(self):
        message = Message(
            to='nowhere@mediacloud.org',
            cc='nowhere+cc@mediacloud.org',
            bcc='nowhere+bcc@mediacloud.org',
            subject='Hello!',
            text_body='Text message 𝖜𝖎𝖙𝖍 𝖘𝖔𝖒𝖊 𝖀𝖓𝖎𝖈𝖔𝖉𝖊 𝖈𝖍𝖆𝖗𝖆𝖈𝖙𝖊𝖗𝖘.',
            html_body='<strong>HTML message 𝖜𝖎𝖙𝖍 𝖘𝖔𝖒𝖊 𝖀𝖓𝖎𝖈𝖔𝖉𝖊 𝖈𝖍𝖆𝖗𝖆𝖈𝖙𝖊𝖗𝖘.</strong>',
        )
        assert send_email(message)

        sent_message = sent_test_messages().pop()

        assert sent_message == message

    def test_send_text_email(self):
        assert send_text_email(
            to='nowhere@mediacloud.org',
            subject='Hello!',
            body='This is my message 𝖜𝖎𝖙𝖍 𝖘𝖔𝖒𝖊 𝖀𝖓𝖎𝖈𝖔𝖉𝖊 𝖈𝖍𝖆𝖗𝖆𝖈𝖙𝖊𝖗𝖘.',
        )
