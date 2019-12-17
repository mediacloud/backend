"""Parse generic posts from a csv."""

import csv
import datetime
from dateutil import parser
import io

from mediawords.util.log import create_logger

from topics_mine.posts import AbstractPostFetcher

log = create_logger(__name__)

# number of posts to mock for tests
NUM_MOCK_POSTS = 100


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

    def fetch_posts(self, query: str, start_date: datetime, end_date: datetime) -> list:
        """Return posts from a csv that are within the given date range."""
        if self._mock_enabled:
            all_posts = self.get_mock_data()
        else:
            all_posts = self._get_dicts_from_csv_string(query)

        required_fields = ['content', 'author', 'channel', 'content', 'publish_date', 'post_id']
        for post in all_posts:
            for field in required_fields:
                if field not in post:
                    raise McPostsGenericDataException(f"Missing required field: {field}")
            
            post['data'] = {}

        posts = []
        for p in all_posts:
            if start_date <= parser.parse(p['publish_date']) <= end_date:
                posts.append(p)


        return posts

    def get_mock_data(self) -> list:
        """Return mock data for testing.

        Subclass implementations of enable_mock should return this data, so that tests can generically verify
        that the mocked version of fetch_posts is returning the mocked data.
        """
        mock_data = []
        for i in range(NUM_MOCK_POSTS):
            publish_date = datetime.datetime.strptime('2019-01-01', '%Y-%m-%d') + datetime.timedelta(days=i)
            d = {
                'content': 'mock content %s' % str(i),
                'author': 'mock author %s' % str(i),
                'channel': 'mock channel %s' % str(i),
                'publish_date': str(publish_date),
                'post_id': i}
            mock_data.append(d)

        return mock_data

    def enable_mock(self) -> None:
        """Mock a csv so that the test search works."""

        # just set an attribute and let fetch_posts decide to send mocked data back
        self._mock_enabled = True
