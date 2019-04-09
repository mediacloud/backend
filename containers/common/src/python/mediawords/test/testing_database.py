from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.db.handler import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.mail import enable_test_mode, disable_test_mode

log = create_logger(__name__)


class McTestDatabaseTestCaseException(Exception):
    """Errors arising from the setup or tear down of database test cases."""

    pass


class TestDatabaseTestCase(TestCase):
    """TestCase that connects to the test database which is later accessible as self.db()."""

    __slots__ = [
        '__db',
    ]

    @staticmethod
    def create_database_handler() -> DatabaseHandler:
        """Create and return database handler; used by some tests to create separate handlers."""
        db = connect_to_db()
        return db

    def setUp(self):
        super().setUp()
        log.info('Connecting to database...')
        self.__db = self.create_database_handler()

    def tearDown(self):
        super().tearDown()
        self.__db.disconnect()

    def db(self) -> DatabaseHandler:
        return self.__db


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
