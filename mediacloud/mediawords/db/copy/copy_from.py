import tempfile

import psycopg2
from psycopg2.extras import DictCursor

from mediawords.db.exceptions.handler import McDatabaseHandlerException
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McCopyFromException(McDatabaseHandlerException):
    pass


# FIXME writes everything to a temporary file first, does the actual copying in end()
class CopyFrom(object):
    """COPY FROM helper."""

    # Chunk size to COPY FROM
    __COPY_CHUNK_SIZE = 100 * 1024

    # SQL to run
    __sql = None

    # Database cursor
    __cursor = None

    # Temporary file buffer
    __temp_file_buffer = None

    def __init__(self, cursor: DictCursor, sql: str):

        sql = decode_object_from_bytes_if_needed(sql)

        self.__start_copy_from(cursor=cursor, sql=sql)

    def __start_copy_from(self, cursor: DictCursor, sql: str) -> None:
        """Start COPY FROM."""

        sql = decode_object_from_bytes_if_needed(sql)

        if sql is None:
            raise McDatabaseHandlerException("SQL is None.")
        if len(sql) == '':
            raise McDatabaseHandlerException("SQL is empty.")

        self.__sql = sql
        self.__cursor = cursor
        self.__temp_file_buffer = tempfile.TemporaryFile(mode='w+', encoding='utf-8')

    def put_line(self, line: str) -> None:
        """Write line."""

        line = decode_object_from_bytes_if_needed(line)

        line = line.rstrip('\n')
        try:
            self.__temp_file_buffer.write("%s\n" % line)
        except Exception as ex:
            raise McCopyFromException("Error write writing line '%s': %s" % (line, str(ex)))

    def end(self) -> None:
        """Stop writing (and run the actual COPY FROM)."""
        try:
            self.__temp_file_buffer.seek(0)
            self.__cursor.copy_expert(sql=self.__sql, file=self.__temp_file_buffer, size=self.__COPY_CHUNK_SIZE)
            self.__temp_file_buffer.close()
        except psycopg2.Warning as ex:
            log.warning('Warning while running COPY FROM query: %s' % str(ex))
        except Exception as ex:
            raise McCopyFromException('COPY FROM query failed: %s' % str(ex))
