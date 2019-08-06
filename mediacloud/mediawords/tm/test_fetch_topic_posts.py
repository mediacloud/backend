"""test fetch_topic_posts."""

import datetime
import os
import unittest

from mediawords.db import DatabaseHandler
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
import mediawords.test.db
import mediawords.test.db.create
import mediawords.tm.fetch_topic_posts as ftp
from mediawords.util.csv import get_csv_string_from_dicts
import mediawords.util.paths
import mediawords.util.twitter
from mediawords.util.log import create_logger

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

# arbitrary tests for tweets / users so that we don't have to use fixtures
MIN_TEST_CH_POSTS = 500
MIN_TEST_POST_LENGTH = 10
MIN_TEST_AUTHOR_LENGTH = 3

# test crimson hexagon monitor id
TEST_MONITOR_ID = 4667493813


def _get_mock_posts() -> str:
    """Return a list of mock posts."""
    num_mock_posts = MOCK_DAYS * MOCK_POSTS_PER_DAY
    posts = []
    for post_id in range(num_mock_posts):
        url_id = post_id % NUM_MOCK_URLS
        user_id = post_id % NUM_MOCK_USERS

        start_date = datetime.datetime.strptime(MOCK_START_DATE, '%Y-%m-%d')
        publish_date = start_date + datetime.timedelta(days=int(post_id % MOCK_DAYS))

        test_url = "http://test.host/post_url?id=" + str(url_id)

        posts.append({
            'post_id': post_id,
            'content': "sample post for id id %s" % test_url,
            'publish_date': publish_date,
            'url': test_url,
            'author': 'user-%s' % user_id,
            'channel': 'channel-%s' % user_id,
        })

    return posts


def validate_topic_posts(db: DatabaseHandler, topic: dict, mock_posts: list) -> None:
    """Validate that the topic_posts match the mock_posts."""
    got_posts = db.query(
        """
        select *
            from topic_posts tp
                join topic_post_days tpd using ( topic_post_days_id )
            where topics_id = %(a)s
        """,
        {'a': topic['topics_id']}).hashes()

    assert len(got_posts) == len(mock_posts)

    mock_posts = sorted(mock_posts, key=lambda x: x['post_id'])

    for i, mock_post in enumerate(mock_posts):
        got_post = db.query(
            "select * from topic_posts where post_id = %(a)s::text",
            {'a': mock_post['post_id']}).hash()

        assert got_post

        for field in ftp.POST_FIELDS:
            assert str(got_post.get(field, None)) == str(mock_post.get(field, None))


def validate_topic_post_urls(db: DatabaseHandler, topic: dict, mock_posts: list) -> None:
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


class TestFetchTopicposts(TestDatabaseWithSchemaTestCase):
    """Run database tests."""

    def test_fetch_topic_posts(self) -> None:
        """Run fetch_topic_post tests with test database."""
        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'test')

        topic['pattern'] = '.*'
        topic['platform'] = 'generic_post'
        topic['mode'] = 'web_sharing'
        topic['start_date'] = datetime.datetime.strptime(MOCK_START_DATE, '%Y-%m-%d')
        topic['end_date'] = topic['start_date'] + datetime.timedelta(days=MOCK_DAYS)

        db.update_by_id('topics', topic['topics_id'], topic)

        mock_posts = _get_mock_posts()
        mock_posts_csv = get_csv_string_from_dicts(mock_posts)

        tsq = {'topics_id': topic['topics_id'], 'platform': 'generic_post', 'source': 'csv', 'query': mock_posts_csv}
        db.create('topic_seed_queries', tsq)

        db.update_by_id('topics', topic['topics_id'], {'platform': 'generic_post'})

        ftp.fetch_topic_posts(db, topic['topics_id'])

        topic_post_days = db.query("select * from topic_post_days").hashes()
        assert len(topic_post_days) == MOCK_DAYS

        start_date = topic['start_date']
        test_days = [start_date + datetime.timedelta(days=x) for x in range(0, MOCK_DAYS)]
        for d in test_days:
            topic_post_day = db.query(
                "select * from topic_post_days where topics_id = %(a)s and day = %(b)s",
                {'a': topic['topics_id'], 'b': d}
            ).hash()
            assert topic_post_day is not None

        validate_topic_posts(db, topic, mock_posts)

        validate_topic_post_urls(db, topic, mock_posts)

    def _test_remote_integration(self, source, query, day) -> None:
        """Run santity test on remote apis."""
        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, "test_remote_integration")

        tsq = {
            'topics_id': topic['topics_id'],
            'platform': 'post',
            'source': source,
            'query': query
        }
        db.create('topic_seed_queries', tsq)

        topic['platform'] = 'post'
        topic['pattern'] = '.*'
        topic['start_date'] = day
        topic['end_date'] = day
        db.update_by_id('topics', topic['topics_id'], topic)

        # only fetch 200 posts to make test quicker
        max_posts = 200
        ftp.fetch_topic_posts(db, topic['topics_id'], max_posts)

        got_tts = db.query("select * from topic_posts").hashes()

        # for old ch monitors, lots of the posts may be deleted
        assert len(got_tts) > max_posts / 10

        assert len(got_tts[0]['content']) > MIN_TEST_POST_LENGTH
        assert len(got_tts[0]['author']) > MIN_TEST_AUTHOR_LENGTH

    @unittest.skipUnless(os.environ.get('MC_REMOTE_TESTS', False), "remote tests")
    def test_ch_remote_integration(self) -> None:
        """Test ch remote integration."""
        self._test_remote_integration('crimson_hexagon', TEST_MONITOR_ID, '2016-01-01')

    @unittest.skipUnless(os.environ.get('MC_REMOTE_TESTS', False), "remote tests")
    def test_archive_remote_integration(self) -> None:
        """Test archive.org remote integration."""
        self._test_remote_integration('archive_org', 'harvard', '2019-01-01')
