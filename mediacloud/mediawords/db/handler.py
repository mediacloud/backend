import itertools
import os
import pprint
import re
from typing import Dict, Callable, List

import psycopg2
import psycopg2.extras

from mediawords.db.schema.version import schema_version_from_lines
from mediawords.util.config import get_config
from mediawords.util.log import create_logger
from mediawords.util.paths import mc_script_path
from mediawords.util.perl import convert_dbd_pg_arguments_to_psycopg2_format

l = create_logger(__name__)


class MediaWordsDatabaseException(Exception):
    pass


class RequireByIDException(MediaWordsDatabaseException):
    pass


# FIXME add decode_string_from_bytes_if_needed() everywhere
# FIXME think about Catalyst reconnecting to the database every time
# FIXME MC_REWRITE_TO_PYTHON: pass arguments by name, not by index
# FIXME make PyCharm parse psycopg2's query parameters correctly: http://stackoverflow.com/a/36346689/200603
# FIXME custom exceptions
# FIXME add function parameter / return types
class DatabaseHandler(object):
    """PostgreSQL middleware (imitates DBIx::Simple's interface)."""

    # Environment variable which, when set, will make us ignore the schema version
    __IGNORE_SCHEMA_VERSION_ENV_VARIABLE = 'MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION'

    # Min. "deadlock_timeout" to not cause problems under load (in seconds)
    __MIN_DEADLOCK_TIMEOUT = 5

    # cache of table primary key columns
    __primary_key_columns = {}

    # PIDs for which the schema version has been checked
    __schema_version_check_pids = {}

    # Pyscopg2 instance and cursor
    __conn = None
    __db = None

    def __init__(self,
                 host: str,
                 port: int,
                 username: str,
                 password: str,
                 database: str,
                 do_not_check_schema_version: bool = False):
        """Connect to PostgreSQL."""

        # If the user didn't clearly (via 'true' or 'false') state whether or not
        # to check schema version, check it once per PID
        pid = os.getpid()

        if not (host and username and password and database):
            raise Exception("Database connection credentials are not set.")

        if not port:
            port = 5432

        if not do_not_check_schema_version:
            if pid in self.__schema_version_check_pids:
                do_not_check_schema_version = True
            else:
                do_not_check_schema_version = False

        self.__conn = psycopg2.connect(host=host, port=port, user=username, password=password, database=database)
        self.__db = self.__conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

        if not do_not_check_schema_version:
            if not self.schema_is_up_to_date():
                # It would make sense to check the MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION environment variable
                # at this particular point too, but schema_is_up_to_date() warns the user about schema being
                # too old on every run, and that's supposedly a good thing.
                raise Exception("Database schema is not up-to-date.")

        # If schema is not up-to-date, connect() dies and we don't get to set PID here
        self.__schema_version_check_pids[pid] = True

        # Check deadlock_timeout
        (deadlock_timeout,) = self.query("SHOW deadlock_timeout").flat()
        deadlock_timeout = re.sub(r'\s*s$', '', deadlock_timeout, re.I)
        deadlock_timeout = int(deadlock_timeout)
        if deadlock_timeout == 0:
            raise Exception("'deadlock_timeout' is 0, probably unable to read it")
        if deadlock_timeout < self.__MIN_DEADLOCK_TIMEOUT:
            l.warn('"deadlock_timeout" is less than "%ds", expect deadlocks on high extractor load' %
                   self.__MIN_DEADLOCK_TIMEOUT)

    def __should_continue_with_outdated_schema(self, current_schema_version: int, target_schema_version: int) -> bool:
        """Schema is outdated / too new; returns 1 if MC should continue nevertheless, 0 otherwise"""
        config = get_config()
        config_ignore_schema_version = config["mediawords"]["ignore_schema_version"] or False

        if config_ignore_schema_version and self.__IGNORE_SCHEMA_VERSION_ENV_VARIABLE in os.environ:
            l.warn("""
                The current Media Cloud database schema is older than the schema present in mediawords.sql,
                but %s is set so continuing anyway.
            """ % self.__IGNORE_SCHEMA_VERSION_ENV_VARIABLE)
            return True
        else:
            l.warn("""
                ################################

                The current Media Cloud database schema is not the same as the schema present in mediawords.sql.

                The database schema currently running in the database is %(current_schema_version)s,
                and the schema version in the mediawords.sql is %(target_schema_version)s.

                Please run:

                    ./script/mediawords_upgrade_db.py --import

                to automatically upgrade the database schema to the latest version.

                If you want to connect to the Media Cloud database anyway (ignoring the schema version),
                set the %(IGNORE_SCHEMA_VERSION_ENV_VARIABLE)s environment variable as such:

                    %(IGNORE_SCHEMA_VERSION_ENV_VARIABLE)s=1 ./script/your_script.py

                ################################

            """ % {
                "current_schema_version": current_schema_version,
                "target_schema_version": target_schema_version,
                "IGNORE_SCHEMA_VERSION_ENV_VARIABLE": self.__IGNORE_SCHEMA_VERSION_ENV_VARIABLE,
            })
            return False

    def schema_is_up_to_date(self) -> bool:
        """Checks if the database schema is up-to-date"""
        script_dir = mc_script_path()

        # Check if the database is empty
        db_vars_table_exists = len(self.query("""
            -- noinspection SqlResolve
            SELECT *
            FROM information_schema.tables
            WHERE table_name = 'database_variables'
        """).flat()) > 0
        if not db_vars_table_exists:
            l.info("Database table 'database_variables' does not exist, probably the database is empty at this point.")
            return True

        # Current schema version
        (current_schema_version,) = self.query("""
            SELECT value AS schema_version
            FROM database_variables
            WHERE name = 'database-schema-version'
            LIMIT 1
        """).flat()
        current_schema_version = int(current_schema_version)
        if current_schema_version == 0:
            raise Exception("Current schema version is 0")

        # Target schema version
        sql = open(os.path.join(script_dir, 'mediawords.sql'), 'r').read()
        target_schema_version = schema_version_from_lines(sql)
        if not target_schema_version:
            raise Exception("Invalid target schema version.")

        # Check if the current schema is up-to-date
        if current_schema_version != target_schema_version:
            return self.__should_continue_with_outdated_schema(current_schema_version, target_schema_version)
        else:
            # Things are fine at this point.
            return True

    class Result(object):
        """Wrapper around SQL query result."""

        __cursor = None  # psycopg2 cursor

        def __init__(self, cursor, *query_args):
            if len(query_args) == 0:
                raise Exception('No query or its parameters.')
            if len(query_args[0]) == 0:
                raise Exception('Query is empty or undefined.')

            cursor.execute(*query_args)

            self.__cursor = cursor  # Cursor now holds results

        def columns(self) -> list:
            """(result) Returns a list of column names"""
            column_names = [desc[0] for desc in self.__cursor.description]
            return column_names

        def rows(self) -> int:
            """(result) Returns the number of rows affected by the last row affecting command, or -1 if the number of
            rows is not known or not available"""
            rows_affected = self.__cursor.rowcount
            return rows_affected

        def array(self) -> list:
            """(single row) Returns a reference to an array"""
            row_tuple = self.__cursor.fetchone()
            if row_tuple is not None:
                row = list(row_tuple)
            else:
                row = None
            return row

        def hash(self) -> dict:
            """(single row) Returns a reference to a hash, keyed by column name"""
            row_tuple = self.__cursor.fetchone()
            if row_tuple is not None:
                row = dict(row_tuple)
            else:
                row = None
            return row

        def flat(self) -> list:
            """(all remaining rows) Returns a flattened list"""
            all_rows = self.__cursor.fetchall()
            flat_rows = list(itertools.chain.from_iterable(all_rows))
            return flat_rows

        def hashes(self) -> List[Dict]:
            """(all remaining rows) Returns a list of references to hashes, keyed by column name"""
            rows = [dict(row) for row in self.__cursor.fetchall()]
            return rows

        def text(self, text_type='neat') -> str:
            """(all remaining rows) Returns a string with a simple text representation of the data."""
            if text_type != 'neat':
                raise Exception("Formatting types other than 'neat' are not supported.")
            return pprint.pformat(self.hashes(), indent=4)

    def query(self, *query_params) -> Result:
        """Run the query, return instance of MediaWords.Result for accessing the result.

        Accepts either (preferred) psycopg2-style query and parameters:

            db.query('SELECT * FROM foo WHERE bar = %s AND baz = %s', (bar, baz,))
            db.query('SELECT * FROM foo WHERE bar = %(bar)s AND baz = %(baz)s', {'bar': bar, 'baz': baz})

        ...or DBD::Pg (DBIx::Simple) form of query and parameters:

            db.query('SELECT * FROM foo WHERE bar = ? AND baz = ?', bar, baz)
        """

        # FIXME MC_REWRITE_TO_PYTHON: remove after porting queries to named parameter style
        query_params = convert_dbd_pg_arguments_to_psycopg2_format(*query_params)

        if len(query_params) == 0:
            raise Exception("Query is unset.")
        if len(query_params) > 2:
            raise Exception("psycopg2's execute() accepts at most 2 parameters.")

        return DatabaseHandler.Result(self.__db, *query_params)

    def __get_current_work_mem(self) -> str:
        current_work_mem = self.query("SHOW work_mem").flat()[0]
        return current_work_mem

    def __get_large_work_mem(self) -> str:
        config = get_config()
        if 'large_work_mem' in config['mediawords']:
            work_mem = config['mediawords']['large_work_mem']
        else:
            work_mem = self.__get_current_work_mem()
        return work_mem

    def __set_work_mem(self, new_work_mem: str) -> None:
        self.query("SET work_mem TO %s", (new_work_mem,))

    def execute_with_large_work_mem(self, *query_args) -> None:
        """Execute query with large 'work_mem' setting; does *not* return a result of any kind."""

        def __execute_with_large_work_mem_subquery():
            self.query(*query_args)

        exception = None
        try:
            self.run_block_with_large_work_mem(__execute_with_large_work_mem_subquery)
        except Exception as ex:
            l.error("Error while running query with large work memory: %s" % str(ex))
            exception = ex

        if exception is not None:
            raise exception  # pass further

    def run_block_with_large_work_mem(self, block: Callable[[], None]) -> None:
        """Run a block (function) with a large 'work_mem' setting set; does *not* return a result of any kind."""
        l.debug("starting run_block_with_large_work_mem")

        large_work_mem = self.__get_large_work_mem()
        old_work_mem = self.__get_current_work_mem()

        self.__set_work_mem(large_work_mem)

        exception = None
        try:
            block()
        except Exception as ex:
            l.error("Error while running block with large work memory: %s" % str(ex))
            exception = ex

        self.__set_work_mem(old_work_mem)

        l.debug("exiting run_block_with_large_work_mem")

        if exception is not None:
            raise exception  # pass further

    def primary_key_column(self, table: str) -> str:
        """Get the primary key column for the table."""
        if table not in self.__primary_key_columns:
            # noinspection SqlResolve,SqlCheckUsingColumns
            primary_key_column = self.query("""
                SELECT column_name
                FROM information_schema.table_constraints
                     JOIN information_schema.key_column_usage
                         USING (constraint_catalog, constraint_schema, constraint_name,
                                table_catalog, table_schema, table_name)
                WHERE constraint_type = 'PRIMARY KEY'
                  AND table_name = %(table_name)s
                ORDER BY ordinal_position
            """, {'table_name': table}).flat()
            if primary_key_column is None or len(primary_key_column) == 0:
                raise Exception("Primary key for table '%s' was not found" % table)
            if len(primary_key_column) > 1:
                raise Exception(
                    "More than one primary key column was found for table '%(table)s': %(primary_key_columns)s" % {
                        'table': table,
                        'primary_key_columns': str(primary_key_column)
                    })
            primary_key_column = primary_key_column[0]

            self.__primary_key_columns[table] = primary_key_column

        return self.__primary_key_columns[table]

    def find_by_id(self, table: str, object_id: int) -> Result:
        """Do an ID lookup on the table and return a single row match if found."""
        primary_key_column = self.primary_key_column(table)
        if not primary_key_column:
            raise Exception("Primary key for table '%s' was not found" % table)

        # Python substitution
        find_by_id_query = "SELECT * FROM %(table)s WHERE %(id_column)s" % {
            "table": table,
            "id_column": primary_key_column,
        }

        # psycopg2 substitution
        return self.query(find_by_id_query + " = %(id_value)s", {'id_value': object_id})

    def require_by_id(self, table: str, object_id: int) -> Result:
        """find_by_id() or raise exception if not found."""
        row = self.find_by_id(table, object_id)
        if row is None or row.rows() == 0:
            raise RequireByIDException("Unable to find id '%d' in table '%s'" % (object_id, table))
        return row

    def update_by_id(self, table: str, object_id: int, update_hash: dict) -> Result:
        """Update the row in the table with the given ID. Ignore any fields that start with '_'."""
        update_hash = update_hash.copy()  # To be able to safely modify it

        # FIXME MC_REWRITE_TO_PYTHON: remove after getting rid of Catalyst
        if "submit" in update_hash:
            del update_hash["submit"]

        update_hash = {k: v for k, v in update_hash.items() if not k.startswith("_")}

        if len(update_hash) == 0:
            raise Exception("Hash to UPDATE is empty.")

        primary_key_column = self.primary_key_column(table)
        if not primary_key_column:
            raise Exception("Primary key for table '%s' was not found" % table)

        keys = []
        for key, value in update_hash.items():
            key_value = key
            key_value += " = %(" + key + ")s"  # "%(key)s" to be resolved by psycopg2, not Python

            keys.append(key_value)

        update_hash['__object_id'] = object_id

        sql = "UPDATE %s " % table
        sql += "SET %s " % ", ".join(keys)
        sql += "WHERE %s = " % primary_key_column
        sql += "%(__object_id)s"  # "%(__object_id)s" to be resolved by psycopg2, not Python

        return self.query(sql, update_hash)

    def delete_by_id(self, table: str, object_id: int) -> Result:
        """Delete the row in the table with the given ID."""

        primary_key_column = self.primary_key_column(table)
        if not primary_key_column:
            raise Exception("Primary key for table '%s' was not found" % table)

        sql = "DELETE FROM %s " % table
        sql += "WHERE %s = " % primary_key_column
        sql += "%(__object_id)s"  # "%(object_id)s" to be resolved by psycopg2, not Python

        return self.query(sql, {"__object_id": object_id})

    def insert(self, table: str, insert_hash: dict) -> Result:
        """Alias for create()."""
        return self.create(table=table, insert_hash=insert_hash)

    def create(self, table: str, insert_hash: dict) -> Result:
        """Insert a row into the database for the given table with the given hash values and return the created row."""
        insert_hash = insert_hash.copy()  # To be able to safely modify it

        # FIXME MC_REWRITE_TO_PYTHON: remove after getting rid of Catalyst
        if "submit" in insert_hash:
            del insert_hash["submit"]

        if len(insert_hash) == 0:
            raise Exception("Hash to INSERT is empty")

        primary_key_column = self.primary_key_column(table)
        if not primary_key_column:
            raise Exception("Primary key for table '%s' was not found" % table)

        keys = []
        values = []
        for key, value in insert_hash.items():
            keys.append(key)
            values.append("%(" + key + ")s")  # "%(key)s" to be resolved by psycopg2, not Python

        sql = "INSERT INTO %s " % table
        sql += "(%s) " % ", ".join(keys)
        sql += "VALUES (%s) " % ", ".join(values)
        sql += "RETURNING %s" % primary_key_column

        last_inserted_id = self.query(sql, insert_hash).flat()

        if last_inserted_id is None or len(last_inserted_id) == 0:
            raise Exception("Last inserted ID was not found")
        last_inserted_id = last_inserted_id[0]

        inserted_row = self.find_by_id(table=table, object_id=last_inserted_id)
        if inserted_row is None:
            raise Exception("Could not find new ID %d in table '%s'" % (last_inserted_id, table))

        return inserted_row

    def select(self, table: str, what_to_select: str, condition_hash: dict = None) -> Result:
        """SELECT chosen columns from the table that match given conditions."""

        if condition_hash is None:
            condition_hash = {}

        condition_hash = condition_hash.copy()  # To be able to safely modify it

        # FIXME MC_REWRITE_TO_PYTHON: remove after getting rid of Catalyst
        if "submit" in condition_hash:
            del condition_hash["submit"]

        sql_conditions = []

        for key, value in condition_hash.items():
            condition = key
            condition += " = %(" + key + ")s"  # "%(key)s" to be resolved by psycopg2, not Python
            sql_conditions.append(condition)

        sql = "SELECT %s " % what_to_select
        sql += "FROM %s " % table
        if len(sql_conditions) > 0:
            sql += "WHERE %s" % " AND ".join(sql_conditions)

        return self.query(sql, condition_hash)

    def find_or_create(self, table: str, insert_hash: dict) -> Result:
        """Select a single row from the database matching the hash or insert a row with the hash values and return the
        inserted row as a hash."""
        insert_hash = insert_hash.copy()  # To be able to safely modify it

        if len(insert_hash) == 0:
            raise Exception("Hash to INSERT or SELECT is empty")

        # FIXME MC_REWRITE_TO_PYTHON: remove after getting rid of Catalyst
        if "submit" in insert_hash:
            del insert_hash["submit"]

        row = self.select(table=table, what_to_select='*', condition_hash=insert_hash)
        if row is not None and row.rows() > 0:
            return row
        else:
            return self.create(table=table, insert_hash=insert_hash)

    # noinspection PyMethodMayBeStatic
    def dbh(self):
        raise Exception("Please don't use internal database handler directly")
