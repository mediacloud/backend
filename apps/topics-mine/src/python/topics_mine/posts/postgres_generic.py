"""Parse generic posts from a postgres table."""

import datetime
from dateutil import parser
import io
import uuid

import mediawords.db
from mediawords.db.handler import DatabaseHandler

from topics_base.posts import get_mock_data, filter_posts_for_date_range
from topics_mine.posts import AbstractPostFetcher

from mediawords.util.log import create_logger

log = create_logger(__name__)

class McPostgresGenericDataException(Exception):
    """exception indicating an error in the data for generic posts."""
    pass


class PostgresPostFetcher(AbstractPostFetcher):

    def _insert_mock_data(self, db: DatabaseHandler, data: list) -> str:
        """Insert the mock data into the test table and return the test table name."""
        table = 'postgres_post_fetcher_test'

        db.query(
            f"""
            create table {table} (
                id serial primary key,
                content text,
                publish_date text,
                author text,
                channel text,
                post_id text
            )
            """)

        for d in data:
            db.create(table, d)

        return table

    def fetch_posts_from_api(self, query: str, start_date: datetime, end_date: datetime) -> list:
        """Return posts from a csv that are within the given date range."""
        db = mediawords.db.connect_to_db()

        if self.mock_enabled:
            query = self._insert_mock_data(db, get_mock_data())

        table = query

        posts = db.query(
            f"""
            select content, publish_date, author, post_id, channel
                from {table} 
                where publish_date::timestamp between %(a)s and %(b)s
            """,
            {'a': start_date, 'b': end_date }).hashes()

        return posts
