from unittest import TestCase

from mediawords.db.handler import DatabaseHandler
from mediawords.db.schema.schema import initialize_with_schema
from mediawords.test.db.environment import force_using_test_database
from mediawords.util.config.common import CommonConfig
from mediawords.util.log import create_logger
from mediawords.util.mail import enable_test_mode, disable_test_mode

log = create_logger(__name__)


class McTestDatabaseTestCaseException(Exception):
    """Errors arising from the setup or tear down of database test cases."""

    pass


class TestDatabaseTestCase(TestCase):
    """TestCase that connects to the test database which is later accessible as self.db()."""

    __slots__ = [
        '__db_config',
        '__db',
    ]

    def setUp(self):
        super().setUp()
        log.info('Connecting to database...')
        self.__db_config = CommonConfig.database()
        self.__db = DatabaseHandler(
            host=self.__db_config.hostname(),
            port=self.__db_config.port(),
            username=self.__db_config.username(),
            password=self.__db_config.password(),
            database=self.__db_config.database_name(),
        )

    def tearDown(self):
        super().tearDown()
        self.__db.disconnect()

    def db(self) -> DatabaseHandler:
        return self.__db


class TestDatabaseWithSchemaTestCase(TestDatabaseTestCase):
    """TestCase that connects to the test database and imports schema; database is later accessible as self.db()."""

    @staticmethod
    def __kill_connections_to_database(db: DatabaseHandler, database_name: str) -> None:
        """Kill all active connections to the database."""
        # If multiple Python test files get run in a sequence and one of them fails, the test apparently doesn't call
        # tearDown() and the the connection to the test database persists (apparently)
        db.query("""
            SELECT pg_terminate_backend(pg_stat_activity.pid)
            FROM pg_catalog.pg_stat_activity
            WHERE datname = %(template_db_name)s
              AND pid != pg_backend_pid()
        """, {'template_db_name': database_name})

    def setUp(self) -> None:
        """Create a fresh template data from mediawords.sql."""
        super().setUp()

        TestDatabaseWithSchemaTestCase.__kill_connections_to_database(
            db=self.__db,
            database_name=CommonConfig.database().database_name(),
        )

        # Refuse to do anything else if there is at least a single relation in a non-system schema
        relations = self.__db.query("""
            SELECT *
            FROM information_schema.tables
            WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
        """).hashes()
        if len(relations):
            raise McTestDatabaseTestCaseException("Test database is not empty.")

        initialize_with_schema(db=self.__db)

        force_using_test_database()


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
