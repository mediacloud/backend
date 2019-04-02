"""Test mediawords.tm.media.*."""

from mediawords.test.db.create import create_test_medium
from mediawords.test.test_database import TestDatabaseTestCase
from mediawords.util.log import create_logger
from mediawords.util.url import normalize_url_lossy

from mediawords.tm.media import (
    _normalize_url,
    MAX_URL_LENGTH,
    _normalized_urls_out_of_date,
    generate_medium_url_and_name_from_url,
    _update_media_normalized_urls,
    lookup_medium,
    McTopicMediaException,
    get_unique_medium_url,
    URL_SPIDERED_SUFFIX,
    McTopicMediaUniqueException,
    get_unique_medium_name,
    get_spidered_tag,
    SPIDERED_TAG_TAG,
    SPIDERED_TAG_SET,
    guess_medium,
)

log = create_logger(__name__)


def test_normalize_url() -> None:
    """Test normalize_url()."""
    assert _normalize_url('http://www.foo.com/') == 'http://foo.com/'
    assert _normalize_url('http://foo.com') == 'http://foo.com/'
    assert _normalize_url('http://articles.foo.com/') == 'http://foo.com/'

    long_url = 'http://foo.com/' + ('x' * (1024 * 1024))
    assert len(_normalize_url(long_url)) == MAX_URL_LENGTH


def test_generate_medium_url_and_name_from_url() -> None:
    """Test generate_medium_url_and_name_from_url()."""
    (url, name) = generate_medium_url_and_name_from_url('http://foo.com/bar')
    assert url == 'http://foo.com/'
    assert name == 'foo.com'


class TestTMMediaDB(TestDatabaseTestCase):
    """Run tests that require database access."""

    def test_normalized_urls_out_of_date(self) -> None:
        """Test _normalized_urls_out_of_date()."""
        db = self.db()

        assert not _normalized_urls_out_of_date(db)

        [create_test_medium(db, str(i)) for i in range(5)]

        assert _normalized_urls_out_of_date(db)

        db.query("update media set normalized_url = url")

        assert not _normalized_urls_out_of_date(db)

        db.query("update media set normalized_url = null where media_id in ( select media_id from media limit 1 )")

        assert _normalized_urls_out_of_date(db)

        db.query("update media set normalized_url = url")

        assert not _normalized_urls_out_of_date(db)

    def test_update_media_normalized_urls(self) -> None:
        """Test _update_media_normalized_urls()."""
        db = self.db()

        [create_test_medium(db, str(i)) for i in range(5)]

        _update_media_normalized_urls(db)

        media = db.query("select * from media").hashes()
        for medium in media:
            expected_nu = normalize_url_lossy(medium['url'])
            assert (medium['url'] == expected_nu)

    def test_lookup_medium(self) -> None:
        """Test lookup_medium()."""
        db = self.db()

        num_media = 5
        [create_test_medium(db, str(i)) for i in range(num_media)]

        # dummy call to lookup_medium to set normalized_urls
        lookup_medium(db, 'foo', 'foo')

        media = db.query("select * from media order by media_id").hashes()

        assert lookup_medium(db, 'FAIL', 'FAIL') is None

        for i in range(num_media):
            assert lookup_medium(db, media[i]['url'], 'IGNORE') == media[i]
            assert lookup_medium(db, media[i]['url'].upper(), 'IGNORE') == media[i]
            assert lookup_medium(db, 'IGNORE', media[i]['name']) == media[i]
            assert lookup_medium(db, 'IGNORE', media[i]['name'].upper()) == media[i]

        db.query(
            "update media set dup_media_id = %(a)s where media_id = %(b)s",
            {'a': media[1]['media_id'], 'b': media[2]['media_id']})
        db.query(
            "update media set dup_media_id = %(a)s where media_id = %(b)s",
            {'a': media[2]['media_id'], 'b': media[3]['media_id']})

        assert lookup_medium(db, media[3]['url'], 'IGNORE') == media[1]

        db.query(
            "update media set foreign_rss_links = 't' where media_id = %(a)s",
            {'a': media[1]['media_id']})

        self.assertRaises(
            McTopicMediaException,
            lookup_medium, db, media[3]['url'], 'IGNORE')

        db.query(
            "update media set dup_media_id = %(a)s where media_id = %(b)s",
            {'a': media[3]['media_id'], 'b': media[1]['media_id']})

        self.assertRaises(
            McTopicMediaException,
            lookup_medium, db, media[3]['url'], 'IGNORE')

    def test_get_unique_media_url(self) -> None:
        """Test get_unique_media_url()."""
        db = self.db()

        num_media = 5
        [create_test_medium(db, str(i)) for i in range(num_media)]
        media = db.query("select * from media order by media_id").hashes()

        assert get_unique_medium_url(db, ['UNIQUE']) == 'UNIQUE'

        media_urls = [m['url'] for m in media]

        expected_url = media[0]['url'] + URL_SPIDERED_SUFFIX
        assert get_unique_medium_url(db, media_urls) == expected_url

        db.query(
            "insert into media (name, url) select name || %(a)s, url || %(a)s from media",
            {'a': URL_SPIDERED_SUFFIX})

        self.assertRaises(
            McTopicMediaUniqueException,
            get_unique_medium_url, db, media_urls)

        assert get_unique_medium_url(db, media_urls + ['UNIQUE']) == 'UNIQUE'

    def test_get_unique_media_name(self) -> None:
        """Test get_unique_media_name()."""
        db = self.db()

        num_media = 5
        [create_test_medium(db, str(i)) for i in range(num_media)]
        media = db.query("select * from media order by media_id").hashes()

        assert get_unique_medium_name(db, ['UNIQUE']) == 'UNIQUE'

        media_names = [m['name'] for m in media]
        self.assertRaises(
            McTopicMediaUniqueException,
            get_unique_medium_name, db, media_names)

        assert get_unique_medium_name(db, media_names + ['UNIQUE']) == 'UNIQUE'

    def test_get_spidered_tag(self) -> None:
        """Test get_spidered_tag()."""
        db = self.db()

        tag = get_spidered_tag(db)

        assert tag['tag'] == SPIDERED_TAG_TAG

        tag_set = db.require_by_id('tag_sets', tag['tag_sets_id'])
        assert tag_set['name'] == SPIDERED_TAG_SET

        assert get_spidered_tag(db)['tags_id'] == tag['tags_id']

    def test_guess_medium(self) -> None:
        """Test guess_medium()."""
        db = self.db()

        num_media = 5
        [create_test_medium(db, str(i)) for i in range(num_media)]

        # the default test media do not have unique domains
        db.query("update media set url = 'http://media-' || media_id ||'.com'")

        # dummy guess_medium call to assign normalized_urls
        guess_medium(db, 'foo')

        media = db.query("select * from media order by media_id").hashes()

        # basic lookup of existing media
        assert guess_medium(db, media[0]['url']) == media[0]
        assert guess_medium(db, media[1]['url'] + '/foo/bar/') == media[1]
        assert guess_medium(db, media[2]['url'] + URL_SPIDERED_SUFFIX) == media[2]

        # create a new medium
        new_medium_story_url = 'http://new-medium.com/with/path'
        new_medium = guess_medium(db, new_medium_story_url)
        assert new_medium['name'] == 'new-medium.com'
        assert new_medium['url'] == 'http://new-medium.com/'

        spidered_tag = get_spidered_tag(db)
        spidered_mtm = db.query(
            "select * from media_tags_map where tags_id = %(a)s and media_id = %(b)s",
            {'a': spidered_tag['tags_id'], 'b': new_medium['media_id']})
        assert spidered_mtm is not None

        # find the url with some url varients
        new_medium_url_variants = [
            'http://new-medium.com/with/another/path',
            'http://www.new-medium.com/',
            'http://new-medium.com/with/path#andanchor'
        ]

        for url in new_medium_url_variants:
            assert guess_medium(db, url)['media_id'] == new_medium['media_id']

        # set foreign_rss_links to true to make guess_medium create another new medium
        db.query("update media set foreign_rss_links = 't' where media_id = %(a)s", {'a': new_medium['media_id']})

        another_new_medium = guess_medium(db, new_medium_story_url)
        assert another_new_medium['media_id'] > new_medium['media_id']
        assert another_new_medium['url'] == new_medium_story_url
        assert another_new_medium['name'] == 'http://new-medium.com/'

        # now try finding a dup
        db.query(
            "update media set dup_media_id = %(a)s where media_id = %(b)s",
            {'a': media[0]['media_id'], 'b': media[1]['media_id']})

        assert guess_medium(db, media[1]['url'])['media_id'] == media[0]['media_id']

        # now make
