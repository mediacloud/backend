"""test fetch_topic_tweets."""

import datetime
import os
import random
import re
import unittest

from mediawords.db import DatabaseHandler
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
import mediawords.test.db
import mediawords.tm.fetch_topic_tweets
import mediawords.util.paths

from mediawords.util.log import create_logger
logger = create_logger(__name__)

# this is an estimate of the number of tweets per day included in the ch-posts-date.json files
# this should not be edited other than to provide a better estimate
MAX_MOCK_TWEETS_PER_DAY = 400

# number of mocked tweets to return for each day -- edit this up to MAX_MOCK_TWEETS_PER_DAY to change the size
# of the testing set
MOCK_TWEETS_PER_DAY = 25

# ratios of tweets to urls and users.  these can be edited to derive the desired ratios for testing
MOCK_TWEETS_PER_URL = 4
MOCK_TWEETS_PER_USER = 20

# max number of days difference between start and end dates for test topic -- this can edited for the desired
# number of days for the local test
LOCAL_DATE_RANGE = 4

# these should not be edited
NUM_MOCK_URLS = int((LOCAL_DATE_RANGE * MOCK_TWEETS_PER_DAY) / MOCK_TWEETS_PER_URL)
NUM_MOCK_USERS = int((LOCAL_DATE_RANGE * MOCK_TWEETS_PER_DAY) / MOCK_TWEETS_PER_USER)

# arbitrary tests for tweets / users so that we don't have to use fixtures
MIN_TEST_CH_POSTS = 500
MIN_TEST_TWEET_LENGTH = 10
MIN_TEST_TWITTER_USER_LENGTH = 3


class MockCrimsonHexagon(mediawords.tm.fetch_topic_tweets.AbstractCrimsonHexagon):
    """Mock the CrimsonHexagon class in fetch_topic_tweets to return test data."""

    @staticmethod
    def fetch_posts(ch_monitor_id: int, day: datetime.datetime) -> dict:
        """
        Return a mock ch response to the posts end point.

        Generate the mock response by sending back data from a consistent but semirandom selection of
        ch-posts-2016-01-0[12345].json.
        """
        assert MOCK_TWEETS_PER_DAY <= MAX_MOCK_TWEETS_PER_DAY

        test_path = mediawords.util.paths.mc_root_path() + '/mediacloud/test-data/ch/'
        filename = test_path + "ch-posts-" + day.strftime('%Y-%m-%d') + '.json'
        with open(filename, 'r', encoding='utf-8') as fh:
            json = fh.read()

        data = dict(mediawords.util.json.decode_json(json))

        assert 'posts' in data
        assert len(data['posts']) >= MOCK_TWEETS_PER_DAY

        data['posts'] = data['posts'][0:MOCK_TWEETS_PER_DAY]

        # replace tweets with the epoch of the start date so that we can infer the date of each tweet in
        # tweet_urler_lookup below
        i = 0
        for ch_post in data['posts']:
            ch_post['url'] = re.sub('status/(\d+)/', '/status/' + str(i), ch_post['url'])
            i += 1

        return data


class MockTwitter(mediawords.tm.fetch_topic_tweets.AbstractTwitter):
    """Mock the Twitter class in mediawords.tm.fetch_topic_tweets to return test data."""

    @staticmethod
    def fetch_100_tweets(ids: list) -> list:
        """Return mocked test tweets."""
        num_errors = (3 if (len(ids) > 10) else 0)

        # simulate twitter not being able to find some ids, which is typical
        for i in range(num_errors):
            ids.pop()

        tweets = []
        for tweet_id in ids:

            # restrict url and user ids to desired number
            # include randomness so that the urls and users are not nearly collated
            url_id = int(random.randint(1, int(tweet_id))) % NUM_MOCK_URLS
            user_id = int(random.randint(1, int(tweet_id))) % NUM_MOCK_USERS

            test_url = "http://test.host/tweet_url?id=" + str(url_id)

            # all we use is id, text, and created_by, so just test for those
            tweets.append(
                {
                    'id': tweet_id,
                    'text': "sample tweet for id id",
                    'created_at': '2018-12-13',
                    'user': {'screen_name': "user-" + str(user_id)},
                    'entities': {'urls': [{'expanded_url': test_url}]}
                })

        return tweets


def get_test_date_range() -> tuple:
    """Return either 2016-01-01 - 2016-01-01 + LOCAL_DATE_RANGE - 1 for local tests."""
    end_date = datetime.datetime(year=2016, month=1, day=1) + datetime.timedelta(days=LOCAL_DATE_RANGE)
    return ('2016-01-01', end_date.strftime('%Y-%m-%d'))


def validate_topic_tweets(db: DatabaseHandler, topic_tweet_day: dict) -> None:
    """Validate that the topic tweets belonging to the given topic_tweet_day have all of the current data."""
    topic_tweets = db.query(
        "select * from topic_tweets where topic_tweet_days_id = %(a)s",
        {'a': topic_tweet_day['topic_tweet_days_id']}
    ).hashes()

    # fetch_topic_tweets should have set num_ch_tweets to the total number of tweets
    assert len(topic_tweets) > 0
    assert len(topic_tweets) == topic_tweet_day['num_ch_tweets']

    for topic_tweet in topic_tweets:
        tweet_data = dict(mediawords.util.json.decode_json(topic_tweet['data']))

        # random field that should be coming from twitter
        assert 'assignedCategoryId' in tweet_data

        expected_date = datetime.datetime.strptime(tweet_data['tweet']['created_at'], '%Y-%m-%d')
        got_date = datetime.datetime.strptime(topic_tweet['publish_date'], '%Y-%m-%d 00:00:00')
        assert got_date == expected_date

        assert topic_tweet['content'] == tweet_data['tweet']['text']


def validate_topic_tweet_urls(db: DatabaseHandler, topic: dict) -> None:
    """Validate that topic_tweet_urls match what's in the tweet JSON data as saved in topic_tweets."""
    topic_tweets = db.query(
        """
        select *
            from topic_tweets tt
                join topic_tweet_days ttd using (topic_tweet_days_id)
            where
                ttd.topics_id = %(a)s
        """,
        {'a': topic['topics_id']}).hashes()

    expected_num_urls = 0
    for topic_tweet in topic_tweets:
        data = dict(mediawords.util.json.decode_json(topic_tweet['data']))
        expected_num_urls += len(data['tweet']['entities']['urls'])

    # first sanity check to make sure we got some urls
    num_urls = db.query("select count(*) from topic_tweet_urls").flat()[0]
    assert num_urls == expected_num_urls

    total_json_urls = 0
    for topic_tweet in topic_tweets:

        ch_post = dict(mediawords.util.json.decode_json(topic_tweet['data']))
        expected_urls = [x['expanded_url'] for x in ch_post['tweet']['entities']['urls']]
        total_json_urls += len(expected_urls)

        for expected_url in expected_urls:
            got_url = db.query("select * from topic_tweet_urls where url = %(a)s", {'a': expected_url}).hash()
            assert got_url is not None

    assert total_json_urls == num_urls


@unittest.skipUnless(os.environ.get('MC_REMOTE_TESTS', False), "remote tests")
def test_twitter_api() -> None:
    """Test Twitter.fetch_100_tweets() by hitting the remote twitter api."""
    config = mediawords.util.config.get_config()

    assert 'twitter' in config, "twitter section present in mediawords.yml"
    for key in 'consumer_key consumer_secret access_token access_token_secret test_status_id'.split():
        assert key in config['twitter'], "twitter." + key + " present in mediawords.yml"

    test_status_id = int(config['twitter']['test_status_id'])
    got_tweets = mediawords.tm.fetch_topic_tweets.Twitter.fetch_100_tweets([test_status_id])

    assert len(got_tweets) == 1

    got_tweet = got_tweets[0]

    assert 'text' in got_tweet
    assert len(got_tweet['text']) > MIN_TEST_TWEET_LENGTH
    assert 'user' in got_tweet
    assert 'screen_name' in got_tweet['user']
    assert len(got_tweet['user']['screen_name']) > MIN_TEST_TWITTER_USER_LENGTH


@unittest.skipUnless(os.environ.get('MC_REMOTE_TESTS', False), "remote tests")
def test_ch_api() -> None:
    """Test CrimsonHexagon.fetch_posts() by hitting the remote ch api."""
    config = mediawords.util.config.get_config()

    assert 'crimson_hexagon' in config, "crimson_hexagon section present in mediawords.yml"
    for key in 'key test_monitor_id test_date'.split():
        assert key in config['crimson_hexagon'], "crimson_hexagon." + key + " present in mediawords.yml"

    test_monitor_id = config['crimson_hexagon']['test_monitor_id']
    test_date = datetime.datetime.strptime(config['crimson_hexagon']['test_date'], '%Y-%m-%d')

    got_data = mediawords.tm.fetch_topic_tweets.CrimsonHexagon.fetch_posts(test_monitor_id, test_date)

    # sanity test even though we don't know how many posts we should get back, but we want to make sure it is more
    # than 500 to make CH is not limiting us to the default 500 in their api
    assert 'totalPostsAvailable' in got_data
    assert got_data['totalPostsAvailable'] > MIN_TEST_CH_POSTS

    assert 'posts' in got_data
    got_posts = got_data['posts']
    assert len(got_posts) > MIN_TEST_CH_POSTS

    for post in got_posts:
        assert 'url' in post
        assert re.search('status/\d+', post['url'])


class TestFetchTopicTweets(TestDatabaseWithSchemaTestCase):
    """Run database tests."""

    def test_fetch_topic_tweets(self) -> None:
        """Run fetch_topic_tweet tests with test database."""
        db = self.db()
        topic = mediawords.test.db.create_test_topic(db, 'test')

        test_dates = get_test_date_range()
        topic['start_date'] = test_dates[0]
        topic['end_date'] = test_dates[1]
        topic['ch_monitor_id'] = 123456
        db.update_by_id('topics', topic['topics_id'], topic)

        mediawords.tm.fetch_topic_tweets.fetch_topic_tweets(db, topic['topics_id'], MockTwitter, MockCrimsonHexagon)

        topic_tweet_days = db.query("select * from topic_tweet_days").hashes()
        assert len(topic_tweet_days) == LOCAL_DATE_RANGE + 1

        start_date = datetime.datetime.strptime(topic['start_date'], '%Y-%m-%d')
        test_days = [start_date + datetime.timedelta(days=x) for x in range(0, LOCAL_DATE_RANGE)]
        for d in test_days:
            topic_tweet_day = db.query(
                "select * from topic_tweet_days where topics_id = %(a)s and day = %(b)s",
                {'a': topic['topics_id'], 'b': d}
            ).hash()
            assert topic_tweet_day is not None

            validate_topic_tweets(db, topic_tweet_day)

        validate_topic_tweet_urls(db, topic)

    @unittest.skipUnless(os.environ.get('MC_REMOTE_TESTS', False), "remote tests")
    def test_remote_integration(self) -> None:
        """Run santity test on remote apis by calling the internal functions that integrate the CH and twitter data."""
        db = self.db()
        config = mediawords.util.config.get_config()

        topic = mediawords.test.db.create_test_topic(db, "test_remote_integration")
        topic['ch_monitor_id'] = config['crimson_hexagon']['test_monitor_id']
        db.update_by_id('topics', topic['topics_id'], topic)

        ttd = mediawords.tm.fetch_topic_tweets._add_topic_tweet_single_day(
            db,
            topic,
            datetime.datetime(year=2016, month=1, day=1),
            mediawords.tm.fetch_topic_tweets.CrimsonHexagon)

        max_tweets = 200
        mediawords.tm.fetch_topic_tweets._fetch_tweets_for_day(
            db,
            mediawords.tm.fetch_topic_tweets.Twitter,
            topic,
            ttd,
            max_tweets=max_tweets)

        got_tts = db.query(
            "select * from topic_tweets where topic_tweet_days_id = %(a)s",
            {'a': ttd['topic_tweet_days_id']}).hashes()

        # for old ch monitors, lots of the tweets may be deleted
        assert len(got_tts) > max_tweets / 10

        assert len(got_tts[0]['content']) > MIN_TEST_TWEET_LENGTH
        assert len(got_tts[0]['twitter_user']) > MIN_TEST_TWITTER_USER_LENGTH
