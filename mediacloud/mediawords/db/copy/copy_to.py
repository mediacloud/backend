import tempfile
from typing import Union

import psycopg2
from psycopg2.extras import DictCursor

from mediawords.db.exceptions.handler import McDatabaseHandlerException
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McCopyToException(McDatabaseHandlerException):
    pass


# FIXME reads everything to a temporary file in a constructor, gives back line by line afterwards
class CopyTo(object):
    """COPY TO helper. Implements iterator methods too."""

    # Chunk size to COPY TO
    __COPY_CHUNK_SIZE = 100 * 1024

    # SQL to run
    __sql = None

    # Database cursor
    __cursor = None

    # Temporary file buffer
    __temp_file_buffer = None

    def __init__(self, cursor: DictCursor, sql: str):

        sql = decode_object_from_bytes_if_needed(sql)

        self.__start_copy_to(cursor=cursor, sql=sql)

    def __start_copy_to(self, cursor: DictCursor, sql: str) -> None:
        """Start COPY TO."""

        sql = decode_object_from_bytes_if_needed(sql)

        if sql is None:
            raise McDatabaseHandlerException("SQL is None.")
        if len(sql) == '':
            raise McDatabaseHandlerException("SQL is empty.")

        self.__sql = sql
        self.__cursor = cursor
        self.__temp_file_buffer = tempfile.TemporaryFile(mode='w+', encoding='utf-8')

        try:
            self.__cursor.copy_expert(sql=self.__sql, file=self.__temp_file_buffer, size=self.__COPY_CHUNK_SIZE)
            self.__temp_file_buffer.seek(0)
        except psycopg2.Warning as ex:
            log.warning('Warning while running COPY TO query: %s' % str(ex))
        except Exception as ex:
            raise McCopyToException('COPY TO query failed: %s' % str(ex))

    def get_line(self) -> Union[str, None]:
        """Read line."""
        line = self.__temp_file_buffer.readline()
        if line != '':
            return line
        else:
            return None

    def end(self) -> None:
        """Stop reading."""
        self.__temp_file_buffer.close()

    def __iter__(self):
        return self

    def __next__(self) -> Union[str, None]:
        line = self.get_line()
        if line is None:
            raise StopIteration
        return line
