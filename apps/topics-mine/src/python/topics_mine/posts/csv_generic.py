"""Parse generic posts from a csv."""

import csv
import datetime
from dateutil import parser
import io
import shelve
import uuid
from typing import Optional

import mediawords.util.url
import mediawords.util.web.user_agent

from mediawords.util.log import create_logger

from topics_base.posts import get_mock_data, filter_posts_for_date_range
from topics_mine.posts import AbstractPostFetcher

log = create_logger(__name__)

class McPostsGenericDataException(Exception):
    """exception indicating an error in the data for generic posts."""
    pass


class CSVStaticPostFetcher(AbstractPostFetcher):

    @staticmethod
    def _get_csv_string_from_dicts(dicts: list) -> str:
        """Given a list of dicts, return a representative csv string."""
        if len(dicts) < 1:
            return ''

        csv_io = io.StringIO()

        csv_writer = csv.DictWriter(csv_io, fieldnames=dicts[0].keys())

        csv_writer.writeheader()
        [csv_writer.writerow(d) for d in dicts]

        return csv_io.getvalue()

    @staticmethod
    def _get_dicts_from_csv_string(csv_string: str) -> list:
        """Given a csv string, return a list of dicts."""
        if len(csv_string) < 1:
            return []

        csv_io = io.StringIO(csv_string)

        return list(csv.DictReader(csv_io))

    def fetch_posts_from_api(
        self,
        query: str,
        start_date: datetime,
        end_date: datetime,
        sample: Optional[int] = None,
        page_size: Optional[int] = None,
    ) -> list:
        """Return posts from a csv that are within the given date range."""
        if self.mock_enabled:
            query = self._get_csv_string_from_dicts(get_mock_data())

        assert sample is None, "Sampling is not implemented."
        assert page_size is None, "Page size limiting is not supported."

        all_posts = self._get_dicts_from_csv_string(query)

        required_fields = ['content', 'author', 'publish_date']
        for post in all_posts:
            for field in required_fields:
                if field not in post:
                    raise McPostsGenericDataException(f"Missing required field: {field}")
            
            post['data'] = {}
            if 'channel' not in post:
                post['channel'] = post['author']

            if 'post_id' not in post:
                post['post_id'] = uuid.uuid4().hex

            post['post_id'] =str(post['post_id'])

        posts = filter_posts_for_date_range(all_posts, start_date, end_date)

        return posts
