from typing import Any

import collections

from mediawords.util.perl import convert_dbd_pg_arguments_to_psycopg2_format

from mediawords.db.result.result import DatabaseResult
from psycopg2.extras import DictCursor

from mediawords.db.exceptions.handler import McPrepareException
from mediawords.util.log import create_logger

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
        self.__prepare(cursor=cursor, sql=sql)

    def __prepare(self, cursor: DictCursor, sql: str):
        """Prepare statement."""
        if sql is None:
            raise McPrepareException("SQL is None.")
        if len(sql) == '':
            raise McPrepareException("SQL is empty.")

        self.__sql = sql
        self.__arguments = collections.OrderedDict()
        self.__cursor = cursor

    def bind(self, param_num: int, value: Any):
        """Bind any value as statement's parameter."""
        if param_num < 1:
            raise McPrepareException("Parameter number must be >1.")

        self.__arguments[param_num] = value

    def bind_bytea(self, param_num: int, value: bytes):
        """Bind BYTEA value as statement's parameter."""
        if not isinstance(value, bytes):
            raise McPrepareException("Value '%s' is not 'bytes'." % str(value))
        return self.bind(param_num=param_num, value=value)

    def execute(self):
        """Execute prepared statement."""

        query_args = [self.__sql]
        expected_param_num = 1
        for param_num, param_value in self.__arguments.items():
            query_args.append(param_value)

            if param_num != expected_param_num:
                raise McPrepareException("Invalid parameter number %d" % param_num)
            expected_param_num += 1

        query_args = convert_dbd_pg_arguments_to_psycopg2_format(*query_args)

        return DatabaseResult(cursor=self.__cursor, query_args=query_args)
