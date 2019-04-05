import time

import mediawords.crawler.provider
import mediawords.test.db.create
import mediawords.test.test_database
from mediawords.util.sql import sql_now, get_sql_date_from_epoch


class TestTMCrawlerProviderDB(mediawords.test.test_database.TestDatabaseWithSchemaTestCase):
    """Run tests that require database access."""

    def test_add_stale_feeds(self) -> None:
        """Test _add_stale_feeds()."""
        db = self.db()

        medium = mediawords.test.db.create.create_test_medium(db, 'foo')

        pending_feeds = []

        feed = {
            'media_id': medium['media_id'],
            'name': 'null last download',
            'url': 'http://null last download',
            'type': 'syndicated',
            'active': True,
            'last_attempted_download_time': None
        }
        feed = db.create('feeds', feed)
        pending_feeds.append(feed)

        feed = {
            'media_id': medium['media_id'],
            'name': 'recent last download',
            'url': 'http://recent last download',
            'type': 'syndicated',
            'active': True,
            'last_attempted_download_time': sql_now()
        }
        feed = db.create('feeds', feed)

        feed = {
            'media_id': medium['media_id'],
            'name': 'recent last new story',
            'url': 'http://recent last new story',
            'type': 'syndicated',
            'active': True,
            'last_attempted_download_time': sql_now(),
            'last_new_story_time': sql_now()
        }
        feed = db.create('feeds', feed)

        feed = {
            'media_id': medium['media_id'],
            'name': '5 minute new story',
            'url': 'http://5 minute new story',
            'type': 'syndicated',
            'active': True,
            'last_attempted_download_time': get_sql_date_from_epoch(time.time() - 300),
            'last_new_story_time': get_sql_date_from_epoch(time.time() - 300),
        }
        feed = db.create('feeds', feed)
        pending_feeds.append(feed)

        feed = {
            'media_id': medium['media_id'],
            'name': 'old last download',
            'url': 'http://old last download',
            'type': 'syndicated',
            'active': True,
            'last_attempted_download_time': get_sql_date_from_epoch(time.time() - (86400 * 10))
        }
        feed = db.create('feeds', feed)
        pending_feeds.append(feed)

        mediawords.crawler.provider._add_stale_feeds(db)

        num_pending_downloads = db.query("select count(*) from downloads where state = 'pending'").flat()[0]
        assert num_pending_downloads == len(pending_feeds)

        for feed in pending_feeds:
            exists = db.query(
                "select * from downloads where state = 'pending' and feeds_id = %(a)s",
                {'a': feed['feeds_id']}).hash()
            assert exists, "download for feed %s added" % feed['name']

    def test_run_provider(self) -> None:
        """Test run_provider()."""
        db = self.db()

        medium = mediawords.test.db.create.create_test_medium(db, 'foo')
        feed = mediawords.test.db.create.create_test_feed(db, 'foo', medium=medium)

        hosts = ('foo.bar', 'bar.bat', 'bat.baz')
        downloads_per_host = 3

        for host in hosts:
            for i in range(downloads_per_host):
                download = {
                    'feeds_id': feed['feeds_id'],
                    'state': 'pending',
                    'priority': 1,
                    'sequence': 1,
                    'type': 'content',
                    'url': 'http://' + host + '/' + str(i),
                    'host': host}

                db.create('downloads', download)

        mediawords.crawler.provider.run_provider(db, daemon=False)
        assert len(hosts) == db.query("select count(distinct downloads_id) from queued_downloads").flat()[0]

        # make sure that the next loop doesn't just add the same downloads_id values again
        time.sleep(1)
        mediawords.crawler.provider.run_provider(db, daemon=False)
        assert 2 * len(hosts) == db.query("select count(distinct downloads_id) from queued_downloads").flat()[0]

    def test_provide_download_ids(self) -> None:
        """Test provide_download_ids()."""
        db = self.db()

        medium = mediawords.test.db.create.create_test_medium(db, 'foo')
        feed = mediawords.test.db.create.create_test_feed(db, 'foo', medium=medium)

        hosts = ('foo.bar', 'bar.bat', 'bat.baz')
        downloads_per_host = 3

        for host in hosts:
            for i in range(downloads_per_host):
                download = {
                    'feeds_id': feed['feeds_id'],
                    'state': 'pending',
                    'priority': 1,
                    'sequence': 1,
                    'type': 'content',
                    'url': 'http://' + host + '/' + str(i),
                    'host': host}

                db.create('downloads', download)

        for i in range(downloads_per_host):
            download_ids = mediawords.crawler.provider.provide_download_ids(db)
            assert len(download_ids) == len(hosts)

        download_ids = mediawords.crawler.provider.provide_download_ids(db)
        assert len(download_ids) == 0

        # reset host timing for any subsequent tests
        time.sleep(1)
