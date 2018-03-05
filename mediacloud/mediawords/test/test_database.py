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
from mediawords.util.mail import enable_test_mode, disable_test_mode

log = create_logger(__name__)

_template_db_created = False


class McTestDatabaseTestCaseException(Exception):
    """Errors arising from the setup or tear down of database test cases."""

    pass


class TestDatabaseTestCase(TestCase):
    """TestCase that connects to the test database which is later accessible as self.db()."""

    __db = None

    @staticmethod
    def create_database_handler() -> DatabaseHandler:
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
        super().setUp()
        self.__db = self.create_database_handler()

    def tearDown(self):
        super().tearDown()
        self.__db.disconnect()

    def db(self) -> DatabaseHandler:
        return self.__db


class TestDatabaseWithSchemaTestCase(TestCase):
    """TestCase that connects to the test database and imports schema; database is later accessible as self.db()."""

    TEST_DB_LABEL = 'test'
    db_name = None
    template_db_name = None

    @classmethod
    def setUpClass(cls) -> None:
        """Create a fresh template data from mediawords.sql.

        The template database will be used to execute the
        'create database mediacloud_test template mediacloud_test_template' functionality to create a fresh database
        for each individual unit test.  Recreating from a template is much faster than creating a database from
        scratch from our large schema.
        """
        super().setUpClass()

        log.info("create test db template")

        config = py_get_config()
        db_config = list(filter(lambda x: x['label'] == cls.TEST_DB_LABEL, config['database']))
        if len(db_config) < 1:
            raise McTestDatabaseTestCaseException("Unable to find %s database in mediawords.yml" % cls.TEST_DB_LABEL)

        cls.db_name = (db_config[0])['db']
        cls.template_db_name = cls.db_name + '_template'

        # we only want to run this once per test suite for all database test cases, so this needs to be a global
        global _template_db_created
        if _template_db_created:
            return

        # we insert this db name directly into sql, so be paranoid about what is in it
        if re.search('[^a-z0-9_]', cls.db_name, flags=re.I) is not None:
            raise McTestDatabaseTestCaseException("Illegal table name: " + cls.db_name)

        # mediacloud_test should already exist, so we have to connect to it to create the template database
        db = connect_to_db(label=cls.TEST_DB_LABEL, do_not_check_schema_version=True)
        db.query("drop database if exists %s" % (cls.template_db_name,))
        db.query("create database %s" % (cls.template_db_name,))
        db.disconnect()
        recreate_db(label=cls.TEST_DB_LABEL, is_template=True)

        _template_db_created = True

    def setUp(self) -> None:
        """Create a fresh testing database for each unit test.

        This relies on an empty template existing, which should have been created in setUpClass() above.
        """

        super().setUp()

        # Connect to the template database to execure the create command for the test database
        log.info("recreate test db template")

        db = connect_to_db(label=self.TEST_DB_LABEL, is_template=True)
        db.query("drop database if exists %s" % (self.db_name,))
        db.query("create database %s template %s" % (self.db_name, self.template_db_name))

        db.disconnect()

        db = connect_to_db(label=self.TEST_DB_LABEL)

        force_using_test_database()

        self.__db = db

    def tearDown(self) -> None:
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
