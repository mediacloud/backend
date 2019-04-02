"""Test fetch_twitter_urls."""

import json
import random
import re
import threading
from typing import List
from urllib.parse import urlparse, parse_qs

import httpretty

import mediawords.test.db.create
from mediawords.test.test_database import TestDatabaseTestCase
import mediawords.tm.fetch_link_states
import mediawords.tm.fetch_twitter_urls as ftu

from mediawords.util.log import create_logger

log = create_logger(__name__)


def mock_users_lookup(request, uri, response_headers) -> List:
    """Mock twitter /users/lookup response."""
    params = parse_qs(request.body.decode('utf-8'))

    screen_names = params['screen_name'][0].split(',')

    users = []
    for screen_name in screen_names:
        m = re.match(r'.*_(\d+)$', screen_name)
        if m:
            user_id = m.group(1)
        else:
            # deal with dummy users inserted by mediawords.util.twitter.fetch_100_users() (see comments there)
            user_id = 0

        user = {
            'id': user_id,
            'name': 'test user %s' % user_id,
            'screen_name': screen_name,
            'description': "test description for user %s" % user_id}
        users.append(user)

    return [200, response_headers, json.dumps(users)]


def mock_statuses_lookup(request, uri, response_headers) -> List:
    """Mock twitter /statuses/lookup response."""
    params = parse_qs(urlparse(uri).query)

    ids = params['id'][0].split(',')

    tweets = []
    for id in ids:
        tweet = {
            'id': id,
            'text': 'test content for tweet %s' % id,
            'created_at': 'Mon Dec 13 23:21:48 +0000 2010',
            'user': {'screen_name': 'user %s' % id},
            'entities': {'urls': []}}
        tweets.append(tweet)

    return [200, response_headers, json.dumps(tweets)]


def test_split_urls_into_users_and_statuses() -> None:
    """Test split_urls_into_users_and_statuses()."""
    user_urls = [{'url': u} for u in ['http://twitter.com/foo', 'http://twitter.com/bar']]
    status_urls = [{'url': u} for u in ['https://twitter.com/foo/status/123', 'https://twitter.com/bar/status/456']]
    assert ftu._split_urls_into_users_and_statuses(user_urls + status_urls) == (user_urls, status_urls)


class TestFetchTopicTweets(TestDatabaseTestCase):
    """Run database tests."""

    def test_call_function_on_url_chunk(self) -> None:
        """test _call_function_on_url_chunk."""
        _chunk_collector = []

        def _test_function(db, topic, urls):
            _chunk_collector.append(urls)

        def _error_function(db, topic, urls):
            raise Exception('chunk exception')

        db = self.db()
        topic = mediawords.test.db.create.create_test_topic(db, 'test')

        urls = list(range(ftu.URLS_CHUNK_SIZE * 2))

        ftu._call_function_on_url_chunks(db, topic, urls, _test_function)

        assert _chunk_collector == [urls[0:ftu.URLS_CHUNK_SIZE], urls[ftu.URLS_CHUNK_SIZE:]]

        for i in range(ftu.URLS_CHUNK_SIZE * 2):
            db.create('topic_fetch_urls', {'topics_id': topic['topics_id'], 'url': 'foo', 'state': 'pending'})

        topic_fetch_urls = db.query("select * from topic_fetch_urls").hashes()

        ftu._call_function_on_url_chunks(db, topic, topic_fetch_urls, _error_function)

        [error_count] = db.query(
            "select count(*) from topic_fetch_urls where state = %(a)s",
            {'a': mediawords.tm.fetch_link_states.FETCH_STATE_PYTHON_ERROR}).flat()

        assert error_count == ftu.URLS_CHUNK_SIZE * 2

    def test_add_user_story(self) -> None:
        """Test _add_user_story()."""
        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'test')
        medium = mediawords.test.db.create.create_test_medium(db, 'test')
        feed = mediawords.test.db.create.create_test_feed(db, 'test', medium)
        source_story = mediawords.test.db.create.create_test_story(db, 'source', feed)

        topics_id = topic['topics_id']

        db.create('topic_stories', {'topics_id': topics_id, 'stories_id': source_story['stories_id']})

        topic_link = {'topics_id': topics_id, 'url': 'u', 'stories_id': source_story['stories_id']}
        topic_link = db.create('topic_links', topic_link)

        tfu = {'topics_id': topics_id, 'url': 'u', 'state': 'pending', 'topic_links_id': topic_link['topic_links_id']}
        tfu = db.create('topic_fetch_urls', tfu)

        user = {
            'id': 123,
            'screen_name': 'test_screen_name',
            'name': 'test screen name',
            'description': 'test user description'
        }

        story = ftu._add_user_story(db, topic, user, [tfu])

        got_story = db.require_by_id('stories', story['stories_id'])

        assert got_story['title'] == "%s (%s) | Twitter" % (user['name'], user['screen_name'])
        assert got_story['url'] == 'https://twitter.com/%s' % (user['screen_name'])

        got_topic_link = db.require_by_id('topic_links', topic_link['topic_links_id'])
        assert got_topic_link['ref_stories_id'] == story['stories_id']

        content = '%s (%s): %s' % (user['name'], user['screen_name'], user['description'])
        assert mediawords.dbi.downloads.get_content_for_first_download(db, story) == content

        got_topic_story = db.query(
            "select * from topic_stories where stories_id = %(a)s and topics_id = %(b)s",
            {'a': story['stories_id'], 'b': topic['topics_id']}).hash()
        assert got_topic_story is not None
        assert got_topic_story['link_mined']

        got_undateable_tag = db.query(
            """
            select *
                from stories_tags_map stm
                    join tags t using (tags_id)
                    join tag_sets using(tag_sets_id)
                where
                    stories_id = %(a)s and
                    tag = 'undateable' and
                    name = 'date_invalid'
            """,
            {'a': got_story['stories_id']}).hash()

        assert got_undateable_tag

    def _test_try_fetch_users_chunk_threaded(self, num_threads: int = 1) -> None:
        """Test fetch_100_users using mock. Run in parallel threads to test for race conditions."""

        def _try_fetch_users_chunk_threaded(topic: dict, tfus: list) -> None:
            """Call ftu._try_fetch_users_chunk with a newly created db handle for thread safety."""
            db = mediawords.db.connect_to_db()
            ftu._try_fetch_users_chunk(db, topic, tfus)

        httpretty.enable()  # enable HTTPretty so that it will monkey patch the socket module
        httpretty.register_uri(
            httpretty.POST, "https://api.twitter.com/1.1/users/lookup.json", body=mock_users_lookup)

        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'test')
        topics_id = topic['topics_id']

        num_urls_per_thread = 100

        threads = []
        for j in range(num_threads):
            tfus = []
            for i in range(num_urls_per_thread):
                url = 'https://twitter.com/test_user_%s' % i
                tfu = db.create('topic_fetch_urls', {'topics_id': topics_id, 'url': url, 'state': 'pending'})
                tfus.append(tfu)

            random.shuffle(tfus)

            t = threading.Thread(target=_try_fetch_users_chunk_threaded, args=(topic, tfus))
            t.start()
            threads.append(t)

        [t.join() for t in threads]

        [num_topic_stories] = db.query(
            "select count(*) from topic_stories where topics_id = %(a)s", {'a': topics_id}).flat()
        assert num_urls_per_thread == num_topic_stories

        httpretty.disable()
        httpretty.reset()

    def test_try_fetch_users_chunk_single(self) -> None:
        """Test _try_fetch_users_chunk with a single thread."""
        self._test_try_fetch_users_chunk_threaded(1)

    def test_try_fetch_users_chunk_multiple(self) -> None:
        """Test _try_fetch_users_chunk with a single thread."""
        self._test_try_fetch_users_chunk_threaded(20)

    def test_add_tweet_story(self) -> None:
        """Test _add_test_story()."""
        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'test')
        medium = mediawords.test.db.create.create_test_medium(db, 'test')
        feed = mediawords.test.db.create.create_test_feed(db, 'test', medium)
        source_story = mediawords.test.db.create.create_test_story(db, 'source', feed)

        topics_id = topic['topics_id']

        db.create('topic_stories', {'topics_id': topics_id, 'stories_id': source_story['stories_id']})

        topic_link = {'topics_id': topics_id, 'url': 'u', 'stories_id': source_story['stories_id']}
        topic_link = db.create('topic_links', topic_link)

        tfu = {'topics_id': topics_id, 'url': 'u', 'state': 'pending', 'topic_links_id': topic_link['topic_links_id']}
        tfu = db.create('topic_fetch_urls', tfu)

        tweet = {
            'id': 123,
            'text': 'add tweet story tweet text',
            'user': {'screen_name': 'tweet screen name'},
            'created_at': 'Mon Dec 13 23:21:48 +0000 2010',
            'entities': {'urls': [{'expanded_url': 'http://direct.entity'}]},
            'retweeted_status': {'entities': {'urls': [{'expanded_url': 'http://retweeted.entity'}]}},
            'quoted_status': {'entities': {'urls': [{'expanded_url': 'http://quoted.entity'}]}}
        }

        story = ftu._add_tweet_story(db, topic, tweet, [tfu])

        got_story = db.require_by_id('stories', story['stories_id'])

        assert got_story['title'] == "%s: %s" % (tweet['user']['screen_name'], tweet['text'])
        assert got_story['publish_date'][0:10] == '2010-12-13'
        assert got_story['url'] == 'https://twitter.com/%s/status/%s' % (tweet['user']['screen_name'], tweet['id'])
        assert got_story['guid'] == story['url']

        got_topic_link = db.require_by_id('topic_links', topic_link['topic_links_id'])
        assert got_topic_link['ref_stories_id'] == story['stories_id']

        assert mediawords.dbi.downloads.get_content_for_first_download(db, story) == tweet['text']

        got_topic_story = db.query(
            "select * from topic_stories where stories_id = %(a)s and topics_id = %(b)s",
            {'a': story['stories_id'], 'b': topic['topics_id']}).hash()
        assert got_topic_story is not None
        assert got_topic_story['link_mined']

        for url in (tweet['entities']['urls'][0]['expanded_url'],
                    tweet['retweeted_status']['entities']['urls'][0]['expanded_url'],
                    tweet['quoted_status']['entities']['urls'][0]['expanded_url']):
            got_topic_link = db.query(
                "select * from topic_links where topics_id = %(a)s and url = %(b)s",
                {'a': topic['topics_id'], 'b': url}).hash()
            assert got_topic_link is not None

    def _test_try_fetch_tweets_chunk_threaded(self, num_threads: int = 0) -> None:
        """Test fetch_100_tweets using mock."""

        def _try_fetch_tweets_chunk_threaded(topic: dict, tfus: list) -> None:
            """Call ftu._try_fetch_tweets_chunk with a newly created db handle for thread safety."""
            db = mediawords.db.connect_to_db()
            ftu._try_fetch_tweets_chunk(db, topic, tfus)

        httpretty.enable()
        httpretty.register_uri(
            httpretty.GET, "https://api.twitter.com/1.1/statuses/lookup.json", body=mock_statuses_lookup)

        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'test')
        topics_id = topic['topics_id']

        num_urls_per_thread = 100

        threads = []
        for j in range(num_threads):
            tfus = []
            for i in range(num_urls_per_thread):
                url = 'https://twitter.com/foo/status/%d' % i
                tfu = db.create('topic_fetch_urls', {'topics_id': topics_id, 'url': url, 'state': 'pending'})
                tfus.append(tfu)

            random.shuffle(tfus)

            t = threading.Thread(target=_try_fetch_tweets_chunk_threaded, args=(topic, tfus))
            t.start()
            threads.append(t)

        [t.join() for t in threads]

        [num_topic_stories] = db.query(
            "select count(*) from topic_stories where topics_id = %(a)s", {'a': topics_id}).flat()
        assert num_urls_per_thread == num_topic_stories

        httpretty.disable()
        httpretty.reset()

    def test_try_fetch_tweets_chunk_single(self) -> None:
        """Test _try_fetch_tweets_chunk with a single thread."""
        self._test_try_fetch_tweets_chunk_threaded(1)

    def test_try_fetch_tweets_chunk_multiple(self) -> None:
        """Test _try_fetch_tweets_chunk with a single thread."""
        self._test_try_fetch_tweets_chunk_threaded(20)
