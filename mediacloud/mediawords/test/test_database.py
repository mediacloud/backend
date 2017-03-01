from unittest import TestCase
from mediawords.db.handler import DatabaseHandler
from mediawords.util.config import \
    get_config as py_get_config  # MC_REWRITE_TO_PYTHON: rename back to get_config()
from mediawords.util.log import create_logger

l = create_logger(__name__)


class TestDatabaseTestCase(TestCase):
    """TestCase that connects to the test database which is later accessible as self.db()"""
    # FIXME might as well initialize it with the schema here
    __db = None

    @staticmethod
    def _create_database_handler():
        l.info("Looking for test database credentials...")
        test_database = None
        config = py_get_config()
        for database in config['database']:
            if database['label'] == 'test':
                test_database = database
                break
        assert test_database is not None

        l.info("Connecting to test database '%s' via DatabaseHandler class..." % test_database['db'])
        db = DatabaseHandler(
            host=test_database['host'],
            port=test_database['port'],
            username=test_database['user'],
            password=test_database['pass'],
            database=test_database['db']
        )

        return db

    def setUp(self):
        self.__db = self._create_database_handler()

    def tearDown(self):
        self.__db.disconnect()

    def db(self) -> DatabaseHandler:
        return self.__db
