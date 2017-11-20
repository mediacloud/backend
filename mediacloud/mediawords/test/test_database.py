from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.db.handler import DatabaseHandler
from mediawords.db.schema.schema import recreate_db
from mediawords.test.db.env import force_using_test_database
from mediawords.util.config import (
    get_config as py_get_config,  # MC_REWRITE_TO_PYTHON: rename back to get_config()
)
from mediawords.util.log import create_logger

log = create_logger(__name__)


class TestDatabaseTestCase(TestCase):
    """TestCase that connects to the test database which is later accessible as self.db()"""
    __db = None

    @staticmethod
    def _create_database_handler():
        log.info("Looking for test database credentials...")
        test_database = None
        config = py_get_config()
        for database in config['database']:
            if database['label'] == 'test':
                test_database = database
                break
        assert test_database is not None

        log.info("Connecting to test database '%s' via DatabaseHandler class..." % test_database['db'])
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


class TestDatabaseWithSchemaTestCase(TestCase):
    """TestCase that connects to the test database and imports schema; database is later accessible as self.db()"""

    def setUp(self):
        test_db_label = 'test'
        recreate_db(label=test_db_label)
        db = connect_to_db(label=test_db_label)
        force_using_test_database()
        self.__db = db

    def tearDown(self):
        self.__db.disconnect()

    def db(self) -> DatabaseHandler:
        return self.__db
