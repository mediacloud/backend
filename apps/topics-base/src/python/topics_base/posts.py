import datetime
import dateutil

# mock data numbers
NUM_MOCK_POST_DAYS = 100
NUM_MOCK_POSTS_PER_DAY = 10
NUM_MOCK_POSTS = NUM_MOCK_POST_DAYS * NUM_MOCK_POSTS_PER_DAY
NUM_MOCK_AUTHORS = NUM_MOCK_POSTS / 100
NUM_MOCK_CHANNELS = NUM_MOCK_POSTS / 10

# start date for mock posts
MOCK_START_DATE = '2019-01-01'

def filter_posts_for_date_range(all_posts: list, start_date: datetime, end_date: datetime) -> list:
    """Return a list of only the posts for which publish_date is between start_date and end_date, inclusive.""" 
    posts = []
    for p in all_posts:
        if start_date <= dateutil.parser.parse(p['publish_date']) <= end_date:
            posts.append(p)

    return posts


def get_mock_post(post_id: int) -> dict:
    """Return consistent mock data for a given post id.

    This method is used by get_mock_data(), so posts generated with this method will be consistent with posts
    return from get_mock_data().
    """
    day_interval = int(post_id / NUM_MOCK_POST_DAYS)
    publish_date = datetime.datetime.strptime(MOCK_START_DATE, '%Y-%m-%d') + datetime.timedelta(days=day_interval)

    author_id = int(post_id % NUM_MOCK_AUTHORS)
    channel_id = int(post_id % NUM_MOCK_CHANNELS)

    hindi_foo_bar = 'फू बार';
    mandarin_author = 'មិត្ត ១០០ ឆ្នាំ';

    d = {
            'content': 'mock content %s %s' % (hindi_foo_bar, str(post_id)),
            'author': 'mock author %s %s' % (mandarin_author, str(author_id)),
            'channel': 'mock channel %s' % str(channel_id),
            'publish_date': str(publish_date),
            'post_id': str(post_id)
        }

    return d


def get_mock_data(start_date: datetime=None, end_date: datetime=None) -> list:
    """Return mock data for testing.

    Subclass implementations of enable_mock should return this data, so that tests can generically verify
    that the mocked version of fetch_posts is returning the mocked data.
    """
    mock_data = []
    for j in range(NUM_MOCK_POST_DAYS):
        for i in range(NUM_MOCK_POSTS_PER_DAY):
            post_id = (j * NUM_MOCK_POST_DAYS) + i
            mock_data.append(get_mock_post(post_id))

    if start_date and end_date:
        mock_data = filter_posts_for_date_range(mock_data, start_date, end_date)

    return mock_data
