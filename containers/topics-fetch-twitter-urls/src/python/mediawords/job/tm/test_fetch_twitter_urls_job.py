import random

import httpretty

import mediawords.test.db.create
import mediawords.test.test_database
import mediawords.tm.test_fetch_twitter_urls as tftu


class TestFetchTwitterUrlsJobDB(mediawords.test.test_database.TestDatabaseTestCase):
    """Run tests that require database access."""

    def test_try_fetch_twitter_urls_job(self) -> None:
        """Test fetch_100_tweets using mock."""
        httpretty.enable()
        httpretty.register_uri(
            httpretty.GET, "https://api.twitter.com/1.1/statuses/lookup.json", body=tftu.mock_statuses_lookup)
        httpretty.register_uri(
            httpretty.POST, "https://api.twitter.com/1.1/users/lookup.json", body=tftu.mock_users_lookup)

        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'test')
        topics_id = topic['topics_id']

        tfus = []

        num_tweets = 150
        for i in range(num_tweets):
            url = 'https://twitter.com/foo/status/%d' % i
            tfu = db.create('topic_fetch_urls', {'topics_id': topics_id, 'url': url, 'state': 'pending'})
            tfus.append(tfu)

        num_users = 150
        for i in range(num_users):
            url = 'https://twitter.com/test_user_%s' % i
            tfu = db.create('topic_fetch_urls', {'topics_id': topics_id, 'url': url, 'state': 'pending'})
            tfus.append(tfu)

        tfu_ids = [u['topic_fetch_urls_id'] for u in tfus]
        random.shuffle(tfu_ids)

        FetchTwitterUrlsJob.run(tfu_ids)

        [num_tweet_stories] = db.query(
            """
            select count(*)
                from topic_stories ts
                    join stories s using ( stories_id )
                where topics_id = %(a)s and url ~ '/status/[0-9]+'
            """,
            {'a': topics_id}).flat()
        assert num_tweet_stories == num_tweets

        [num_user_stories] = db.query(
            """
            select count(*)
                from topic_stories ts
                    join stories s using ( stories_id )
                where topics_id = %(a)s and url !~ '/status/[0-9]+'
            """,
            {'a': topics_id}).flat()
        assert num_user_stories == num_users

        httpretty.disable()
        httpretty.reset()
