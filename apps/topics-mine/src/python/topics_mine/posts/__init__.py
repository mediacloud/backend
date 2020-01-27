import abc
import datetime
import dateutil

from mediawords.util.log import create_logger

log = create_logger(__name__)

# number of days to mock posts for
NUM_MOCK_POST_DAYS = 100

# number of mock posts per day
NUM_MOCK_POSTS_PER_DAY = 10

# start date for mock posts
MOCK_START_DATE = '2019-01-01'


class AbstractPostFetcher(object, metaclass=abc.ABCMeta):

    def __init__(self):
        self.mock_enabled = False

    @abc.abstractmethod
    def fetch_posts(self, query: dict, start_date: datetime, end_date: datetime) -> list:
        raise NotImplemented("Abstract method")

    def filter_posts_for_date_range(self, all_posts: list, start_date: datetime, end_date: datetime) -> list:
        """Return a list of only the posts for which publish_date is between start_date and end_date, inclusive.""" 
        posts = []
        for p in all_posts:
            if start_date <= dateutil.parser.parse(p['publish_date']) <= end_date:
                posts.append(p)

        return posts


    def get_mock_data(self) -> list:
        """Return mock data for testing.

        Subclass implementations of enable_mock should return this data, so that tests can generically verify
        that the mocked version of fetch_posts is returning the mocked data.
        """
        mock_data = []
        for j in range(NUM_MOCK_POST_DAYS):
            for i in range(NUM_MOCK_POSTS_PER_DAY):
                post_id = i * j
                publish_date = datetime.datetime.strptime(MOCK_START_DATE, '%Y-%m-%d') + datetime.timedelta(days=i)
                d = {
                    'content': 'mock content %s' % str(post_id),
                    'author': 'mock author %s' % str(i),
                    'channel': 'mock channel %s' % str(i),
                    'publish_date': str(publish_date),
                    'post_id': post_id}
                mock_data.append(d)

        return mock_data

    def test_mock_data(self, query:str='') -> None:
        """Run test of object using mock data.

        This should work on any class, as long as fetch_post() is implemented to return the data from
        get_mock_data when mock_enabled = True.
        """
        self.mock_enabled = True

        expected_posts = self.get_mock_data()

        start_date = dateutil.parser.parse(expected_posts[0]['publish_date'])
        end_date = dateutil.parser.parse(expected_posts[-1]['publish_date'])

        got_posts = self.fetch_posts(query, start_date, end_date)

        log.warning(len(got_posts))
        log.warning(len(expected_posts))

        assert len(got_posts) == len(expected_posts)
        for i, got_post in enumerate(got_posts):
            for field in ('post_id', 'author', 'channel', 'content'):
                assert got_post[field] == expected_posts[i][field]
