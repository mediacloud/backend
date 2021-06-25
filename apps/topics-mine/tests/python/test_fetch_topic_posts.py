"""test fetch_topic_posts."""

import datetime

from mediawords.db import DatabaseHandler, connect_to_db
from mediawords.test.db.create import create_test_topic
from mediawords.util.log import create_logger

# noinspection PyProtectedMember
from topics_mine.fetch_topic_posts import POST_FIELDS, fetch_topic_posts
# noinspection PyProtectedMember
from topics_mine.posts.csv_generic import CSVStaticPostFetcher

logger = create_logger(__name__)

# number of mocked posts to return for each day -- edit this up to MAX_MOCK_POSTS_PER_DAY to change the size
# of the testing set
MOCK_POSTS_PER_DAY = 5

# ratios of posts to urls and users.  these can be edited to derive the desired ratios for testing
MOCK_POSTS_PER_URL = 4
MOCK_POSTS_PER_USER = 20

MOCK_START_DATE = '2019-02-02'

# number of days to mock posts for
MOCK_DAYS = 100

# these should not be edited
NUM_MOCK_URLS = int((MOCK_DAYS * MOCK_POSTS_PER_DAY) / MOCK_POSTS_PER_URL)
NUM_MOCK_USERS = int((MOCK_DAYS * MOCK_POSTS_PER_DAY) / MOCK_POSTS_PER_USER)


def _get_mock_posts() -> list:
    """Return a list of mock posts."""
    num_mock_posts = MOCK_DAYS * MOCK_POSTS_PER_DAY
    posts = []
    for post_id in range(num_mock_posts):
        url_id = post_id % NUM_MOCK_URLS
        user_id = post_id % NUM_MOCK_USERS

        start_date = datetime.datetime.strptime(MOCK_START_DATE, '%Y-%m-%d')
        publish_date = start_date + datetime.timedelta(days=int(post_id % MOCK_DAYS))

        test_url = "http://test.host/post_url?id=" + str(url_id)

        # this one should get ignored by the topic_seed_query['ignore_pattern']
        ignore_url = "http://ignore.test/" + str(url_id)

        hindi_foo_bar = 'फू बार';
        mandarin_author = 'មិត្ត ១០០ ឆ្នាំ';

        posts.append({
            'post_id': post_id,
            'content': "%s sample post for id id %s %s" % (hindi_foo_bar, test_url, ignore_url),
            'publish_date': publish_date,
            'url': test_url,
            'author': '%s user-%s' % (mandarin_author, user_id),
            'channel': 'channel-%s' % user_id,
        })

    return posts


def _validate_topic_posts(db: DatabaseHandler, topic: dict, mock_posts: list) -> None:
    """Validate that the topic_posts match the mock_posts."""
    got_posts = db.query(
        """
        SELECT *
        FROM topic_posts
            INNER JOIN topic_post_days ON
                topic_posts.topics_id = topic_post_days.topics_id AND
                topic_posts.topic_post_days_id = topic_post_days.topic_post_days_id
            INNER JOIN topic_seed_queries ON
                topic_post_days.topics_id = topic_seed_queries.topics_id AND
                topic_post_days.topic_seed_queries_id = topic_seed_queries.topic_seed_queries_id
        WHERE topic_posts.topics_id = %(a)s
        """,
        {'a': topic['topics_id']}).hashes()

    assert len(got_posts) == len(mock_posts)

    mock_posts = sorted(mock_posts, key=lambda x: x['post_id'])

    for i, mock_post in enumerate(mock_posts):
        got_post = db.query(
            "SELECT * FROM topic_posts WHERE post_id = %(a)s::text",
            {'a': mock_post['post_id']}).hash()

        assert got_post

        for field in POST_FIELDS:
            assert str(got_post.get(field, None)) == str(mock_post.get(field, None))


def _validate_topic_post_urls(db: DatabaseHandler, mock_posts: list) -> None:
    """Validate that topic_post_urls match the url in each post."""
    # first sanity check to make sure we got some urls
    num_urls = db.query("select count(*) from topic_post_urls").flat()[0]
    assert num_urls == len(mock_posts)

    for mock_post in mock_posts:
        topic_post = db.query(
            "select * from topic_posts where post_id = %(a)s::text",
            {'a': mock_post['post_id']}).hash()

        assert topic_post is not None

        topic_urls = db.query(
            "select * from topic_post_urls where topic_posts_id = %(a)s",
            {'a': topic_post['topic_posts_id']}).hashes()

        assert len(topic_urls) == 1
        assert topic_urls[0]['url'] == mock_post['url']


def test_fetch_topic_posts() -> None:
    """Run fetch_topic_post tests."""
    db = connect_to_db()

    topic = create_test_topic(db, 'test')

    topic['pattern'] = '.*'
    topic['platform'] = 'generic_post'
    topic['mode'] = 'url_sharing'
    topic['start_date'] = datetime.datetime.strptime(MOCK_START_DATE, '%Y-%m-%d')
    topic['end_date'] = topic['start_date'] + datetime.timedelta(days=MOCK_DAYS - 1)

    db.update_by_id('topics', topic['topics_id'], topic)

    mock_posts = _get_mock_posts()

    mock_posts_csv = CSVStaticPostFetcher()._get_csv_string_from_dicts(mock_posts)

    tsq = {
        'topics_id': topic['topics_id'],
        'platform': 'generic_post',
        'source': 'csv',
        'ignore_pattern': 'ignore',
        'query': mock_posts_csv}
    tsq = db.create('topic_seed_queries', tsq)

    db.update_by_id('topics', topic['topics_id'], {'platform': 'generic_post'})

    fetch_topic_posts(db, tsq)

    topic_post_days = db.query("SELECT * FROM topic_post_days").hashes()
    assert len(topic_post_days) == MOCK_DAYS

    start_date = topic['start_date']
    test_days = [start_date + datetime.timedelta(days=x) for x in range(0, MOCK_DAYS)]
    for d in test_days:
        topic_post_day = db.query("""
            SELECT *
            FROM topic_post_days
            WHERE
                topics_id = %(topics_id)s AND
                topic_seed_queries_id = %(topic_seed_queries_id)s AND
                day = %(day)s
            """, {
                'topics_id': tsq['topics_id'],
                'topic_seed_queries_id': tsq['topic_seed_queries_id'],
                'day': d,
            }
        ).hash()
        assert topic_post_day is not None

    _validate_topic_posts(db, topic, mock_posts)

    _validate_topic_post_urls(db, mock_posts)
