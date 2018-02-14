from unittest import TestCase
import re

from mediawords.db import connect_to_db
from mediawords.db.handler import DatabaseHandler
from mediawords.db.schema.schema import recreate_db
from mediawords.test.db.env import force_using_test_database
from mediawords.util.config import (
    get_config as py_get_config,  # MC_REWRITE_TO_PYTHON: rename back to get_config()
)
from mediawords.util.log import create_logger

log = create_logger(__name__)


class McTestDatabaseTestCaseException(Exception):
    """Errors arising from the setup or tear down of database test cases."""

    pass


class TestDatabaseTestCase(TestCase):
    """TestCase that connects to the test database which is later accessible as self.db()."""

    __db = None

    @staticmethod
    def _create_database_handler() -> None:
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
    """TestCase that connects to the test database and imports schema; database is later accessible as self.db()."""

    _template_db_created = False

    def setUp(self) -> None:
        """Create a fresh testing database for each unit test.

        The first time this function is called within a given process, it will create a template database from
        mediawords.sql.  For each test, it will create a new test database using the postgres
        'create database mediacloud_test template mediacloud_test_template' functionality.  Recreating each
        unit test database from the template is much faster than recreating from mediawords.sql.
        """
        test_db_label = 'test'
        config = py_get_config()
        db_config = list(filter(lambda x: x['label'] == test_db_label, config['database']))
        if len(db_config) < 1:
            raise McTestDatabaseTestCaseException("Unable to find %s database in mediawords.yml" % [test_db_label])
        db_name = (db_config[0])['db']
        template_db_name = db_name + '_template'

        if re.search('[^a-z0-9_]', db_name, flags=re.I) is not None:
            raise McTestDatabaseTestCaseException("Illegal table name: " + db_name)

        if not TestDatabaseWithSchemaTestCase._template_db_created:
            log.info("create test db template")
            # mediacloud_test should already exist, so we have to connect to it to create the template database
            db = connect_to_db(label=test_db_label, do_not_check_schema_version=True)
            db.query("drop database if exists %s" % (template_db_name,))
            db.query("create database %s" % (template_db_name,))
            db.disconnect()
            recreate_db(label=test_db_label, is_template=True)
            TestDatabaseWithSchemaTestCase._template_db_created = True

        # now connect to the template database to execure the create command for the test database
        log.info("recreate test db template")

        db = connect_to_db(label=test_db_label, is_template=True)
        db.query("drop database if exists %s" % (db_name,))
        db.query("create database %s template %s" % (db_name, template_db_name))

        db.disconnect()

        db = connect_to_db(label=test_db_label)

        force_using_test_database()
        self.__db = db

    def tearDown(self) -> None:
        self.__db.disconnect()

    def db(self) -> DatabaseHandler:
        return self.__db
