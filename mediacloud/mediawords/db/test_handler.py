from unittest import TestCase

from mediawords.db.handler import *
from mediawords.util.config import get_config, set_config
from mediawords.util.log import create_logger

l = create_logger(__name__)


# FIXME make use of the testing database
# noinspection SqlResolve,SpellCheckingInspection
class TestDatabaseHandler(TestCase):
    __db = None

    @staticmethod
    def __create_database_handler():
        l.info("Looking for test database credentials...")
        test_database = None
        config = get_config()
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

        self.__db = self.__create_database_handler()

        l.info("Looking for test database credentials...")
        test_database = None
        config = get_config()
        for database in config['database']:
            if database['label'] == 'test':
                test_database = database
                break
        assert test_database is not None

        l.info("Connecting to test database '%s' via DatabaseHandler class..." % test_database['db'])
        self.__db = DatabaseHandler(
            host=test_database['host'],
            port=test_database['port'],
            username=test_database['user'],
            password=test_database['pass'],
            database=test_database['db']
        )

        l.info("Preparing test table 'kardashians'...")
        self.__db.query("DROP TABLE IF EXISTS kardashians")
        self.__db.query("""
            CREATE TABLE kardashians (
                id SERIAL PRIMARY KEY NOT NULL,
                name VARCHAR UNIQUE NOT NULL,   -- UNIQUE to test find_or_create()
                surname TEXT NOT NULL,
                dob DATE NOT NULL,
                married_to_kanye BOOL NOT NULL DEFAULT 'f'
            )
        """)
        self.__db.query("""
            INSERT INTO kardashians (name, surname, dob, married_to_kanye) VALUES
            ('Kris', 'Jenner', '1955-11-05'::DATE, 'f'),          -- id=1
            ('Caitlyn', 'Jenner', '1949-10-28'::DATE, 'f'),       -- id=2
            ('Kourtney', 'Kardashian', '1979-04-18'::DATE, 'f'),  -- id=3
            ('Kim', 'Kardashian', '1980-10-21'::DATE, 't'),       -- id=4
            ('Khloé', 'Kardashian', '1984-06-27'::DATE, 'f'),     -- id=5
            ('Rob', 'Kardashian', '1987-03-17'::DATE, 'f'),       -- id=6
            ('Kendall', 'Jenner', '1995-11-03'::DATE, 'f'),       -- id=7
            ('Kylie', 'Jenner', '1997-08-10'::DATE, 'f')          -- id=8
        """)

    def tearDown(self):
        l.info("Tearing down...")
        self.__db.query("DROP TABLE IF EXISTS kardashians")

    def test_query_parameters(self):

        # DBD::Pg style
        row = self.__db.query("SELECT * FROM kardashians WHERE name = ?", 'Kris')
        assert row is not None
        row_hash = row.hash()
        assert row_hash['name'] == 'Kris'
        assert row_hash['surname'] == 'Jenner'

        # psycopg2 style
        row = self.__db.query('SELECT * FROM kardashians WHERE name = %s', ('Kris',))
        assert row is not None
        row_hash = row.hash()
        assert row_hash['name'] == 'Kris'
        assert row_hash['surname'] == 'Jenner'

    def test_query_result_columns(self):
        columns = self.__db.query("SELECT * FROM kardashians").columns()
        assert len(columns) == 5
        assert columns[2] == 'surname'

    def test_query_result_rows(self):
        rows_affected = self.__db.query("SELECT * FROM kardashians").rows()
        assert rows_affected == 8  # rows SELECTed

        rows_affected = self.__db.query("""
            UPDATE kardashians SET surname = 'Kardashian-West' WHERE name = 'Kim'
        """).rows()
        assert rows_affected == 1  # rows UPDATEd

    def test_query_result_array(self):
        result = self.__db.query("SELECT * FROM kardashians WHERE name IN ('Caitlyn', 'Kris') ORDER BY name")

        row = result.array()
        assert row[1] == 'Caitlyn'

        row = result.array()
        assert row[1] == 'Kris'

        row = result.array()
        assert row is None

    def test_query_result_hash(self):
        result = self.__db.query("SELECT * FROM kardashians WHERE name IN ('Caitlyn', 'Kris') ORDER BY name")

        row = result.hash()
        assert row['name'] == 'Caitlyn'

        row = result.hash()
        assert row['name'] == 'Kris'

        row = result.hash()
        assert row is None

    def test_query_result_flat(self):
        flat_rows = self.__db.query("""
            SELECT * FROM kardashians WHERE name IN ('Caitlyn', 'Kris') ORDER BY name
        """).flat()
        assert len(flat_rows) == 5 * 2  # two rows, 5 columns each
        assert flat_rows[1] == 'Caitlyn'

    def test_query_result_hashes(self):
        hashes = self.__db.query("""
            SELECT * FROM kardashians WHERE name IN ('Caitlyn', 'Kris') ORDER BY name
        """).hashes()
        assert len(hashes) == 2

        assert len(hashes[0]) == 5
        assert hashes[0]['name'] == 'Caitlyn'

        assert len(hashes[1]) == 5
        assert hashes[1]['name'] == 'Kris'

    def test_execute_with_large_work_mem(self):
        normal_work_mem = 256  # MB
        large_work_mem = 512  # MB

        old_large_work_mem = None
        config = get_config()
        if 'large_work_mem' in config['mediawords']:
            old_large_work_mem = config['mediawords']['large_work_mem']

        config['mediawords']['large_work_mem'] = '%dMB' % large_work_mem
        set_config(config)

        self.__db.query('SET work_mem TO %s', ('%sMB' % normal_work_mem,))

        current_work_mem = int(self.__db.query("""
            SELECT setting::INT FROM pg_settings WHERE name = 'work_mem'
        """).flat()[0])
        assert current_work_mem == normal_work_mem * 1024

        self.__db.query('CREATE TEMPORARY TABLE execute_large_work_mem (work_mem INT NOT NULL)')
        self.__db.execute_with_large_work_mem("""
            INSERT INTO execute_large_work_mem (work_mem)
            SELECT setting::INT FROM pg_settings WHERE name = 'work_mem'
        """)

        statement_work_mem = int(self.__db.query("""
            SELECT work_mem FROM execute_large_work_mem
        """).flat()[0])
        assert statement_work_mem == large_work_mem * 1024

        current_work_mem = int(self.__db.query("""
            SELECT setting::INT FROM pg_settings WHERE name = 'work_mem'
        """).flat()[0])
        assert current_work_mem == normal_work_mem * 1024

        config['mediawords']['large_work_mem'] = old_large_work_mem
        set_config(config)

    def test_run_block_with_large_work_mem(self):
        normal_work_mem = 256  # MB
        large_work_mem = 512  # MB

        old_large_work_mem = None
        config = get_config()
        if 'large_work_mem' in config['mediawords']:
            old_large_work_mem = config['mediawords']['large_work_mem']

        config['mediawords']['large_work_mem'] = '%dMB' % large_work_mem
        set_config(config)

        self.__db.query("SET work_mem TO %s", ('%sMB' % normal_work_mem,))

        current_work_mem = int(self.__db.query("""
            SELECT setting::INT FROM pg_settings WHERE name = 'work_mem'
        """).flat()[0])
        assert current_work_mem == normal_work_mem * 1024

        def __test_run_block_with_large_work_mem_inner():
            self.__db.execute_with_large_work_mem("""
                INSERT INTO execute_large_work_mem (work_mem)
                SELECT setting::INT FROM pg_settings WHERE name = 'work_mem'
            """)

        self.__db.query('CREATE TEMPORARY TABLE execute_large_work_mem (work_mem INT NOT NULL)')
        self.__db.run_block_with_large_work_mem(__test_run_block_with_large_work_mem_inner)

        statement_work_mem = int(self.__db.query("""
            SELECT work_mem FROM execute_large_work_mem
        """).flat()[0])
        assert statement_work_mem == large_work_mem * 1024

        current_work_mem = int(self.__db.query("""
            SELECT setting::INT FROM pg_settings WHERE name = 'work_mem'
        """).flat()[0])
        assert current_work_mem == normal_work_mem * 1024

        config['mediawords']['large_work_mem'] = old_large_work_mem
        set_config(config)

    def test_primary_key_column(self):
        primary_key = self.__db.primary_key_column('kardashians')
        assert primary_key == 'id'

        # Test caching
        primary_key = self.__db.primary_key_column('kardashians')
        assert primary_key == 'id'

    def test_find_by_id(self):
        row = self.__db.find_by_id(table='kardashians', object_id=4)
        assert row is not None
        row_hash = row.hash()
        assert row_hash['name'] == 'Kim'

    def test_require_by_id(self):
        # Exists
        row = self.__db.find_by_id(table='kardashians', object_id=4)
        assert row is not None
        row_hash = row.hash()
        assert row_hash['name'] == 'Kim'

        # Doesn't exist
        row = None
        try:
            row = self.__db.require_by_id(table='kardashians', object_id=42)
        except McRequireByIDException:
            pass
        else:
            assert "Should have thrown an exception, " == "but it didn't"
        assert row is None

    def test_update_by_id(self):
        self.__db.update_by_id(table='kardashians', object_id=4, update_hash={
            'surname': 'Kardashian-West',
            '_ignored_key': 'Ignored value.'
        })
        row = self.__db.find_by_id(table='kardashians', object_id=4)
        assert row is not None
        row_hash = row.hash()
        assert row_hash['name'] == 'Kim'
        assert row_hash['surname'] == 'Kardashian-West'
        assert '_ignored_key' not in row_hash

    def test_delete_by_id(self):
        self.__db.delete_by_id(table='kardashians', object_id=4)
        row = self.__db.find_by_id(table='kardashians', object_id=4)
        assert row.rows() == 0

    def test_create(self):
        self.__db.create(table='kardashians', insert_hash={
            'name': 'Lamar',
            'surname': 'Odom',
            'dob': '1979-11-06',
        })
        row = self.__db.query("SELECT * FROM kardashians WHERE name = 'Lamar'").hash()
        assert row['surname'] == 'Odom'
        assert str(row['dob']) == '1979-11-06'

    def test_select(self):
        # One condition
        row = self.__db.select(table='kardashians', what_to_select='*', condition_hash={
            'name': 'Kim',
        })
        assert row is not None
        row_hash = row.hash()
        assert row_hash['surname'] == 'Kardashian'

        # No conditions
        rows = self.__db.select(table='kardashians', what_to_select='*')
        assert rows is not None
        assert rows.rows() == 8

    def test_find_or_create(self):

        # Verify that the record is not here
        row = self.__db.query("SELECT * FROM kardashians WHERE name = 'Lamar'")
        assert row.rows() == 0

        # Should INSERT
        self.__db.find_or_create(table='kardashians', insert_hash={
            'name': 'Lamar',
            'surname': 'Odom',
            'dob': '1979-11-06',
        })
        row = self.__db.query("SELECT * FROM kardashians WHERE name = 'Lamar'")
        assert row is not None
        assert row.rows() == 1
        row_hash = row.hash()
        assert row_hash['surname'] == 'Odom'

        # Should SELECT
        self.__db.find_or_create(table='kardashians', insert_hash={
            'name': 'Lamar',
            'surname': 'Odom',
            'dob': '1979-11-06',
        })
        row = self.__db.query("SELECT * FROM kardashians WHERE name = 'Lamar'")
        assert row is not None
        assert row.rows() == 1
        row_hash = row.hash()
        assert row_hash['surname'] == 'Odom'

    def test_begin_commit(self):

        row = self.__db.query("SELECT * FROM kardashians WHERE name = 'Lamar'")
        assert row.rows() == 0

        # Create a separate database handler to test whether transactions are isolated
        isolated_db = self.__create_database_handler()
        row = isolated_db.query("SELECT * FROM kardashians WHERE name = 'Lamar'")
        assert row.rows() == 0

        self.__db.begin()
        self.__db.create(table='kardashians', insert_hash={
            'name': 'Lamar',
            'surname': 'Odom',
            'dob': '1979-11-06',
        })

        # Should exist in a handle that initiated the transaction...
        row = self.__db.query("SELECT * FROM kardashians WHERE name = 'Lamar'").hash()
        assert row['surname'] == 'Odom'
        assert str(row['dob']) == '1979-11-06'

        # ...but not on the testing handle which is supposed to be isolated
        row = isolated_db.query("SELECT * FROM kardashians WHERE name = 'Lamar'")
        assert row.rows() == 0

        self.__db.commit()

        # Both handles should be able to access new row at this point
        row = self.__db.query("SELECT * FROM kardashians WHERE name = 'Lamar'").hash()
        assert row['surname'] == 'Odom'
        assert str(row['dob']) == '1979-11-06'

        row = isolated_db.query("SELECT * FROM kardashians WHERE name = 'Lamar'").hash()
        assert row['surname'] == 'Odom'
        assert str(row['dob']) == '1979-11-06'

    def test_begin_rollback(self):

        row = self.__db.query("SELECT * FROM kardashians WHERE name = 'Lamar'")
        assert row.rows() == 0

        self.__db.begin()
        self.__db.create(table='kardashians', insert_hash={
            'name': 'Lamar',
            'surname': 'Odom',
            'dob': '1979-11-06',
        })
        self.__db.rollback()

        row = self.__db.query("SELECT * FROM kardashians WHERE name = 'Lamar'")
        assert row.rows() == 0
