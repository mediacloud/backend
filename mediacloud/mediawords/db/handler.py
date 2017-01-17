import os
import random
import re
from typing import Callable, Union, List, Dict, Any

import psycopg2
import psycopg2.extras
from psycopg2.extensions import adapt as psycopg2_adapt

from mediawords.db.copy.copy_from import CopyFrom
from mediawords.db.copy.copy_to import CopyTo
from mediawords.db.exceptions.handler import *
from mediawords.db.statement.statement import DatabaseStatement
from mediawords.db.pages.pages import DatabasePages
from mediawords.db.result.result import DatabaseResult
from mediawords.db.schema.version import schema_version_from_lines

from mediawords.util.config import get_config
from mediawords.util.log import create_logger
from mediawords.util.paths import mc_root_path
from mediawords.util.perl import convert_dbd_pg_arguments_to_psycopg2_format, decode_object_from_bytes_if_needed, \
    McDecodeObjectFromBytesIfNeededException

l = create_logger(__name__)

# Set to the module in addition to connection so that adapt() returns what it should
# noinspection PyArgumentList
psycopg2.extensions.register_type(psycopg2.extensions.UNICODE)
# noinspection PyArgumentList
psycopg2.extensions.register_type(psycopg2.extensions.UNICODEARRAY)


# FIXME test if autocommit can be toggled with database cursor enabled
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

    # Whether or not to print PostgreSQL warnings
    __print_warnings = True

    # Debugging variable to test whether we're in a transaction
    __in_manual_transaction = False

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
        """Database handler constructor; connects to PostgreSQL too."""

        host = decode_object_from_bytes_if_needed(host)
        username = decode_object_from_bytes_if_needed(username)
        password = decode_object_from_bytes_if_needed(password)
        database = decode_object_from_bytes_if_needed(database)

        self.__connect(
            host=host,
            port=port,
            username=username,
            password=password,
            database=database,
            do_not_check_schema_version=do_not_check_schema_version
        )

    def __connect(self,
                  host: str,
                  port: int,
                  username: str,
                  password: str,
                  database: str,
                  do_not_check_schema_version: bool = False) -> None:
        """Connect to PostgreSQL."""

        host = decode_object_from_bytes_if_needed(host)
        username = decode_object_from_bytes_if_needed(username)
        password = decode_object_from_bytes_if_needed(password)
        database = decode_object_from_bytes_if_needed(database)

        # If the user didn't clearly (via 'true' or 'false') state whether or not
        # to check schema version, check it once per PID
        pid = os.getpid()

        if not (host and username and password and database):
            raise McConnectException("Database connection credentials are not set.")

        if not port:
            port = 5432

        if not do_not_check_schema_version:
            if pid in self.__schema_version_check_pids:
                do_not_check_schema_version = True
            else:
                do_not_check_schema_version = False

        self.__conn = psycopg2.connect(host=host, port=port, user=username, password=password, database=database)

        psycopg2.extensions.register_type(psycopg2.extensions.UNICODE, self.__conn)
        psycopg2.extensions.register_type(psycopg2.extensions.UNICODEARRAY, self.__conn)

        # Magic bits for psycopg2 to start supporting UTF-8
        self.__conn.set_client_encoding(psycopg2.extensions.encodings['UTF8'])

        # psycopg2.extras.DictCursor factory enables server-side query prepares so all result data does not get fetched
        # at once
        cursor_factory = psycopg2.extras.DictCursor
        self.__db = self.__conn.cursor(cursor_factory=cursor_factory)

        # Queries to have immediate effect by default
        self.set_autocommit(True)

        if not do_not_check_schema_version:
            if not self.schema_is_up_to_date():
                # It would make sense to check the MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION environment variable
                # at this particular point too, but schema_is_up_to_date() warns the user about schema being
                # too old on every run, and that's supposedly a good thing.
                raise McConnectException("Database schema is not up-to-date.")

        # If schema is not up-to-date, connect() dies and we don't get to set PID here
        self.__schema_version_check_pids[pid] = True

        # Check deadlock_timeout
        (deadlock_timeout,) = self.query("SHOW deadlock_timeout").flat()
        deadlock_timeout = re.sub(r'\s*s$', '', deadlock_timeout, re.I)
        deadlock_timeout = int(deadlock_timeout)
        if deadlock_timeout == 0:
            raise McConnectException("'deadlock_timeout' is 0, probably unable to read it")
        if deadlock_timeout < self.__MIN_DEADLOCK_TIMEOUT:
            l.warn('"deadlock_timeout" is less than "%ds", expect deadlocks on high extractor load' %
                   self.__MIN_DEADLOCK_TIMEOUT)

    def disconnect(self) -> None:
        """Disconnect from the database."""
        self.__db.close()
        self.__db = None

        self.__conn.close()
        self.__db = None

    # noinspection PyMethodMayBeStatic
    def dbh(self) -> None:
        raise McDatabaseHandlerException("Please don't use internal database handler directly")

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
        root_dir = mc_root_path()

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
            raise McSchemaIsUpToDateException("Current schema version is 0")

        # Target schema version
        sql = open(os.path.join(root_dir, 'schema', 'mediawords.sql'), 'r').read()
        target_schema_version = schema_version_from_lines(sql)
        if not target_schema_version:
            raise McSchemaIsUpToDateException("Invalid target schema version.")

        # Check if the current schema is up-to-date
        if current_schema_version != target_schema_version:
            return self.__should_continue_with_outdated_schema(current_schema_version, target_schema_version)
        else:
            # Things are fine at this point.
            return True

    def query(self, *query_params) -> DatabaseResult:
        """Run the query, return instance of DatabaseResult for accessing the result.

        Accepts either (preferred) psycopg2-style query and parameters:

            db.query('SELECT * FROM foo WHERE bar = %s AND baz = %s', (bar, baz,))
            db.query('SELECT * FROM foo WHERE bar = %(bar)s AND baz = %(baz)s', {'bar': bar, 'baz': baz})

        ...or DBD::Pg (DBIx::Simple) form of query and parameters:

            db.query('SELECT * FROM foo WHERE bar = ? AND baz = ?', bar, baz)
        """

        # MC_REWRITE_TO_PYTHON: remove after porting queries to named parameter style
        query_params = convert_dbd_pg_arguments_to_psycopg2_format(*query_params)

        if len(query_params) == 0:
            raise McQueryException("Query is unset.")
        if len(query_params) > 2:
            raise McQueryException("psycopg2's execute() accepts at most 2 parameters.")

        return DatabaseResult(cursor=self.__db, query_args=query_params, print_warnings=self.__print_warnings)

    def prepare(self, sql: str) -> DatabaseStatement:
        """Return a prepared statement."""
        # MC_REWRITE_TO_PYTHON get rid of it because it was useful only for writing BYTEA cells; psycopg2 can just
        # use 'bytes' arguments

        sql = decode_object_from_bytes_if_needed(sql)

        return DatabaseStatement(cursor=self.__db, sql=sql)

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
        new_work_mem = decode_object_from_bytes_if_needed(new_work_mem)
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

        table = decode_object_from_bytes_if_needed(table)

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
                raise McPrimaryKeyColumnException("Primary key for table '%s' was not found" % table)
            if len(primary_key_column) > 1:
                raise McPrimaryKeyColumnException(
                    "More than one primary key column was found for table '%(table)s': %(primary_key_columns)s" % {
                        'table': table,
                        'primary_key_columns': str(primary_key_column)
                    })
            primary_key_column = primary_key_column[0]

            self.__primary_key_columns[table] = primary_key_column

        return self.__primary_key_columns[table]

    def find_by_id(self, table: str, object_id: int) -> DatabaseResult:
        """Do an ID lookup on the table and return a single row match if found."""

        table = decode_object_from_bytes_if_needed(table)

        primary_key_column = self.primary_key_column(table)
        if not primary_key_column:
            raise McFindByIDException("Primary key for table '%s' was not found" % table)

        # Python substitution
        find_by_id_query = "SELECT * FROM %(table)s WHERE %(id_column)s" % {
            "table": table,
            "id_column": primary_key_column,
        }

        # psycopg2 substitution
        return self.query(find_by_id_query + " = %(id_value)s", {'id_value': object_id})

    def require_by_id(self, table: str, object_id: int) -> DatabaseResult:
        """find_by_id() or raise exception if not found."""

        table = decode_object_from_bytes_if_needed(table)

        row = self.find_by_id(table, object_id)
        if row is None or row.rows() == 0:
            raise McRequireByIDException("Unable to find id '%d' in table '%s'" % (object_id, table))
        return row

    def update_by_id(self, table: str, object_id: int, update_hash: dict) -> DatabaseResult:
        """Update the row in the table with the given ID. Ignore any fields that start with '_'."""

        table = decode_object_from_bytes_if_needed(table)
        update_hash = decode_object_from_bytes_if_needed(update_hash)

        update_hash = update_hash.copy()  # To be able to safely modify it

        # MC_REWRITE_TO_PYTHON: remove after getting rid of Catalyst
        if "submit" in update_hash:
            del update_hash["submit"]

        update_hash = {k: v for k, v in update_hash.items() if not k.startswith("_")}

        if len(update_hash) == 0:
            raise McUpdateByIDException("Hash to UPDATE is empty.")

        primary_key_column = self.primary_key_column(table)
        if not primary_key_column:
            raise McUpdateByIDException("Primary key for table '%s' was not found" % table)

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

    def delete_by_id(self, table: str, object_id: int) -> DatabaseResult:
        """Delete the row in the table with the given ID."""

        table = decode_object_from_bytes_if_needed(table)

        primary_key_column = self.primary_key_column(table)
        if not primary_key_column:
            raise McDeleteByIDException("Primary key for table '%s' was not found" % table)

        sql = "DELETE FROM %s " % table
        sql += "WHERE %s = " % primary_key_column
        sql += "%(__object_id)s"  # "%(object_id)s" to be resolved by psycopg2, not Python

        return self.query(sql, {"__object_id": object_id})

    def insert(self, table: str, insert_hash: dict) -> DatabaseResult:
        """Alias for create()."""
        table = decode_object_from_bytes_if_needed(table)
        insert_hash = decode_object_from_bytes_if_needed(insert_hash)

        return self.create(table=table, insert_hash=insert_hash)

    def create(self, table: str, insert_hash: dict) -> DatabaseResult:
        """Insert a row into the database for the given table with the given hash values and return the created row."""

        table = decode_object_from_bytes_if_needed(table)
        insert_hash = decode_object_from_bytes_if_needed(insert_hash)

        insert_hash = insert_hash.copy()  # To be able to safely modify it

        # MC_REWRITE_TO_PYTHON: remove after getting rid of Catalyst
        if "submit" in insert_hash:
            del insert_hash["submit"]

        if len(insert_hash) == 0:
            raise McCreateException("Hash to INSERT is empty")

        primary_key_column = self.primary_key_column(table)
        if not primary_key_column:
            raise McCreateException("Primary key for table '%s' was not found" % table)

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
            raise McCreateException("Last inserted ID was not found")
        last_inserted_id = last_inserted_id[0]

        inserted_row = self.find_by_id(table=table, object_id=last_inserted_id)
        if inserted_row is None:
            raise McCreateException("Could not find new ID %d in table '%s'" % (last_inserted_id, table))

        return inserted_row

    def select(self, table: str, what_to_select: str, condition_hash: dict = None) -> DatabaseResult:
        """SELECT chosen columns from the table that match given conditions."""

        table = decode_object_from_bytes_if_needed(table)
        what_to_select = decode_object_from_bytes_if_needed(what_to_select)
        condition_hash = decode_object_from_bytes_if_needed(condition_hash)

        if condition_hash is None:
            condition_hash = {}

        condition_hash = condition_hash.copy()  # To be able to safely modify it

        # MC_REWRITE_TO_PYTHON: remove after getting rid of Catalyst
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

    def find_or_create(self, table: str, insert_hash: dict) -> DatabaseResult:
        """Select a single row from the database matching the hash or insert a row with the hash values and return the
        inserted row as a hash."""

        table = decode_object_from_bytes_if_needed(table)
        insert_hash = decode_object_from_bytes_if_needed(insert_hash)

        insert_hash = insert_hash.copy()  # To be able to safely modify it

        if len(insert_hash) == 0:
            raise McFindOrCreateException("Hash to INSERT or SELECT is empty")

        # MC_REWRITE_TO_PYTHON: remove after getting rid of Catalyst
        if "submit" in insert_hash:
            del insert_hash["submit"]

        row = self.select(table=table, what_to_select='*', condition_hash=insert_hash)
        if row is not None and row.rows() > 0:
            return row
        else:
            return self.create(table=table, insert_hash=insert_hash)

    def autocommit(self) -> bool:
        """Return True if autocommit mode is on."""
        return self.__conn.autocommit

    def set_autocommit(self, autocommit: bool) -> None:
        """Set autocommit mode."""
        self.__conn.autocommit = autocommit

    # noinspection PyMethodMayBeStatic
    def show_error_statement(self) -> bool:
        """Return whether failed SQL statement will be included into thrown exception."""
        # FIXME I suppose psycopg2 always returns failed statement?
        # MC_REWRITE_TO_PYTHON remove after porting
        return True

    # noinspection PyMethodMayBeStatic
    def set_show_error_statement(self, show_error_statement: bool) -> None:
        """Set whether failed SQL statement will be included into thrown exception."""
        # FIXME I suppose psycopg2 always returns failed statement?
        # MC_REWRITE_TO_PYTHON remove after porting
        pass

    # noinspection PyMethodMayBeStatic
    def prepare_on_server_side(self) -> bool:
        """Return whether queries are being prepared on server-side."""
        # MC_REWRITE_TO_PYTHON prepare_on_server_side() was being used to get around DBD::Pg's bug, so probably not
        # needed anymore

        # Always prepared on server-side because of psycopg2.extras.DictCursor, see:
        # https://wiki.postgresql.org/wiki/Using_psycopg2_with_PostgreSQL#Fetch_Records_using_a_Server-Side_Cursor
        return True

    # noinspection PyMethodMayBeStatic
    def set_prepare_on_server_side(self, prepare_on_server_side: bool) -> None:
        """Set whether queries are being prepared on server-side."""
        # MC_REWRITE_TO_PYTHON set_prepare_on_server_side() was being used to get around DBD::Pg's bug, so probably not
        # needed anymore
        pass

    def print_warn(self) -> bool:
        """Return whether PostgreSQL warnings will be printed."""
        return self.__print_warnings

    def set_print_warn(self, print_warn: bool) -> None:
        """Set whether PostgreSQL warnings will be printed."""
        self.__print_warnings = print_warn

    def begin(self) -> None:
        """Begin a transaction."""
        if self.autocommit():
            l.warn("Autocommit is enabled, are you sure you want to start a transaction?")
        if self.__in_manual_transaction:
            l.warn("We're already in the middle of a manual transaction, the query will probably fail")

        self.query('BEGIN')
        self.__in_manual_transaction = True

    def begin_work(self) -> None:
        """Begin a transaction."""
        return self.begin()

    def commit(self) -> None:
        """Commit a transaction."""
        if self.autocommit():
            l.warn("Autocommit is enabled, are you sure you want to commit a transaction?")
        if not self.__in_manual_transaction:
            l.warn("We're not in the middle of a manual transaction, the query will probably fail")

        self.query('COMMIT')
        self.__in_manual_transaction = False

    def rollback(self) -> None:
        """Rollback a transaction."""
        if self.autocommit():
            l.warn("Autocommit is enabled, are you sure you want to rollback a transaction?")
        if not self.__in_manual_transaction:
            l.warn("We're not in the middle of a manual transaction, the query will probably fail")

        self.query('ROLLBACK')
        self.__in_manual_transaction = False

    @staticmethod
    def quote(value: Union[bool, int, float, str, None]) -> str:
        """Quote a string for being passed as a literal in a query."""

        value = decode_object_from_bytes_if_needed(value)

        quoted_obj = None
        try:
            # Docs say that: "While the original adapt() takes 3 arguments, psycopg2's one only takes 1: the bound
            # variable to be adapted", so:
            #
            # noinspection PyArgumentList
            quoted_obj = psycopg2_adapt(value)

            if hasattr(quoted_obj, 'encoding'):  # integer adaptors don't support encoding for example
                # Otherwise string gets treated as Latin-1:
                quoted_obj.encoding = psycopg2.extensions.encodings['UTF8']

        except Exception as ex:
            raise McQuoteException("psycopg2_adapt() failed while quoting '%s': %s" % (quoted_obj, str(ex)))
        if quoted_obj is None:
            raise McQuoteException("psycopg2_adapt() returned None while quoting '%s'" % quoted_obj)

        try:
            quoted_value = quoted_obj.getquoted()
        except Exception as ex:
            raise McQuoteException("getquoted() failed while quoting '%s': %s" % (quoted_obj, str(ex)))
        if quoted_value is None:
            raise McQuoteException("getquoted() returned None while quoting '%s'" % quoted_obj)

        if isinstance(quoted_value, bytes):
            quoted_value = quoted_value.decode(encoding='utf-8', errors='replace')

        if not isinstance(quoted_value, str):
            # Maybe overly paranoid, but better than returning random stuff for a string that will go into the database
            raise McQuoteException("Quoted value is not 'str' after quoting '%s'" % quoted_obj)

        return quoted_value

    @staticmethod
    def quote_bool(value: bool) -> str:
        """Quote a boolean value for being passed as a literal in a query."""
        # FIXME probably there's no point in having this as an alias
        return DatabaseHandler.quote(value=value)

    @staticmethod
    def quote_varchar(value: str) -> str:
        """Quote VARCHAR for being passed as a literal in a query."""
        # FIXME probably there's no point in having this as an alias
        value = decode_object_from_bytes_if_needed(value)

        return DatabaseHandler.quote(value=value)

    @staticmethod
    def quote_date(value: str) -> str:
        """Quote DATE for being passed as a literal in a query."""
        value = decode_object_from_bytes_if_needed(value)

        return '%s::date' % DatabaseHandler.quote(value=value)

    @staticmethod
    def quote_timestamp(value: str) -> str:
        """Quote TIMESTAMP for being passed as a literal in a query."""
        value = decode_object_from_bytes_if_needed(value)

        return '%s::timestamp' % DatabaseHandler.quote(value=value)

    def copy_from(self, sql: str) -> CopyFrom:
        """Return COPY FROM helper object."""
        sql = decode_object_from_bytes_if_needed(sql)

        return CopyFrom(cursor=self.__db, sql=sql)

    def copy_to(self, sql: str) -> CopyTo:
        """Return COPY TO helper object."""
        sql = decode_object_from_bytes_if_needed(sql)

        return CopyTo(cursor=self.__db, sql=sql)

    def get_temporary_ids_table(self, ids: List[int], ordered: bool = False) -> str:
        """Get the name of a temporary table that contains all of the IDs in "ids" as an "id BIGINT" field.

        The database connection must be within a transaction. The temporary table is setup to be dropped at the end of
        the current transaction. If "ordered" is True, include an "<...>_id SERIAL PRIMARY KEY" field in the table."""

        r = random.SystemRandom()  # FIXME replace with "secrets" module after upgrading to Python 3.6
        table_name = '_tmp_ids_%s' % str(r.randrange(2 ** 64))

        l.debug("Temporary IDs table: %s" % table_name)

        primary_key_clause = ""
        if ordered:
            primary_key_clause = "%s_pkey SERIAL PRIMARY KEY," % table_name

        sql = """CREATE TEMPORARY TABLE %s (""" % table_name
        sql += primary_key_clause
        sql += "id BIGINT)"
        self.query(sql)

        copy = self.copy_from("COPY %s (id) FROM STDIN" % table_name)
        for single_id in ids:
            copy.put_line("%d\n" % single_id)
        copy.end()

        self.query("ANALYZE %s" % table_name)

        return table_name

    def attach_child_query(self,
                           data: List[Dict[str, Any]],
                           child_query: str,
                           child_field: str,
                           id_column: str,
                           single: bool = False) -> List[Dict[str, Any]]:
        """For each row in "data", attach all results in the child query that match a JOIN with the "id_column" field in
        each row of "data".

        Then, attach to "row[child_field]":

        * If "single" is True, the "child_field" column in the corresponding row in "data";

        * If "single" is False, a list of values for each row in "data".

        For an example on how this works, see test_attach_child_query() in test_handler.py."""

        # FIXME get rid of this hard to understand reimplementation of JOIN which is here due to the sole reason that
        # _add_nested_data() is hard to refactor out and no one bothered to do it.

        data = decode_object_from_bytes_if_needed(data)
        if not isinstance(data, list):
            raise McDecodeObjectFromBytesIfNeededException(
                "'data' is not a list anymore after converting: %s" % str(data)
            )
        data = list(data)  # get rid of return type warning by enforcing that 'data' is still a list
        child_query = decode_object_from_bytes_if_needed(child_query)
        child_field = decode_object_from_bytes_if_needed(child_field)
        id_column = decode_object_from_bytes_if_needed(id_column)

        parent_lookup = {}
        ids = []
        for parent in data:
            parent_id = parent[id_column]

            parent_lookup[parent_id] = parent
            ids.append(parent_id)

        ids_table = self.get_temporary_ids_table(ids=ids)
        sql = """
            -- noinspection SqlResolve
            SELECT q.*
            FROM ( %(child_query)s ) AS q
                -- Limit rows returned by "child_query" to only IDs from "ids"
                INNER JOIN %(ids_table)s AS ids
                    ON q.%(id_column)s = ids.id
        """ % {
            'child_query': child_query,
            'ids_table': ids_table,
            'id_column': id_column,
        }
        children = self.query(sql).hashes()

        for child in children:
            child_id = child[id_column]
            parent = parent_lookup[child_id]

            if single:
                parent[child_field] = child[child_field]
            else:
                if child_field not in parent:
                    parent[child_field] = []
                parent[child_field].append(child)

        return data

    def query_paged_hashes(self, query: str, page: int, rows_per_page: int) -> DatabasePages:
        """Execute the query and return a list of pages hashes."""

        query = decode_object_from_bytes_if_needed(query)

        return DatabasePages(cursor=self.__db, query=query, page=page, rows_per_page=rows_per_page)
