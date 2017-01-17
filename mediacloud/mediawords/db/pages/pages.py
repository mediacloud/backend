from psycopg2.extras import DictCursor

from typing import List, Dict, Any

from mediawords.db.exceptions.handler import McQueryPagedHashesException
from mediawords.db.result.result import DatabaseResult
from mediawords.util.pages import Pages
from mediawords.util.perl import convert_dbd_pg_arguments_to_psycopg2_format


class DatabasePages(object):
    __list = None
    __pager = None

    def __init__(self, cursor: DictCursor, query: str, page: int, rows_per_page: int):
        self.__execute(cursor=cursor, query=query, page=page, rows_per_page=rows_per_page)

    def __execute(self, cursor: DictCursor, query: str, page: int, rows_per_page: int):
        if page < 1:
            raise McQueryPagedHashesException('Page must be 1 or bigger.')

        offset = (page - 1) * rows_per_page

        query = "%(original_query)s LIMIT ( %(rows_per_page)d + 1 ) OFFSET %(offset)s" % {
            'original_query': query,
            'rows_per_page': rows_per_page,
            'offset': offset,
        }

        query_args = [query]
        query_args = convert_dbd_pg_arguments_to_psycopg2_format(*query_args)

        # Query
        rs = DatabaseResult(cursor=cursor, query_args=query_args)

        hashes = rs.hashes()

        # Truncate
        one_more_page = False
        if len(hashes) > rows_per_page:
            one_more_page = True
            del hashes[rows_per_page:]

        hashes_size = offset + len(hashes)
        if one_more_page:
            hashes_size += 1

        pager = Pages(total_entries=hashes_size, entries_per_page=rows_per_page, current_page=page)

        self.__list = hashes
        self.__pager = pager

    def list(self) -> List[Dict[str, Any]]:
        return self.__list

    def pager(self) -> Pages:
        return self.__pager
