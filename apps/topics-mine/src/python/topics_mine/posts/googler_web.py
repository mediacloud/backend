"""Fetch web urls results from google."""

import csv
import datetime
from dateutil import parser
import io

from mediawords.util.log import create_logger

from topics_base.posts import get_mock_data, filter_posts_for_date_range
from topics_mine.posts import AbstractPostFetcher

log = create_logger(__name__)


class McPostsGenericDataException(Exception):
    """exception indicating an error in the data for generic posts."""
    pass


class GooglerWebPostFetcher(AbstractPostFetcher):

    def _get_mock_json(self):
        """return json in googler format derived from get_mock_data()."""
        mock_data = _get_mock_data()

    @staticmethod
    def fetch_posts_from_api(self, query: str, start_date: datetime, end_date: datetime) -> list:
        """Return posts from a csv that are within the given date range."""
        if self.mock_enabled:
            query = self._get_csv_string_from_dicts(get_mock_data())

        start_query = "after:" + start_date.strftime("%Y-%m-%d")
        end_query = "before:" + (end_date + datetime.timedelta(days=1)).strftime("%Y-%m-%d")

        full_query = "query %s %s" % (start_query, end_query)

        links = subprocess.check_output("googler", "--json", "-n 100", query)

        posts
        for link in links:
            publish_date = dateutil.parser.parse(link['metadata'])
            posts.append(
                {
                    'post_id': link['url'],
                    'content': "%s %s %s" % (link['title', link['abstract'], link['url']),
                    'author': 'google',
                    'channel': 'google',
                    'publish_date': publish_date.strftime('%Y-%m-%d')
                })

        return posts
