"""Test mediawords.tm.media.*."""

import unittest

import mediawords.tm.media
import mediawords.test.test_database
from mediawords.util.log import create_logger

log = create_logger(__name__)


def test_normalize_url() -> None:
    """Test normalize_url()."""
    assert mediawords.tm.media._normalize_url('http://www.foo.com/') == 'http://foo.com/'
    assert mediawords.tm.media._normalize_url('http://foo.com') == 'http://foo.com/'
    assert mediawords.tm.media._normalize_url('http://articles.foo.com/') == 'http://foo.com/'

    long_url = 'http://foo.com/' + ('x' * (1024 * 1024))
    assert len(mediawords.tm.media._normalize_url(long_url)) == mediawords.tm.media._MAX_URL_LENGTH


def test_generate_medium_url_and_name_from_url() -> None:
    """Test generate_medium_url_and_name_from_url()."""
    (url, name) = mediawords.tm.media.generate_medium_url_and_name_from_url('http://foo.com/bar')
    assert url == 'http://foo.com/'
    assert name == 'foo.com'


class TestTMMediaDB(mediawords.test.test_database.TestDatabaseWithSchemaTestCase):
    """Run tests that require database access."""

    def test_normalized_urls_out_of_date(self) -> None:
        """Test _normalized_urls_out_of_date()."""
        db = self.db()

        assert not mediawords.tm.media._normalized_urls_out_of_date(db)

        [mediawords.test.db.create_test_medium(db, str(i)) for i in range(5)]

        assert mediawords.tm.media._normalized_urls_out_of_date(db)

        db.query(
            """
            insert into media_normalized_urls (media_id, normalized_url, normalize_url_lossy_version)
                select media_id, url, %(a)s from media
            """,
            {'a': mediawords.util.url.normalize_url_lossy_version()})

        assert not mediawords.tm.media._normalized_urls_out_of_date(db)

        db.query("update media_normalized_urls set normalize_url_lossy_version = normalize_url_lossy_version - 1")

        assert mediawords.tm.media._normalized_urls_out_of_date(db)

    def test_update_media_normalized_urls(self) -> None:
        """Test _update_media_normalized_urls()."""
        db = self.db()

        [mediawords.test.db.create_test_medium(db, str(i)) for i in range(5)]

        mediawords.tm.media._update_media_normalized_urls(db)

        got_mnu = db.query(
            """
            select media_id, normalized_url, normalize_url_lossy_version
                from media_normalized_urls
                order by media_id
            """).hashes()

        media = db.query("select * from media order by media_id").hashes()
        expected_mnu = list()  # type: list
        for medium in media:
            mnu = {'media_id': medium['media_id']}
            mnu['normalized_url'] = mediawords.tm.media._normalize_url(medium['url'])
            mnu['normalize_url_lossy_version'] = mediawords.util.url.normalize_url_lossy_version()
            expected_mnu.append(mnu)

        assert got_mnu == expected_mnu

    def test_lookup_medium(self) -> None:
        """Test lookup_medium()."""
        db = self.db()

        num_media = 5
        [mediawords.test.db.create_test_medium(db, str(i)) for i in range(num_media)]
        media = db.query("select * from media order by media_id").hashes()

        assert mediawords.tm.media.lookup_medium(db, 'FAIL', 'FAIL') is None

        for i in range(num_media):
            assert mediawords.tm.media.lookup_medium(db, media[i]['url'], 'IGNORE') == media[i]
            assert mediawords.tm.media.lookup_medium(db, media[i]['url'].upper(), 'IGNORE') == media[i]
            assert mediawords.tm.media.lookup_medium(db, 'IGNORE', media[i]['name']) == media[i]
            assert mediawords.tm.media.lookup_medium(db, 'IGNORE', media[i]['name'].upper()) == media[i]

        db.query(
            "update media set dup_media_id = %(a)s where media_id = %(b)s",
            {'a': media[1]['media_id'], 'b': media[2]['media_id']})
        db.query(
            "update media set dup_media_id = %(a)s where media_id = %(b)s",
            {'a': media[2]['media_id'], 'b': media[3]['media_id']})

        assert mediawords.tm.media.lookup_medium(db, media[3]['url'], 'IGNORE') == media[1]

        db.query(
            "update media set foreign_rss_links = 't' where media_id = %(a)s",
            {'a': media[1]['media_id']})

        self.assertRaises(
            mediawords.tm.media.McTopicMediaException,
            mediawords.tm.media.lookup_medium, db, media[3]['url'], 'IGNORE')

        db.query(
            "update media set dup_media_id = %(a)s where media_id = %(b)s",
            {'a': media[3]['media_id'], 'b': media[1]['media_id']})

        self.assertRaises(
            mediawords.tm.media.McTopicMediaException,
            mediawords.tm.media.lookup_medium, db, media[3]['url'], 'IGNORE')

    def test_get_unique_media_name(self) -> None:
        """Test get_unique_media_name()."""
        db = self.db()

        num_media = 5
        [mediawords.test.db.create_test_medium(db, str(i)) for i in range(num_media)]
        media = db.query("select * from media order by media_id").hashes()

        assert mediawords.tm.media.get_unique_medium_name(db, ['UNIQUE']) == 'UNIQUE'

        media_names = [m['name'] for m in media]
        self.assertRaises(
            mediawords.tm.media.McTopicMediaNameException,
            mediawords.tm.media.get_unique_medium_name, db, media_names)

        assert mediawords.tm.media.get_unique_medium_name(db, media_names + ['UNIQUE']) == 'UNIQUE'
