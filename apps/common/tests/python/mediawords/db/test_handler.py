import re
from unittest import TestCase

import pytest

from mediawords.db import connect_to_db
from mediawords.db.exceptions.handler import McPrimaryKeyColumnException
from mediawords.db.exceptions.result import McDatabaseResultException
from mediawords.db.handler import McRequireByIDException, McUniqueConstraintException
from mediawords.util.log import create_logger

log = create_logger(__name__)


# noinspection SqlResolve,SpellCheckingInspection
class TestDatabaseHandler(TestCase):
    __slots__ = [
        '__db',
    ]

    def setUp(self):

        super().setUp()

        self.__db = connect_to_db()

        log.debug("Preparing test table 'kardashians'...")
        self.__db.query("DROP TABLE IF EXISTS kardashians CASCADE")
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
        log.debug("Tearing down...")
        self.__db.query("DROP TABLE IF EXISTS kardashians CASCADE")

        # Test disconnect() too
        super().tearDown()

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
        with pytest.raises(McDatabaseResultException):
            self.__db.query("Badger badger badger badger")

    # MC_REWRITE_TO_PYTHON: remove after __convert_datetime_objects_to_strings() gets removed and database handler
    # is made to return datetime.datetime objects again
    def test_query_datetime(self):
        """Test that datetime objects are being stringified and returned as PostgreSQL-compatible dates."""

        date = self.__db.query("""SELECT NOW()::DATE AS date""").hash()
        assert isinstance(date['date'], str)
        assert re.match(r'^\d\d\d\d-\d\d-\d\d$', date['date'])

        time = self.__db.query("""SELECT NOW()::TIME AS time""").hash()
        assert isinstance(time['time'], str)
        assert re.match(r'^\d\d:\d\d:\d\d(\.\d+)?$', time['time'])

        timestamp = self.__db.query("""SELECT NOW()::TIMESTAMP AS timestamp""").hash()
        assert isinstance(timestamp['timestamp'], str)
        assert re.match(r'^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d(\.\d+)?$', timestamp['timestamp'])

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

        # Try out various strings that could be taken as psycopg2's parameter placeholders, see if database handler
        # fails
        names = [
            'Lamar %(foo)s',
            'Lamar %s',
            'Lamar %()s',
            'Lamar %()',
            'Lamar %(',
            'Lamar %',
        ]

        for name in names:
            query = "INSERT INTO kardashians (name, surname, dob) VALUES (%(name)s, 'Odom', '1979-11-06')" % {
                # Python interpolation
                'name': self.__db.quote(name),
            }
            self.__db.query(query)

            lamar = self.__db.query("SELECT * FROM kardashians WHERE name LIKE 'Lamar%'").hash()
            assert lamar is not None
            assert lamar['name'] == name
            assert lamar['surname'] == 'Odom'

            self.__db.query("DELETE FROM kardashians WHERE name LIKE 'Lamar%'")
            lamar = self.__db.query("SELECT * FROM kardashians WHERE name LIKE 'Lamar%'").hash()
            assert lamar is None

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

        # MC_REWRITE_TO_PYTHON: remove after __convert_datetime_objects_to_strings() gets removed and database handler
        # is made to return datetime.datetime objects again
        assert isinstance(row[3], str)

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

        # MC_REWRITE_TO_PYTHON: remove after __convert_datetime_objects_to_strings() gets removed and database handler
        # is made to return datetime.datetime objects again
        assert isinstance(row['dob'], str)

        row = result.hash()
        assert row is None

    def test_query_result_flat(self):
        flat_rows = self.__db.query("""
            SELECT * FROM kardashians WHERE name IN ('Caitlyn', 'Kris') ORDER BY name
        """).flat()
        assert len(flat_rows) == 5 * 2  # two rows, 5 columns each
        assert flat_rows[1] == 'Caitlyn'

        # MC_REWRITE_TO_PYTHON: remove after __convert_datetime_objects_to_strings() gets removed and database handler
        # is made to return datetime.datetime objects again
        assert isinstance(flat_rows[3], str)
        assert isinstance(flat_rows[8], str)

    def test_query_result_hashes(self):
        hashes = self.__db.query("""
            SELECT * FROM kardashians WHERE name IN ('Caitlyn', 'Kris') ORDER BY name
        """).hashes()
        assert len(hashes) == 2

        assert len(hashes[0]) == 5
        assert hashes[0]['name'] == 'Caitlyn'

        assert len(hashes[1]) == 5
        assert hashes[1]['name'] == 'Kris'

        # MC_REWRITE_TO_PYTHON: remove after __convert_datetime_objects_to_strings() gets removed and database handler
        # is made to return datetime.datetime objects again
        assert isinstance(hashes[0]['dob'], str)
        assert isinstance(hashes[1]['dob'], str)

    def test_primary_key_column(self):
        primary_key = self.__db.primary_key_column('kardashians')
        assert primary_key == 'id'

        # Test caching
        primary_key = self.__db.primary_key_column('kardashians')
        assert primary_key == 'id'

        # Different schema
        self.__db.query("CREATE SCHEMA IF NOT EXISTS test")
        self.__db.query("""
            CREATE TABLE IF NOT EXISTS test.table_with_primary_key (
                primary_key_column SERIAL PRIMARY KEY NOT NULL,
                some_other_column TEXT NOT NULL
            )
        """)
        primary_key = self.__db.primary_key_column('test.table_with_primary_key')
        assert primary_key == 'primary_key_column'

        # Partitioned base table
        self.__db.query("""
            CREATE TABLE IF NOT EXISTS partitioned_table (
                partitioned_table_id    BIGSERIAL       NOT NULL,
                test                    TEXT            NOT NULL,
                PRIMARY KEY (partitioned_table_id)
            ) PARTITION BY RANGE (partitioned_table_id)
        """)
        primary_key = self.__db.primary_key_column('partitioned_table')
        assert primary_key == 'partitioned_table_id'

        # Partitioned child table
        self.__db.query("""
            CREATE TABLE IF NOT EXISTS partitioned_table_c1
                PARTITION OF partitioned_table
                FOR VALUES FROM (1) TO (10)
        """)
        primary_key = self.__db.primary_key_column('partitioned_table_c1')
        assert primary_key == 'partitioned_table_id'

        # Composite primary key
        self.__db.query("""
            CREATE TABLE IF NOT EXISTS table_with_composite_pk (
                table_with_composite_pk_id  BIGSERIAL   NOT NULL,
                name                        TEXT        NOT NULL,
                surname                     TEXT        NOT NULL,
                PRIMARY KEY (table_with_composite_pk_id, surname)
            )
        """)
        primary_key = self.__db.primary_key_column('table_with_composite_pk')
        assert primary_key == 'table_with_composite_pk_id'

        # Nonexistent table
        with pytest.raises(McPrimaryKeyColumnException):
            self.__db.primary_key_column('nonexistent_table')

        # No primary key
        self.__db.query("""
            CREATE TABLE IF NOT EXISTS no_primary_key (
                foo TEXT NOT NULL
            )
        """)
        with pytest.raises(McPrimaryKeyColumnException):
            self.__db.primary_key_column('no_primary_key')

    def test_primary_key_column_view(self):
        """Test primary_key_column() against a view (in front of a partitioned table)."""

        self.__db.query("""
            CREATE OR REPLACE VIEW primary_key_column_view_celebrities AS
                SELECT id AS primary_key_column_view_celebrities_id, name, surname
                FROM kardashians
        """)
        primary_key = self.__db.primary_key_column('primary_key_column_view_celebrities')
        assert primary_key == 'primary_key_column_view_celebrities_id'

        self.__db.query("""
            CREATE OR REPLACE VIEW primary_key_column_view_celebrities_2 AS
                SELECT id, name, surname
                FROM kardashians
        """)
        primary_key = self.__db.primary_key_column('primary_key_column_view_celebrities_2')
        assert primary_key == 'id'

        # Test caching
        primary_key = self.__db.primary_key_column('primary_key_column_view_celebrities')
        assert primary_key == 'primary_key_column_view_celebrities_id'

        # Different schema
        self.__db.query("CREATE SCHEMA IF NOT EXISTS test")
        self.__db.query("""
            CREATE OR REPLACE VIEW test.primary_key_column_view_celebrities_2 AS
                SELECT id, name, surname
                FROM public.kardashians
        """)
        primary_key = self.__db.primary_key_column('test.primary_key_column_view_celebrities_2')
        assert primary_key == 'id'

        # Nonexistent view
        with pytest.raises(McPrimaryKeyColumnException):
            self.__db.primary_key_column('nonexistent_view')

        # No primary key
        self.__db.query("""
            CREATE OR REPLACE VIEW primary_key_column_view_celebrities_no_pk AS
                SELECT name, surname
                FROM kardashians
        """)
        with pytest.raises(McPrimaryKeyColumnException):
            self.__db.primary_key_column('primary_key_column_view_celebrities_no_pk')

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
        with pytest.raises(McDatabaseResultException):
            self.__db.update_by_id('kardashians', 4, {'does_not': 'exist'})

    def test_delete_by_id(self):
        self.__db.delete_by_id(table='kardashians', object_id=4)
        row = self.__db.find_by_id(table='kardashians', object_id=4)
        assert row is None

    def test_create(self):
        insert_hash = {
            'name': 'Lamar',
            'surname': 'Odom',
            'dob': '1979-11-06',
        }
        row = self.__db.create(table='kardashians', insert_hash=insert_hash)
        assert row['surname'] == 'Odom'
        assert str(row['dob']) == '1979-11-06'

        # Nonexistent column
        with pytest.raises(McDatabaseResultException):
            self.__db.create('kardashians', {'does_not': 'exist'})

        # unique constraint
        with pytest.raises(McUniqueConstraintException):
            self.__db.create('kardashians', insert_hash)

    def test_create_updatable_view(self):
        """Test create() against an updatable view that's in front of a partitioned table."""

        self.__db.query("""
            CREATE OR REPLACE VIEW create_updatable_view_celebrities AS
                SELECT *
                FROM kardashians;

            -- Make RETURNING work with partitioned tables
            -- (https://wiki.postgresql.org/wiki/INSERT_RETURNING_vs_Partitioning)
            ALTER VIEW create_updatable_view_celebrities
                ALTER COLUMN id
                SET DEFAULT nextval(pg_get_serial_sequence('kardashians', 'id')) + 1;

            -- Trigger that implements INSERT / UPDATE / DELETE behavior on "create_updatable_view_celebrities" view
            CREATE OR REPLACE FUNCTION create_updatable_view_celebrities_view_insert_update_delete()
            RETURNS TRIGGER
            AS $$
            BEGIN

                IF (TG_OP = 'INSERT') THEN
                    INSERT INTO kardashians SELECT NEW.*;
                    RETURN NEW;

                ELSIF (TG_OP = 'UPDATE') THEN
                    UPDATE kardashians
                    SET name = NEW.name,
                        surname = NEW.surname,
                        dob = NEW.dob,
                        married_to_kanye = NEW.married_to_kanye
                    WHERE id = OLD.id;
                    RETURN NEW;

                ELSIF (TG_OP = 'DELETE') THEN
                    DELETE FROM kardashians
                        WHERE id = OLD.id;
                    RETURN OLD;

                ELSE
                    RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

                END IF;

            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER create_updatable_view_celebrities_view_insert_update_delete_trigger
                INSTEAD OF INSERT OR UPDATE OR DELETE ON create_updatable_view_celebrities
                FOR EACH ROW EXECUTE PROCEDURE create_updatable_view_celebrities_view_insert_update_delete();
        """)

        insert_hash = {
            'name': 'Lamar',
            'surname': 'Odom',
            'dob': '1979-11-06',
            'married_to_kanye': False,
        }
        row = self.__db.create(table='create_updatable_view_celebrities', insert_hash=insert_hash)
        assert row['surname'] == 'Odom'
        assert str(row['dob']) == '1979-11-06'

        # Nonexistent column
        with pytest.raises(McDatabaseResultException):
            self.__db.create('create_updatable_view_celebrities', {
                'does_not': 'exist',

                'name': 'Lamar2',
                'surname': 'Odom2',
                'dob': '1979-12-06',
                'married_to_kanye': False,
            })

        # unique constraint
        with pytest.raises(McUniqueConstraintException):
            self.__db.create('create_updatable_view_celebrities', insert_hash)

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
        isolated_db = connect_to_db()
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

    def test_copy_from(self):
        copy = self.__db.copy_from(sql="COPY kardashians (name, surname, dob, married_to_kanye) FROM STDIN WITH CSV")
        copy.put_line("Lamar,Odom,1979-11-06,f\n")
        copy.put_line("Sam Brody,𝐽𝑒𝑛𝑛𝑒𝑟,1983-08-21,f\n")  # UTF-8
        copy.end()

        row = self.__db.query("SELECT * FROM kardashians WHERE name = 'Lamar'").hash()
        assert row is not None
        assert row['surname'] == 'Odom'
        assert str(row['dob']) == '1979-11-06'

        row = self.__db.query("SELECT * FROM kardashians WHERE name = 'Sam Brody'").hash()
        assert row is not None
        assert row['surname'] == '𝐽𝑒𝑛𝑛𝑒𝑟'
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
        assert line == "Kris,Jenner,1955-11-05,f\n"

        # UTF-8
        copy.get_line()  # Caitlyn Jenner
        copy.get_line()  # Kourtney Kardashian
        copy.get_line()  # Kim Kardashian
        line = copy.get_line()
        assert line == "Khloé,Kardashian,1984-06-27,f\n"

        copy.end()

        # Test iterator
        copy = self.__db.copy_to(sql=sql)
        count = 0
        found_utf8_khloe = False
        for line in copy:
            count += 1
            if 'Khloé' in line:
                found_utf8_khloe = True
        copy.end()
        assert count == 8
        assert found_utf8_khloe is True

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
