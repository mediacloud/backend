from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.util.network import random_unused_port


class TestURLVariantsTestCase(TestCase):
    # Cruft that we expect the function to remove
    CRUFT = '?utm_source=A&utm_medium=B&utm_campaign=C'

    __slots__ = [
        'db',
    ]

    def setUp(self):
        super().setUp()

        self.db = connect_to_db()

        self.TEST_HTTP_SERVER_PORT = random_unused_port()
        self.TEST_HTTP_SERVER_URL = 'http://localhost:%d' % self.TEST_HTTP_SERVER_PORT

        self.STARTING_URL_WITHOUT_CRUFT = '%s/first' % self.TEST_HTTP_SERVER_URL
        self.STARTING_URL = self.STARTING_URL_WITHOUT_CRUFT + self.CRUFT
