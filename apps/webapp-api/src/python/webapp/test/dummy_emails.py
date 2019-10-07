from unittest import TestCase

from mediawords.util.log import create_logger
from mediawords.util.mail import enable_test_mode, disable_test_mode

log = create_logger(__name__)


class TestDoNotSendEmails(TestCase):
    """TestCase that disables email sending."""

    def setUp(self):
        super().setUp()

        # Don't actually send any emails
        enable_test_mode()

    def tearDown(self):
        super().tearDown()

        # Reenable email sending
        disable_test_mode()
