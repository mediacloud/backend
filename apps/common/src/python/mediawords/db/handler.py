import os
import re
import socket
from typing import Union, List, Dict, Any

import psycopg2
import psycopg2.extras
from psycopg2.extensions import adapt as psycopg2_adapt

from mediawords.db.copy.copy_from import CopyFrom
from mediawords.db.copy.copy_to import CopyTo
from mediawords.db.exceptions.handler import (
    McConnectException, McDatabaseHandlerException, McQueryException,
    McPrimaryKeyColumnException, McFindByIDException, McRequireByIDException, McUpdateByIDException,
    McDeleteByIDException, McCreateException, McFindOrCreateException, McBeginException,
    McQuoteException, McUniqueConstraintException)
from mediawords.db.result.result import DatabaseResult

from mediawords.util.log import create_logger
from mediawords.util.perl import (
    convert_dbd_pg_arguments_to_psycopg2_format,
    decode_object_from_bytes_if_needed,
    McDecodeObjectFromBytesIfNeededException,
)
from mediawords.util.text import random_string

log = create_logger(__name__)

# Set to the module in addition to connection so that adapt() returns what it should
psycopg2.extensions.register_type(psycopg2.extensions.UNICODE, None)
psycopg2.extensions.register_type(psycopg2.extensions.UNICODEARRAY, None)


class DatabaseHandler(object):
    """PostgreSQL middleware (imitates DBIx::Simple's interface)."""

    # "Double percentage sign" marker (see handler's quote() for explanation)
    __DOUBLE_PERCENTAGE_SIGN_MARKER = "<DOUBLE PERCENTAGE SIGN: " + random_string(length=16) + ">"

    __slots__ = [

        # Cache of table primary key columns ([schema][table])
        '__primary_key_columns',

        # Whether or not to print PostgreSQL warnings
        '__print_warnings',

        # Debugging variable to test whether we're in a transaction
        '__in_manual_transaction',

        # Pyscopg2 instance and cursor
        '__conn',
        '__db',

    ]

    def __init__(self,
                 host: str,
                 port: int,
                 username: str,
                 password: str,
                 database: str):
        """Database handler constructor; connects to PostgreSQL too."""

        host = decode_object_from_bytes_if_needed(host)
        # noinspection PyTypeChecker
        port = int(decode_object_from_bytes_if_needed(port))
        username = decode_object_from_bytes_if_needed(username)
        password = decode_object_from_bytes_if_needed(password)
        database = decode_object_from_bytes_if_needed(database)

        self.__primary_key_columns = {}
        self.__print_warnings = True
        self.__in_manual_transaction = False
        self.__conn = None
        self.__db = None

        self.__connect(
            host=host,
            port=port,
            username=username,
            password=password,
            database=database,
        )

    def __connect(self,
                  host: str,
                  port: int,
                  username: str,
                  password: str,
                  database: str) -> None:
        """Connect to PostgreSQL."""

        host = decode_object_from_bytes_if_needed(host)
        # noinspection PyTypeChecker
        port = int(decode_object_from_bytes_if_needed(port))
        username = decode_object_from_bytes_if_needed(username)
        password = decode_object_from_bytes_if_needed(password)
        database = decode_object_from_bytes_if_needed(database)

        if not (host and username and password and database):
            raise McConnectException("Database connection credentials are not set.")

        if not port:
            port = 5432

        application_name = '%s %d' % (socket.gethostname(), os.getpid())

        self.__conn = psycopg2.connect(
            host=host,
            port=port,
            user=username,
            password=password,
            database=database,
            application_name=application_name
        )

        # Magic bits for psycopg2 to start supporting UTF-8
        psycopg2.extensions.register_type(psycopg2.extensions.UNICODE, self.__conn)
        psycopg2.extensions.register_type(psycopg2.extensions.UNICODEARRAY, self.__conn)
        self.__conn.set_client_encoding(psycopg2.extensions.encodings['UTF8'])

        # Don't automatically decode JSON, just like DBD::Pg doesn't
        # MC_REWRITE_TO_PYTHON: (probably) remove after porting
        psycopg2.extras.register_default_json(loads=lambda x: x)

        # psycopg2.extras.DictCursor factory enables server-side query prepares so all result data does not get fetched
        # at once
        cursor_factory = psycopg2.extras.DictCursor
        self.__db = self.__conn.cursor(cursor_factory=cursor_factory)

        # Queries to have immediate effect by default
        self.__conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)

    def disconnect(self) -> None:
        """Disconnect from the database."""
        self.__db.close()
        self.__db = None

        self.__conn.close()
        self.__db = None

    # noinspection PyMethodMayBeStatic
    def dbh(self) -> None:
        raise McDatabaseHandlerException("Please don't use internal database handler directly")

    def query(self, *query_params) -> DatabaseResult:
        """Run the query, return instance of DatabaseResult for accessing the result.

        Accepts either (preferred) psycopg2-style query and parameters:

            # Dictionary parameters (preferred):
            db.query('SELECT * FROM foo WHERE bar = %(bar)s AND baz = %(baz)s', {'bar': bar, 'baz': baz})

            # Dictionary parameters with tuple:
            db.query('SELECT * FROM foo WHERE bar IN %(bar)s, {'bar': tuple(['a', 'b', 'c'])})

            # Tuple parameters:
            db.query('SELECT * FROM foo WHERE bar = %s AND baz = %s', (bar, baz,))

        ...or DBD::Pg (DBIx::Simple) form of query and parameters:

            db.query('SELECT * FROM foo WHERE bar = ? AND baz = ?', bar, baz)
        """

        # MC_REWRITE_TO_PYTHON: remove after porting queries to named parameter style
        query_params = convert_dbd_pg_arguments_to_psycopg2_format(*query_params)

        if len(query_params) == 0:
            raise McQueryException("Query is unset.")
        if len(query_params) > 2:
            raise McQueryException("psycopg2's execute() accepts at most 2 parameters.")

        return DatabaseResult(cursor=self.__db,
                              query_args=query_params,
                              double_percentage_sign_marker=DatabaseHandler.__DOUBLE_PERCENTAGE_SIGN_MARKER,
                              print_warnings=self.__print_warnings)

    def primary_key_column(self, object_name: str) -> str:
        """Get INT / BIGINT primary key column name for a table or a view.

        If the table has a composite primary key, return the first INT / BIGINT column name.
        """

        object_name = decode_object_from_bytes_if_needed(object_name)

        if '.' in object_name:
            schema_name, object_name = object_name.split('.', maxsplit=1)
        else:
            schema_name = 'public'

        if schema_name not in self.__primary_key_columns:
            self.__primary_key_columns[schema_name] = {}

        if object_name not in self.__primary_key_columns[schema_name]:

            # noinspection SpellCheckingInspection,SqlResolve
            columns = self.query("""
                SELECT
                    n.nspname AS schema_name,
                    c.relname AS object_name,
                    c.relkind AS object_type,
                    a.attname AS column_name,
                    i.indisprimary AS is_primary_index,
                    t.typname AS column_type,
                    t.typcategory AS column_type_category

                FROM pg_namespace AS n
                    INNER JOIN pg_class AS c
                        ON n.oid = c.relnamespace
                    INNER JOIN pg_attribute AS a
                        ON a.attrelid = c.oid
                        AND NOT a.attisdropped
                    INNER JOIN pg_type AS t
                      ON a.atttypid = t.oid

                    -- Object might be a view, so LEFT JOIN
                    LEFT JOIN pg_index AS i
                        ON c.oid = i.indrelid
                        AND a.attnum = ANY(i.indkey)

                WHERE

                  -- No xid, cid, ...
                  a.attnum > 0

                  -- Live column
                  AND NOT attisdropped

                  -- Numeric (INT or BIGINT)
                  AND t.typcategory = 'N'

                  AND n.nspname = %(schema_name)s
                  AND c.relname = %(object_name)s

                -- In case of a composite PK, select the first numeric column
                ORDER BY a.attnum
            """, {
                'schema_name': schema_name,
                'object_name': object_name,
            }).hashes()
            if not columns:
                raise McPrimaryKeyColumnException(
                    "Object '{}' in schema '{} was not found.".format(schema_name, object_name)
                )

            primary_key_column = None

            for column in columns:

                column_name = column['column_name']

                if column['object_type'] in ['r', 'p']:
                    # Table
                    if column['is_primary_index']:
                        primary_key_column = column_name
                        break

                elif column['object_type'] in ['v', 'm']:
                    # (Materialized) view
                    if column['column_name'] == 'id' or column['column_name'] == '{}_id'.format(object_name):
                        primary_key_column = column_name
                        break

            if not primary_key_column:
                raise McPrimaryKeyColumnException(
                    "Primary key for schema '%s', object '%s' was not found" % (schema_name, object_name,)
                )

            self.__primary_key_columns[schema_name][object_name] = primary_key_column

        return self.__primary_key_columns[schema_name][object_name]

    def find_by_id(self, table: str, object_id: int) -> Union[Dict[str, Any], None]:
        """Do an ID lookup on the table and return a single row match if found."""

        # MC_REWRITE_TO_PYTHON: some IDs get passed as 'str' / 'bytes'; remove after getting rid of Catalyst
        # noinspection PyTypeChecker
        object_id = decode_object_from_bytes_if_needed(object_id)
        object_id = int(object_id)

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
        result = self.query(find_by_id_query + " = %(id_value)s", {'id_value': object_id})
        if result.rows() > 1:
            raise McFindByIDException("More than one row was found for ID '%d' from table '%s'" % (object_id, table))
        elif result.rows() == 1:
            return result.hash()
        else:
            return None

    def require_by_id(self, table: str, object_id: int) -> Dict[str, Any]:
        """find_by_id() or raise exception if not found."""

        # MC_REWRITE_TO_PYTHON: some IDs get passed as 'str' / 'bytes'; remove after getting rid of Catalyst
        # noinspection PyTypeChecker
        object_id = decode_object_from_bytes_if_needed(object_id)
        object_id = int(object_id)

        table = decode_object_from_bytes_if_needed(table)

        row = self.find_by_id(table, object_id)
        if row is None:
            raise McRequireByIDException("Unable to find ID '%d' in table '%s'" % (object_id, table))
        return row

    def update_by_id(self, table: str, object_id: int, update_hash: dict) -> Union[Dict[str, Any], None]:
        """Update the row in the table with the given ID. Ignore any fields that start with '_'."""

        # MC_REWRITE_TO_PYTHON: some IDs get passed as 'str' / 'bytes'; remove after getting rid of Catalyst
        # noinspection PyTypeChecker
        object_id = decode_object_from_bytes_if_needed(object_id)
        object_id = int(object_id)

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

            # Cast Inline::Python's booleans to Python's booleans
            # MC_REWRITE_TO_PYTHON: remove after porting
            if type(value).__name__ == '_perl_obj':
                value = bool(value)
                update_hash[key] = value

            key_value += " = %(" + key + ")s"  # "%(key)s" to be resolved by psycopg2, not Python

            keys.append(key_value)

        update_hash['__object_id'] = object_id

        sql = "UPDATE %s " % table
        sql += "SET %s " % ", ".join(keys)
        sql += "WHERE %s = " % primary_key_column
        sql += "%(__object_id)s"  # "%(__object_id)s" to be resolved by psycopg2, not Python

        self.query(sql, update_hash)

        updated_row = self.find_by_id(table=table, object_id=object_id)

        return updated_row

    def delete_by_id(self, table: str, object_id: int) -> None:
        """Delete the row in the table with the given ID."""

        # MC_REWRITE_TO_PYTHON: some IDs get passed as 'str' / 'bytes'; remove after getting rid of Catalyst
        # noinspection PyTypeChecker
        object_id = decode_object_from_bytes_if_needed(object_id)
        object_id = int(object_id)

        table = decode_object_from_bytes_if_needed(table)

        primary_key_column = self.primary_key_column(table)
        if not primary_key_column:
            raise McDeleteByIDException("Primary key for table '%s' was not found" % table)

        # noinspection SqlWithoutWhere
        sql = "DELETE FROM %s " % table
        sql += "WHERE %s = " % primary_key_column
        sql += "%(__object_id)s"  # "%(object_id)s" to be resolved by psycopg2, not Python

        self.query(sql, {"__object_id": object_id})

    def insert(self, table: str, insert_hash: dict) -> Dict[str, Any]:
        """Alias for create()."""
        table = decode_object_from_bytes_if_needed(table)
        insert_hash = decode_object_from_bytes_if_needed(insert_hash)

        return self.create(table=table, insert_hash=insert_hash)

    def create(self, table: str, insert_hash: dict) -> Dict[str, Any]:
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

            # Cast Inline::Python's booleans to Python's booleans
            # MC_REWRITE_TO_PYTHON: remove after porting
            if type(value).__name__ == '_perl_obj':
                value = bool(value)
                insert_hash[key] = value

        sql = "INSERT INTO %s " % table
        sql += "(%s) " % ", ".join(keys)
        sql += "VALUES (%s) " % ", ".join(values)
        sql += "RETURNING %s" % primary_key_column

        try:
            last_inserted_id = self.query(sql, insert_hash).flat()
        except Exception as ex:
            if 'duplicate key value violates unique constraint' in str(ex):
                raise McUniqueConstraintException("Unable to INSERT into '%(table)s' data '%(data)s': %(exception)s" % {
                    'table': table,
                    'data': str(insert_hash),
                    'exception': str(ex),
                })
            else:
                raise ex

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

            # Cast Inline::Python's booleans to Python's booleans
            # MC_REWRITE_TO_PYTHON: remove after porting
            if type(value).__name__ == '_perl_obj':
                value = bool(value)
                condition_hash[key] = value

        sql = "SELECT %s " % what_to_select
        sql += "FROM %s " % table
        if len(sql_conditions) > 0:
            sql += "WHERE %s" % " AND ".join(sql_conditions)

        return self.query(sql, condition_hash)

    def find_or_create(self, table: str, insert_hash: dict) -> Dict[str, Any]:
        """Select a single row from the database matching the hash or insert a row with the hash values and return the
        inserted row as a hash."""

        # FIXME probably do this in a serialized transaction?

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
            return row.hash()
        else:
            # try to create it, but if some other process has created it because we don't have a lock, just use that one
            try:
                return self.create(table=table, insert_hash=insert_hash)
            except McUniqueConstraintException:
                return self.select(table=table, what_to_select='*', condition_hash=insert_hash).hash()

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

    def print_warn(self) -> bool:
        """Return whether PostgreSQL warnings will be printed."""
        return self.__print_warnings

    def set_print_warn(self, print_warn: bool) -> None:
        """Set whether PostgreSQL warnings will be printed."""
        self.__print_warnings = print_warn

    def in_transaction(self) -> bool:
        """Return True if we're within a manually started transaction."""
        return self.__in_manual_transaction

    def __set_in_transaction(self, in_transaction: bool) -> None:
        if self.__in_manual_transaction == in_transaction:
            log.warning("Setting self.__in_manual_transaction to the same value (%s)" % str(in_transaction))
        self.__in_manual_transaction = in_transaction

    def begin(self) -> None:
        """Begin a transaction."""
        if self.in_transaction():
            raise McBeginException("Already in transaction, can't BEGIN.")

        self.query('BEGIN')
        self.__set_in_transaction(True)

    def begin_work(self) -> None:
        """Begin a transaction."""
        return self.begin()

    def commit(self) -> None:
        """Commit a transaction."""
        if not self.in_transaction():
            log.debug("Not in transaction, nothing to COMMIT.")
        else:
            self.query('COMMIT')
            self.__set_in_transaction(False)

    def rollback(self) -> None:
        """Rollback a transaction."""
        if not self.in_transaction():
            log.warning("Not in transaction, nothing to ROLLBACK.")
        else:
            self.query('ROLLBACK')
            self.__set_in_transaction(False)

    # noinspection PyMethodMayBeStatic
    def quote(self, value: Union[bool, int, float, str, None]) -> str:
        """Quote a string for being passed as a literal in a query.

        Also, replace all cases of a percentage sign ('%') with a random string shared within database handler's
        instance which will be later replaced back into double percentage sign ('%%') when executing the query."""

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

        # Replace percentage signs with a randomly generated marker that will be replaced back into '%%' when executing
        # the query.
        quoted_value = quoted_value.replace('%', DatabaseHandler.__DOUBLE_PERCENTAGE_SIGN_MARKER)

        return quoted_value

    def quote_bool(self, value: bool) -> str:
        """Quote a boolean value for being passed as a literal in a query."""
        # MC_REWRITE_TO_PYTHON: remove after starting to use Python's boolean type everywhere

        if isinstance(value, bool):
            pass
        elif isinstance(value, int):
            if value == 0:
                value = False
            elif value == 1:
                value = True
            else:
                raise McQuoteException("Value '%s' is neither 0 nor 1" % str(value))
        elif isinstance(value, str) or isinstance(value, bytes):
            value = decode_object_from_bytes_if_needed(value)
            if value.lower() in ['t', 'true', 'y', 'yes', 'on', '1']:
                value = True
            elif value.lower() in ['f', 'false', 'n', 'no', 'off', '0']:
                value = False
            else:
                raise McQuoteException("Value '%s' is string but neither of supported values" % str(value))
        else:
            raise McQuoteException("Value '%s' is unsupported" % str(value))

        return self.quote(value=value)

    def quote_varchar(self, value: str) -> str:
        """Quote VARCHAR for being passed as a literal in a query."""
        # MC_REWRITE_TO_PYTHON: remove after starting to use Python's boolean type everywhere
        value = decode_object_from_bytes_if_needed(value)

        return self.quote(value=value)

    def quote_date(self, value: str) -> str:
        """Quote DATE for being passed as a literal in a query."""
        value = decode_object_from_bytes_if_needed(value)

        return '%s::date' % self.quote(value=value)

    def quote_timestamp(self, value: str) -> str:
        """Quote TIMESTAMP for being passed as a literal in a query."""
        value = decode_object_from_bytes_if_needed(value)

        return '%s::timestamp' % self.quote(value=value)

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

        table_name = '_tmp_ids_%s' % random_string(length=16)

        log.debug("Temporary IDs table: %s" % table_name)

        primary_key_clause = ""
        if ordered:
            primary_key_clause = "%s_pkey SERIAL PRIMARY KEY," % table_name

        sql = """CREATE TEMPORARY TABLE %s (""" % table_name
        sql += primary_key_clause
        sql += "id BIGINT)"
        self.query(sql)

        copy = self.copy_from("COPY %s (id) FROM STDIN" % table_name)
        for single_id in ids:
            copy.put_line("%d\n" % int(single_id))
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
        # HMR: the point of this thing is to be able to add nested data in only a single query, which vastly increases
        # performance over performing one query per row for the nested data

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

        # if we're appending lists, make sure each parent row has an empty list
        if not single:
            for parent in data:
                if child_field not in parent:
                    parent[child_field] = []

        for child in children:
            child_id = child[id_column]
            parent = parent_lookup[child_id]

            if single:
                parent[child_field] = child[child_field]
            else:
                parent[child_field].append(child)

        return data
