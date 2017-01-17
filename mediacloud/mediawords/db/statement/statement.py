import collections
from psycopg2.extras import DictCursor
from typing import Any

from mediawords.db.exceptions.handler import McPrepareException
from mediawords.db.result.result import DatabaseResult
from mediawords.util.log import create_logger
from mediawords.util.perl import convert_dbd_pg_arguments_to_psycopg2_format, decode_object_from_bytes_if_needed

l = create_logger(__name__)


class DatabaseStatement(object):
    """Wrapper around a prepared statement."""

    # SQL to run
    __sql = None

    # Query arguments
    __arguments = None

    # Database cursor
    __cursor = None

    def __init__(self, cursor: DictCursor, sql: str):

        sql = decode_object_from_bytes_if_needed(sql)

        self.__prepare(cursor=cursor, sql=sql)

    def __prepare(self, cursor: DictCursor, sql: str) -> None:
        """Prepare statement."""

        sql = decode_object_from_bytes_if_needed(sql)

        if sql is None:
            raise McPrepareException("SQL is None.")
        if len(sql) == '':
            raise McPrepareException("SQL is empty.")

        self.__sql = sql
        self.__arguments = collections.OrderedDict()
        self.__cursor = cursor

    def __bind(self, param_num: int, value: Any) -> None:
        """Underlying implementation of bind(); doesn't do any decoding or preprocessing."""

        if param_num < 1:
            raise McPrepareException("Parameter number must be >1.")

        self.__arguments[param_num] = value

    def bind(self, param_num: int, value: Any) -> None:
        """Bind any value as statement's parameter."""

        value = decode_object_from_bytes_if_needed(value)

        self.__bind(param_num=param_num, value=value)

    def bind_bytea(self, param_num: int, value: bytes) -> None:
        """Bind BYTEA value as statement's parameter."""
        if not isinstance(value, bytes):
            raise McPrepareException("Value '%s' is not 'bytes'." % str(value))
        self.__bind(param_num=param_num, value=value)

    def execute(self) -> DatabaseResult:
        """Execute prepared statement."""

        query_args = [self.__sql]
        expected_param_num = 1
        for param_num, param_value in self.__arguments.items():
            query_args.append(param_value)

            if param_num != expected_param_num:
                raise McPrepareException("Invalid parameter number %d" % param_num)
            expected_param_num += 1

        query_args = convert_dbd_pg_arguments_to_psycopg2_format(*query_args, skip_decoding=True)

        return DatabaseResult(cursor=self.__cursor, query_args=query_args)
