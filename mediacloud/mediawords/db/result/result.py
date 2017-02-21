import itertools
import pprint
from typing import Dict, List

import psycopg2
from psycopg2.extras import DictCursor

from mediawords.db.exceptions.result import *
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

l = create_logger(__name__)


class DatabaseResult(object):
    """Wrapper around SQL query result."""

    __cursor = None  # psycopg2 cursor

    def __init__(self, cursor: DictCursor, query_args: tuple, print_warnings: bool = True):

        # MC_REWRITE_TO_PYTHON: 'query_args' should be decoded from 'bytes' at this point

        self.__execute(cursor=cursor, query_args=query_args, print_warnings=print_warnings)

    def __execute(self, cursor: DictCursor, query_args: tuple, print_warnings: bool) -> None:
        """Execute statement, set up cursor to results."""

        # MC_REWRITE_TO_PYTHON: 'query_args' should be decoded from 'bytes' at this point

        if len(query_args) == 0:
            raise McDatabaseResultException('No query or its parameters.')
        if len(query_args[0]) == 0:
            raise McDatabaseResultException('Query is empty or undefined.')

        try:
            cursor.execute(*query_args)

        except psycopg2.Warning as ex:
            if print_warnings:
                l.warn('Warning while running query: %s' % str(ex))
            else:
                l.debug('Warning while running query: %s' % str(ex))

        except psycopg2.ProgrammingError as ex:
            raise McDatabaseResultException(
                'Invalid query: %(exception)s; query: %(query)s' % {
                    'exception': str(ex),
                    'query': str(query_args),
                })

        except IndexError as ex:
            raise McDatabaseResultException(
                'Invalid query (DBD::Pg -> psycopg2 query conversion?): %(exception)s; query: %(query)s' % {
                    'exception': str(ex),
                    'query': str(query_args),
                })

        except psycopg2.Error as ex:
            raise McDatabaseResultException(
                'Query failed: %(exception)s; query: %(query)s; mogrified query: %(mogrified_query)s' % {
                    'exception': str(ex),
                    'query': str(query_args),
                    'mogrified_query': str(cursor.mogrify(*query_args)),
                })

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

        text_type = decode_object_from_bytes_if_needed(text_type)

        if text_type != 'neat':
            raise McDatabaseResultTextException("Formatting types other than 'neat' are not supported.")
        return pprint.pformat(self.hashes(), indent=4)
