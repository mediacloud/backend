from unittest import TestCase
from nose.tools import assert_raises

from mediawords.db.exceptions.result import McDatabaseResultException
from mediawords.db.handler import *
from mediawords.util.config import \
    get_config as py_get_config, \
    set_config as py_set_config  # MC_REWRITE_TO_PYTHON: rename back to get_config(), get_config()
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

        self.__db = self.__create_database_handler()

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
            ('Khloé', 'Kardashian', '1984-06-27'::DATE, 'f'),     -- id=5; also, UTF-8
            ('Rob', 'Kardashian', '1987-03-17'::DATE, 'f'),       -- id=6
            ('Kendall', 'Jenner', '1995-11-03'::DATE, 'f'),       -- id=7
            ('Kylie', 'Jenner', '1997-08-10'::DATE, 'f')          -- id=8
        """)

    def tearDown(self):
        l.info("Tearing down...")
        self.__db.query("DROP TABLE IF EXISTS kardashians")

        # Test disconnect() in a way too
        self.__db.disconnect()

    def test_query_parameters(self):

        # DBD::Pg style + UTF-8
        row = self.__db.query("SELECT * FROM kardashians WHERE name = ?", 'Khloé')
        assert row is not None
        row_hash = row.hash()
        assert row_hash['name'] == 'Khloé'
        assert row_hash['surname'] == 'Kardashian'

        # psycopg2 style + UTF-8
        row = self.__db.query('SELECT * FROM kardashians WHERE name = %s', ('Khloé',))
        assert row is not None
        row_hash = row.hash()
        assert row_hash['name'] == 'Khloé'
        assert row_hash['surname'] == 'Kardashian'

    def test_query_parameters_multiple(self):

        rows = self.__db.query('SELECT * FROM kardashians WHERE name IN %(names)s ORDER BY name', {
            'names': tuple([
                'Kim',
                'Kris',
                'Kylie',
            ]),
        }).hashes()

        assert rows is not None
        assert len(rows) == 3

        assert rows[0]['name'] == 'Kim'
        assert rows[1]['name'] == 'Kris'
        assert rows[2]['name'] == 'Kylie'

    def test_query_error(self):

        # Bad query
        assert_raises(McDatabaseResultException, self.__db.query, "Badger badger badger badger")

    def test_query_percentage_sign_like(self):

        # LIKE with no psycopg2's arguments
        row = self.__db.query("SELECT * FROM kardashians WHERE name LIKE 'Khlo%'", )
        assert row is not None
        row_hash = row.hash()
        assert row_hash['name'] == 'Khloé'
        assert row_hash['surname'] == 'Kardashian'

        # LIKE with one argument
        row = self.__db.query("""
            SELECT *
            FROM kardashians
            WHERE name LIKE %(name_prefix)s
              AND surname = %(surname)s
        """, {'name_prefix': 'Khlo%', 'surname': 'Kardashian'})
        assert row is not None
        row_hash = row.hash()
        assert row_hash['name'] == 'Khloé'
        assert row_hash['surname'] == 'Kardashian'

    def test_query_percentage_sign_quote_no_params(self):

        # Quoted string with '%'
        inserted_name = 'Lamar 100%'
        inserted_surname = 'Odom 1000%'
        inserted_dob = '1979-11-06'

        quoted_name = self.__db.quote(inserted_name)
        quoted_surname = self.__db.quote(inserted_surname)
        quoted_dob = self.__db.quote(inserted_dob)

        query = "INSERT INTO kardashians (name, surname, dob) VALUES (%(name)s, %(surname)s, %(dob)s)" % {
            # Python interpolation
            'name': quoted_name,
            'surname': quoted_surname,
            'dob': quoted_dob,
        }

        self.__db.query(query)

        lamar = self.__db.query("SELECT * FROM kardashians WHERE name LIKE 'Lamar 100%%'").hash()
        assert lamar is not None
        assert lamar['name'] == inserted_name
        assert lamar['surname'] == inserted_surname

    def test_query_percentage_sign_quote_tuple_params(self):

        # Quoted string with '%' and tuple parameters
        inserted_name = 'Lamar 100%'
        inserted_surname = 'Odom 1000%'
        inserted_dob = '1979-11-06'

        quoted_name = self.__db.quote(inserted_name)
        quoted_surname = self.__db.quote(inserted_surname)

        query = "INSERT INTO kardashians (name, surname, dob) VALUES (%(name)s, %(surname)s" % {
            # Python interpolation
            'name': quoted_name,
            'surname': quoted_surname,
        }

        self.__db.query(query + ", %s)", (inserted_dob,))

        lamar = self.__db.query("SELECT * FROM kardashians WHERE name LIKE 'Lamar 100%%'").hash()
        assert lamar is not None
        assert lamar['name'] == inserted_name
        assert lamar['surname'] == inserted_surname

    def test_query_percentage_sign_quote_dict_params(self):

        # Quoted string with '%' and dictionary parameters
        inserted_name = 'Lamar 100%'
        inserted_surname = 'Odom 1000%'
        inserted_dob = '1979-11-06'

        quoted_name = self.__db.quote(inserted_name)
        quoted_surname = self.__db.quote(inserted_surname)

        query = "INSERT INTO kardashians (name, surname, dob) VALUES (%(name)s, %(surname)s" % {
            # Python interpolation
            'name': quoted_name,
            'surname': quoted_surname,
        }

        self.__db.query(query + ", %(dob)s)", {'dob': inserted_dob})

        lamar = self.__db.query("SELECT * FROM kardashians WHERE name LIKE 'Lamar 100%%'").hash()
        assert lamar is not None
        assert lamar['name'] == inserted_name
        assert lamar['surname'] == inserted_surname

    def test_query_percentage_sign_quote_dbd_pg_params(self):

        # Quoted string with '%' and DBD::Pg parameters
        inserted_name = 'Lamar 100%'
        inserted_surname = 'Odom 1000%'
        inserted_dob = '1979-11-06'

        quoted_name = self.__db.quote(inserted_name)
        quoted_surname = self.__db.quote(inserted_surname)

        query = "INSERT INTO kardashians (name, surname, dob) VALUES (%(name)s, %(surname)s" % {
            # Python interpolation
            'name': quoted_name,
            'surname': quoted_surname,
        }

        self.__db.query(query + ", ?)", inserted_dob)

        lamar = self.__db.query("SELECT * FROM kardashians WHERE name LIKE 'Lamar 100%%'").hash()
        assert lamar is not None
        assert lamar['name'] == inserted_name
        assert lamar['surname'] == inserted_surname

    def test_query_percentage_sign_quote_psycopg2_param_lookalikes(self):

        # Quoted string with '%' and DBD::Pg parameters
        inserted_name = 'Lamar %(foo)s'
        inserted_surname = 'Odom %s'
        inserted_dob = '1979-11-06'

        quoted_name = self.__db.quote(inserted_name)
        quoted_surname = self.__db.quote(inserted_surname)

        query = "INSERT INTO kardashians (name, surname, dob) VALUES (%(name)s, %(surname)s" % {
            # Python interpolation
            'name': quoted_name,
            'surname': quoted_surname,
        }

        self.__db.query(query + ", ?)", inserted_dob)

        lamar = self.__db.query("SELECT * FROM kardashians WHERE name LIKE 'Lamar%'").hash()
        assert lamar is not None
        assert lamar['name'] == 'Lamar % (foo)s'
        assert lamar['surname'] == 'Odom % s'

    def test_query_percentage_sign_quote_psycopg2_param_lookalikes_empty_name(self):

        # Quoted string with '%' and DBD::Pg parameters
        inserted_name = 'Lamar %()s'
        inserted_surname = 'Odom %s'
        inserted_dob = '1979-11-06'

        quoted_name = self.__db.quote(inserted_name)
        quoted_surname = self.__db.quote(inserted_surname)

        query = "INSERT INTO kardashians (name, surname, dob) VALUES (%(name)s, %(surname)s" % {
            # Python interpolation
            'name': quoted_name,
            'surname': quoted_surname,
        }

        self.__db.query(query + ", ?)", inserted_dob)

        lamar = self.__db.query("SELECT * FROM kardashians WHERE name LIKE 'Lamar%'").hash()
        assert lamar is not None
        assert lamar['name'] == 'Lamar % ()s'
        assert lamar['surname'] == 'Odom % s'

    def test_query_percentage_sign_quote_psycopg2_param_lookalikes_empty_name_no_s(self):

        # Quoted string with '%' and DBD::Pg parameters
        inserted_name = 'Lamar %()'
        inserted_surname = 'Odom %'
        inserted_dob = '1979-11-06'

        quoted_name = self.__db.quote(inserted_name)
        quoted_surname = self.__db.quote(inserted_surname)

        query = "INSERT INTO kardashians (name, surname, dob) VALUES (%(name)s, %(surname)s" % {
            # Python interpolation
            'name': quoted_name,
            'surname': quoted_surname,
        }

        self.__db.query(query + ", ?)", inserted_dob)

        lamar = self.__db.query("SELECT * FROM kardashians WHERE name LIKE 'Lamar%'").hash()
        assert lamar is not None
        assert lamar['name'] == 'Lamar % ()'
        assert lamar['surname'] == 'Odom %'

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

    def test_prepare(self):

        # Basic
        statement = self.__db.prepare("""
            UPDATE kardashians
            SET surname = ?
            WHERE name = ?
              AND surname = ?
        """)
        statement.bind(1, 'Kardashian-West')
        statement.bind(2, 'Kim')
        statement.bind(3, 'Kardashian')
        statement.execute()

        row_hash = self.__db.query("SELECT * FROM kardashians WHERE name = ?", 'Kim').hash()
        assert row_hash['surname'] == 'Kardashian-West'

        # BYTEA
        random_bytes = os.urandom(10 * 1024)
        self.__db.query("""
            CREATE TEMPORARY TABLE table_with_bytea_column (
                id INT NOT NULL,
                surname VARCHAR NOT NULL,
                bytea_data BYTEA NOT NULL
            )
        """)
        statement = self.__db.prepare("""
            INSERT INTO table_with_bytea_column (id, surname, bytea_data)
            VALUES (?, ?, ?)
        """)
        statement.bind(1, 42)
        statement.bind(2, 'Kardashian')
        statement.bind_bytea(3, random_bytes)
        statement.execute()

        row_hash = self.__db.query("SELECT id, surname, bytea_data FROM table_with_bytea_column").hash()
        assert row_hash['id'] == 42
        assert row_hash['surname'] == 'Kardashian'
        assert bytes(row_hash['bytea_data']) == random_bytes

    def test_execute_with_large_work_mem(self):
        normal_work_mem = 256  # MB
        large_work_mem = 512  # MB

        old_large_work_mem = None
        config = py_get_config()
        if 'large_work_mem' in config['mediawords']:
            old_large_work_mem = config['mediawords']['large_work_mem']

        config['mediawords']['large_work_mem'] = '%dMB' % large_work_mem
        py_set_config(config)

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
        py_set_config(config)

    def test_execute_with_large_work_mem_params(self):

        # psycopg2 style
        self.__db.execute_with_large_work_mem("""
            INSERT INTO kardashians (name, surname, dob)
            VALUES (%(name)s, %(surname)s, %(dob)s)
        """, {'name': 'Lamar', 'surname': 'Odom', 'dob': '1979-11-06'})

        # DBD::Pg
        self.__db.execute_with_large_work_mem("""
            INSERT INTO kardashians (name, surname, dob)
            VALUES (?, ?, ?)
        """, 'Lamar-2', 'Odom-2', '1979-11-06')

    def test_run_block_with_large_work_mem(self):
        normal_work_mem = 256  # MB
        large_work_mem = 512  # MB

        old_large_work_mem = None
        config = py_get_config()
        if 'large_work_mem' in config['mediawords']:
            old_large_work_mem = config['mediawords']['large_work_mem']

        config['mediawords']['large_work_mem'] = '%dMB' % large_work_mem
        py_set_config(config)

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
        py_set_config(config)

    def test_primary_key_column(self):
        primary_key = self.__db.primary_key_column('kardashians')
        assert primary_key == 'id'

        # Test caching
        primary_key = self.__db.primary_key_column('kardashians')
        assert primary_key == 'id'

    def test_find_by_id(self):
        row_hash = self.__db.find_by_id(table='kardashians', object_id=4)
        assert row_hash['name'] == 'Kim'

    def test_require_by_id(self):
        # Exists
        row_hash = self.__db.require_by_id(table='kardashians', object_id=4)
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
        updated_row = self.__db.update_by_id(table='kardashians', object_id=4, update_hash={
            'surname': 'Kardashian-West',
            '_ignored_key': 'Ignored value.'
        })

        assert updated_row is not None
        assert updated_row['name'] == 'Kim'
        assert updated_row['surname'] == 'Kardashian-West'

        row_hash = self.__db.find_by_id(table='kardashians', object_id=4)
        assert row_hash is not None
        assert row_hash['name'] == 'Kim'
        assert row_hash['surname'] == 'Kardashian-West'
        assert '_ignored_key' not in row_hash

        # Nonexistent column
        assert_raises(McUpdateByIDException, self.__db.update_by_id, 'kardashians', 4, {'does_not': 'exist'})

    def test_delete_by_id(self):
        self.__db.delete_by_id(table='kardashians', object_id=4)
        row = self.__db.find_by_id(table='kardashians', object_id=4)
        assert row is None

    def test_create(self):
        row = self.__db.create(table='kardashians', insert_hash={
            'name': 'Lamar',
            'surname': 'Odom',
            'dob': '1979-11-06',
        })
        assert row['surname'] == 'Odom'
        assert str(row['dob']) == '1979-11-06'

        # Nonexistent column
        assert_raises(McCreateException, self.__db.create, 'kardashians', {'does_not': 'exist'})

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
        row_hash = self.__db.find_or_create(table='kardashians', insert_hash={
            'name': 'Lamar',
            'surname': 'Odom',
            'dob': '1979-11-06',
        })
        assert row_hash is not None
        assert row_hash['surname'] == 'Odom'

        # Should SELECT
        row_hash = self.__db.find_or_create(table='kardashians', insert_hash={
            'name': 'Lamar',
            'surname': 'Odom',
            'dob': '1979-11-06',
        })
        assert row_hash is not None
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

    def test_quote(self):
        assert self.__db.quote(None) == 'NULL'
        assert self.__db.quote("foo") == "'foo'"
        assert self.__db.quote("foo'bar") == "'foo''bar'"
        assert self.__db.quote("Вот моё сердце. 'Оно полно любви.") == "'Вот моё сердце. ''Оно полно любви.'"
        assert self.__db.quote(0) == "0"
        assert self.__db.quote(1) == "1"
        assert self.__db.quote(3.4528) == "3.4528"
        assert self.__db.quote(True) == "true"
        assert self.__db.quote(False) == "false"

        # Doubling the psycopg2 parameter percentage signs
        assert self.__db.quote("%s") == "'% s'"
        assert self.__db.quote("%(param_1)s") == "'% (param_1)s'"
        assert self.__db.quote("%()s") == "'% ()s'"
        assert self.__db.quote("%()") == "'% ()'"
        assert self.__db.quote("%(") == "'% ('"

    def test_copy_from(self):
        copy = self.__db.copy_from(sql="COPY kardashians (name, surname, dob, married_to_kanye) FROM STDIN WITH CSV")
        copy.put_line("Lamar,Odom,1979-11-06,f\n")
        copy.put_line("Sam Brody,Jenner,1983-08-21,f\n")
        copy.end()

        row = self.__db.query("SELECT * FROM kardashians WHERE name = 'Lamar'").hash()
        assert row is not None
        assert row['surname'] == 'Odom'
        assert str(row['dob']) == '1979-11-06'

        row = self.__db.query("SELECT * FROM kardashians WHERE name = 'Sam Brody'").hash()
        assert row is not None
        assert row['surname'] == 'Jenner'
        assert str(row['dob']) == '1983-08-21'

    def test_copy_to(self):
        sql = """
            COPY (
                SELECT name, surname, dob, married_to_kanye
                FROM kardashians
                ORDER BY id
            ) TO STDOUT WITH CSV
        """

        copy = self.__db.copy_to(sql=sql)
        line = copy.get_line()
        copy.end()
        assert line == "Kris,Jenner,1955-11-05,f\n"

        # Test iterator
        copy = self.__db.copy_to(sql=sql)
        count = 0
        for _ in copy:
            count += 1
        copy.end()
        assert count == 8

    def test_get_temporary_ids_table(self):
        ints = [1, 2, 3, 4, 5]

        # Unordered
        table_name = self.__db.get_temporary_ids_table(ids=ints, ordered=False)
        returned_ints = self.__db.query("SELECT * FROM %s" % table_name).hashes()
        assert len(returned_ints) == len(ints)

        # Ordered
        table_name = self.__db.get_temporary_ids_table(ids=ints, ordered=True)
        returned_ints = self.__db.query(
            "SELECT id FROM %(table_name)s ORDER BY %(table_name)s_pkey" % {'table_name': table_name}
        ).flat()
        assert returned_ints == ints

    def test_attach_child_query(self):

        # Single
        self.__db.query("""
            CREATE TEMPORARY TABLE names (
               id INT NOT NULL,
               name VARCHAR NOT NULL
            );
            INSERT INTO names (id, name)
            VALUES (1, 'John'), (2, 'Jane'), (3, 'Joe');
        """)

        surnames = [
            {'id': 1, 'surname': 'Doe'},
            {'id': 2, 'surname': 'Roe'},
            {'id': 3, 'surname': 'Bloggs'},
        ]

        names_and_surnames = self.__db.attach_child_query(
            data=surnames,
            child_query='SELECT id, name FROM names',
            child_field='name',
            id_column='id',
            single=True
        )
        assert names_and_surnames == [
            {
                'id': 1,
                'name': 'John',
                'surname': 'Doe'
            },
            {
                'id': 2,
                'name': 'Jane',
                'surname': 'Roe'
            },
            {
                'id': 3,
                'name': 'Joe',
                'surname': 'Bloggs'
            }
        ]

        # Not single
        self.__db.query("""
            CREATE TEMPORARY TABLE dogs (
               owner_id INT NOT NULL,
               dog_name VARCHAR NOT NULL
            );
            INSERT INTO dogs (owner_id, dog_name)
            VALUES
                (1, 'Bailey'), (1, 'Max'),
                (2, 'Charlie'), (2, 'Bella'),
                (3, 'Lucy'), (3, 'Molly');
        """)

        owners = [
            {'owner_id': 1, 'owner_name': 'John'},
            {'owner_id': 2, 'owner_name': 'Jane'},
            {'owner_id': 3, 'owner_name': 'Joe'},
        ]

        owners_and_their_dogs = self.__db.attach_child_query(
            data=owners,
            child_query='SELECT owner_id, dog_name FROM dogs',
            child_field='owned_dogs',
            id_column='owner_id',
            single=False
        )

        assert owners_and_their_dogs == [
            {
                'owner_id': 1,
                'owner_name': 'John',
                'owned_dogs': [
                    {
                        'dog_name': 'Bailey',
                        'owner_id': 1
                    },
                    {
                        'owner_id': 1,
                        'dog_name': 'Max'
                    }
                ]
            },
            {
                'owner_id': 2,
                'owner_name': 'Jane',
                'owned_dogs': [
                    {
                        'owner_id': 2,
                        'dog_name': 'Charlie'
                    },
                    {
                        'dog_name': 'Bella',
                        'owner_id': 2
                    }
                ]
            },
            {
                'owner_id': 3,
                'owner_name': 'Joe',
                'owned_dogs': [
                    {
                        'dog_name': 'Lucy',
                        'owner_id': 3
                    },
                    {
                        'owner_id': 3,
                        'dog_name': 'Molly'
                    }
                ]
            }
        ]

    def test_query_paged_hashes(self):

        sql = """SELECT * FROM generate_series(1, 15) AS number"""
        rows_per_page = 10

        # First page
        qph = self.__db.query_paged_hashes(query=sql, page=1, rows_per_page=rows_per_page)
        hashes = qph.list()
        pager = qph.pager()

        assert len(hashes) == 10
        assert hashes[0]['number'] == 1
        assert hashes[9]['number'] == 10

        assert pager.previous_page() is None
        assert pager.next_page() == 2
        assert pager.first() == 1
        assert pager.last() == 10

        # Last page
        qph = self.__db.query_paged_hashes(query=sql, page=2, rows_per_page=rows_per_page)
        hashes = qph.list()
        pager = qph.pager()

        assert len(hashes) == 5
        assert hashes[0]['number'] == 11
        assert hashes[4]['number'] == 15

        assert pager.previous_page() == 1
        assert pager.next_page() is None
        assert pager.first() == 11
        assert pager.last() == 15
