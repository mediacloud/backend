"""Test mediawords.tm.stories."""

from operator import itemgetter
import typing

import mediawords.test.db.create
import mediawords.test.test_database
from mediawords.tm.guess_date import GuessDateResult
import mediawords.tm.stories
from mediawords.tm.stories import url_has_binary_extension
from mediawords.util.log import create_logger

log = create_logger(__name__)


def test_url_domain_matches_medium() -> None:
    """Test story_domain_matches_medium()."""
    medium = {}

    medium['url'] = 'http://foo.com'
    urls = ['http://foo.com/bar/baz']
    assert mediawords.tm.stories._url_domain_matches_medium(medium, urls)

    medium['url'] = 'http://foo.com'
    urls = ['http://bar.com', 'http://foo.com/bar/baz']
    assert mediawords.tm.stories._url_domain_matches_medium(medium, urls)

    medium['url'] = 'http://bar.com'
    urls = ['http://foo.com/bar/baz']
    assert not mediawords.tm.stories._url_domain_matches_medium(medium, urls)


def test_url_has_binary_extension() -> None:
    """Test url_has_binary_extention()."""
    assert not url_has_binary_extension('http://google.com')
    assert not url_has_binary_extension('https://www.nytimes.com/trump-khashoggi-dead.html')
    assert not url_has_binary_extension('https://www.washingtonpost.com/war-has-not/_story.html?utm_term=.c6ddfa7f19')
    assert url_has_binary_extension('http://uproxx.files.wordpress.com/2017/06/push-up.jpg?quality=100&amp;w=1024')
    assert url_has_binary_extension('https://cdn.theatlantic.com/assets/media/files/shubeik_lubeik_byna_mohamed.pdf')
    assert url_has_binary_extension('https://i1.wp.com/7miradas.com/wp-content/uploads8/02/UHJ9OKM.png?resize=62%2C62')


class TestTMStoriesDB(mediawords.test.test_database.TestDatabaseWithSchemaTestCase):
    """Run tests that require database access."""

    def test_get_story_with_most_sentences(self) -> None:
        """Test _get_story_with_most_senences()."""
        db = self.db()

        medium = mediawords.test.db.create.create_test_medium(db, "foo")
        feed = mediawords.test.db.create.create_test_feed(db=db, label="foo", medium=medium)

        num_filled_stories = 5
        stories = []
        for i in range(num_filled_stories):
            story = mediawords.test.db.create.create_test_story(db=db, label="foo" + str(i), feed=feed)
            stories.append(story)
            for n in range(1, i + 1):
                db.create('story_sentences', {
                    'stories_id': story['stories_id'],
                    'media_id': medium['media_id'],
                    'sentence': 'foo',
                    'sentence_number': n,
                    'publish_date': story['publish_date']})

        empty_stories = []
        for i in range(2):
            story = mediawords.test.db.create.create_test_story(db=db, label="foo empty" + str(i), feed=feed)
            empty_stories.append(story)
            stories.append(story)

        assert mediawords.tm.stories._get_story_with_most_sentences(db, stories) == stories[num_filled_stories - 1]

        assert mediawords.tm.stories._get_story_with_most_sentences(db, [empty_stories[0]]) == empty_stories[0]
        assert mediawords.tm.stories._get_story_with_most_sentences(db, empty_stories) == empty_stories[0]

    def test_get_preferred_story(self) -> None:
        """Test get_preferred_story()."""
        db = self.db()

        num_media = 5
        media = []
        stories = []
        for i in range(num_media):
            medium = mediawords.test.db.create.create_test_medium(db, "foo " + str(i))
            feed = mediawords.test.db.create.create_test_feed(db=db, label="foo", medium=medium)
            story = mediawords.test.db.create.create_test_story(db=db, label="foo", feed=feed)
            medium['story'] = story
            media.append(medium)

        # first prefer medium pointed to by dup_media_id of another story
        preferred_medium = media[1]
        db.query(
            "update media set dup_media_id = %(a)s where media_id = %(b)s",
            {'a': preferred_medium['media_id'], 'b': media[0]['media_id']})

        stories = [m['story'] for m in media]
        assert mediawords.tm.stories.get_preferred_story(db, stories) == preferred_medium['story']

        # next prefer any medium without a dup_media_id
        preferred_medium = media[num_media - 1]
        db.query("update media set dup_media_id = null")
        db.query("update media set dup_media_id = %(a)s where media_id != %(a)s", {'a': media[0]['media_id']})
        db.query(
            "update media set dup_media_id = null where media_id = %(a)s",
            {'a': preferred_medium['media_id']})
        stories = [m['story'] for m in media[1:]]
        assert mediawords.tm.stories.get_preferred_story(db, stories) == preferred_medium['story']

        # next prefer the medium whose story url matches the medium domain
        db.query("update media set dup_media_id = null")
        db.query("update media set url='http://media-'||media_id||'.com'")
        db.query("update stories set url='http://stories-'||stories_id||'.com'")

        preferred_medium = media[2]
        db.query(
            "update stories set url = 'http://media-'||media_id||'.com' where media_id = %(a)s",
            {'a': preferred_medium['media_id']})
        stories = db.query("select * from stories").hashes()
        preferred_story = db.query(
            "select * from stories where media_id = %(a)s",
            {'a': preferred_medium['media_id']}).hash()

        assert mediawords.tm.stories.get_preferred_story(db, stories) == preferred_story

        # next prefer lowest media_id
        db.query("update stories set url='http://stories-'||stories_id||'.com'")
        stories = db.query("select * from stories").hashes()
        assert mediawords.tm.stories.get_preferred_story(db, stories)['stories_id'] == media[0]['story']['stories_id']

    def test_ignore_redirect(self) -> None:
        """Test mediawords.tm.stories.ignore_redirect()."""
        db = self.db()

        # redirect_url = None
        assert not mediawords.tm.stories.ignore_redirect(db, 'http://foo.com', None)

        # url = redirect_url
        assert not mediawords.tm.stories.ignore_redirect(db, 'http://foo.com', 'http://foo.com')

        # empty topic_ignore_redirects
        assert not mediawords.tm.stories.ignore_redirect(db, 'http://foo.com', 'http://bar.com')

        # match topic_ingnore_redirects
        redirect_url = 'http://foo.com/foo.bar'
        medium_url = mediawords.tm.media.generate_medium_url_and_name_from_url(redirect_url)[0]
        nu = mediawords.util.url.normalize_url_lossy(medium_url)

        db.create('topic_ignore_redirects', {'url': nu})

        assert mediawords.tm.stories.ignore_redirect(db, 'http://bar.com', redirect_url)

        # no match
        assert not mediawords.tm.stories.ignore_redirect(db, 'http://bar.com', 'http://bat.com')

    def test_get_story_match(self) -> None:
        """Test get_story_match()."""
        db = self.db()

        medium = mediawords.test.db.create.create_test_medium(db, 'foo')
        num_stories = 10
        stories = []
        for i in range(num_stories):
            story = db.create('stories', {
                'media_id': medium['media_id'],
                'url': ('http://stories-%d.com/foo/bar' % i),
                'guid': ('http://stories-%d.com/foo/bar/guid' % i),
                'title': ('story %d' % i),
                'publish_date': '2017-01-01'
            })
            stories.append(story)

        # None
        assert mediawords.tm.stories.get_story_match(db, 'http://foo.com') is None

        # straight and normalized versions of url and redirect_url
        assert mediawords.tm.stories.get_story_match(db, stories[0]['url']) == stories[0]
        assert mediawords.tm.stories.get_story_match(db, 'http://foo.com', stories[1]['url']) == stories[1]
        assert mediawords.tm.stories.get_story_match(db, stories[2]['url'] + '#foo') == stories[2]
        assert mediawords.tm.stories.get_story_match(db, 'http://foo.com', stories[3]['url'] + '#foo') == stories[3]

        # get_preferred_story - return only story with sentences
        db.query(
            """
            insert into story_sentences ( stories_id, media_id, publish_date, sentence, sentence_number )
                select stories_id, media_id, publish_date, 'foo', 1 from stories where stories_id = %(a)s
            """,
            {'a': stories[4]['stories_id']})
        stories = db.query("update stories set url = 'http://stories.com/' returning *").hashes()

        assert mediawords.tm.stories.get_story_match(db, 'http://stories.com/') == stories[4]

    def test_create_download_for_new_story(self) -> None:
        """Test create_download_for_new_story()."""
        db = self.db()

        medium = mediawords.test.db.create.create_test_medium(db, 'foo')
        feed = mediawords.test.db.create.create_test_feed(db=db, label='foo', medium=medium)
        story = mediawords.test.db.create.create_test_story(db=db, label='foo', feed=feed)

        returned_download = mediawords.tm.stories.create_download_for_new_story(db, story, feed)

        assert returned_download is not None

        got_download = db.query("select * from downloads where stories_id = %(a)s", {'a': story['stories_id']}).hash()

        assert got_download is not None

        assert got_download['downloads_id'] == returned_download['downloads_id']
        assert got_download['feeds_id'] == feed['feeds_id']
        assert got_download['url'] == story['url']
        assert got_download['state'] == 'success'
        assert got_download['type'] == 'content'
        assert not got_download['extracted']

    def get_story_date_tag(self, story: dict) -> typing.Optional[tuple]:
        """Return the tag tag_sets dict associated with the story guess method tag sets."""
        tags = self.db().query(
            """
            select t.*
                from tags t
                    join tag_sets ts using ( tag_sets_id )
                    join stories_tags_map stm using ( tags_id )
                where
                    ts.name = any(%(a)s) and
                    stm.stories_id = %(b)s
            """,
            {
                'a': [mediawords.tm.guess_date.GUESS_METHOD_TAG_SET, mediawords.tm.guess_date.INVALID_TAG_SET],
                'b': story['stories_id']
            }).hashes()

        assert len(tags) < 2

        if len(tags) == 1:
            tag = tags[0]
        else:
            return [None, None]

        tag_set = self.db().require_by_id('tag_sets', tag['tag_sets_id'])

        return (tag, tag_set)

    def test_assign_guess_date_tag(self) -> None:
        """Test assign_guess_date_tag()."""
        db = self.db()

        # def __init__(self, found: bool, guess_method: str = None, timestamp: int = None):
        medium = mediawords.test.db.create.create_test_medium(db, 'foo')
        feed = mediawords.test.db.create.create_test_feed(db=db, label='foo', medium=medium)
        story = mediawords.test.db.create.create_test_story(db=db, label='foo', feed=feed)

        result = GuessDateResult(found=True, guess_method='Extracted from url')
        mediawords.tm.stories.assign_date_guess_tag(db, story, result, None)
        (tag, tag_set) = self.get_story_date_tag(story)

        assert tag is not None
        assert tag['tag'] == 'guess_by_url'
        assert tag_set['name'] == mediawords.tm.guess_date.GUESS_METHOD_TAG_SET

        result = GuessDateResult(found=True, guess_method='Extracted from tag:\n\n<meta/>')
        mediawords.tm.stories.assign_date_guess_tag(db, story, result, None)
        (tag, tag_set) = self.get_story_date_tag(story)

        assert tag is not None
        assert tag['tag'] == 'guess_by_tag_meta'
        assert tag_set['name'] == mediawords.tm.guess_date.GUESS_METHOD_TAG_SET

        result = GuessDateResult(found=False, guess_method=None)
        mediawords.tm.stories.assign_date_guess_tag(db, story, result, None)
        (tag, tag_set) = self.get_story_date_tag(story)

        assert tag is not None
        assert tag['tag'] == mediawords.tm.guess_date.INVALID_TAG
        assert tag_set['name'] == mediawords.tm.guess_date.INVALID_TAG_SET

        result = GuessDateResult(found=False, guess_method=None)
        mediawords.tm.stories.assign_date_guess_tag(db, story, result, '2017-01-01')
        (tag, tag_set) = self.get_story_date_tag(story)

        assert tag is not None
        assert tag['tag'] == 'fallback_date'
        assert tag_set['name'] == mediawords.tm.guess_date.GUESS_METHOD_TAG_SET

    def test_get_spider_feed(self) -> None:
        """Test get_spider_feed()."""
        db = self.db()

        medium = mediawords.test.db.create.create_test_medium(db, 'foo')

        feed = mediawords.tm.stories.get_spider_feed(self.db(), medium)

        assert feed['name'] == mediawords.tm.stories.SPIDER_FEED_NAME
        assert feed['media_id'] == medium['media_id']
        assert feed['active'] is False

        assert mediawords.tm.stories.get_spider_feed(self.db(), medium)['feeds_id'] == feed['feeds_id']

    def test_generate_story(self) -> None:
        """Test generate_story()."""
        db = self.db()

        story_content = '<title>foo bar</title><meta content="2016-01-12T03:55:46Z" itemprop="datePublished"/>'
        story_url = 'http://foo.com/foo/bar'
        story = mediawords.tm.stories.generate_story(db=db, url=story_url, content=story_content)

        assert 'stories_id' in story
        assert story['title'] == 'foo bar'
        assert story['publish_date'] == '2016-01-12 00:00:00'
        assert story['url'] == story_url
        assert story['guid'] == story_url

        medium = db.require_by_id('media', story['media_id'])

        assert medium['name'] == 'foo.com'
        assert medium['url'] == 'http://foo.com/'

        feed = db.query(
            "select f.* from feeds f join feeds_stories_map fsm using ( feeds_id ) where stories_id = %(a)s",
            {'a': story['stories_id']}).hash()

        assert feed is not None
        assert feed['name'] == mediawords.tm.stories.SPIDER_FEED_NAME

        (date_tag, date_tag_set) = self.get_story_date_tag(story)

        assert date_tag['tag'] == 'guess_by_tag_meta'
        assert date_tag_set['name'] == mediawords.tm.guess_date.GUESS_METHOD_TAG_SET

        download = db.query("select * from downloads where stories_id = %(a)s", {'a': story['stories_id']}).hash()

        assert download is not None
        assert download['url'] == story['url']

        content = mediawords.dbi.downloads.fetch_content(db, download)

        assert content == story_content

        story = mediawords.tm.stories.generate_story(
            db=db,
            url='http://fallback.date',
            content='foo',
            fallback_date='2011-11-11')

        assert story['publish_date'] == '2011-11-11 00:00:00'

        self.assertRaises(
            mediawords.tm.stories.McTMStoriesDuplicateException,
            mediawords.tm.stories.generate_story, db, story['url'], 'foo')

        story = mediawords.tm.stories.generate_story(db=db, url='invalid url', content='foo')

        assert story is not None

    def test_merge_foreign_rss_stories(self) -> None:
        """Test merge_foreign_rss_stories()."""
        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'foo')

        medium = mediawords.test.db.create.create_test_medium(db, 'norss')
        feed = mediawords.test.db.create.create_test_feed(db=db, label='norss', medium=medium)
        num_stories = 10
        stories = [
            mediawords.test.db.create.create_test_story(db=db, label=str(i), feed=feed)
            for i in range(num_stories)
        ]

        rss_medium = mediawords.test.db.create.create_test_medium(db, 'rss')
        rss_medium = db.query(
            "update media set foreign_rss_links = 't' where media_id = %(a)s returning *",
            {'a': rss_medium['media_id']}).hash()
        rss_feed = mediawords.test.db.create.create_test_feed(db=db, label='rss', medium=rss_medium)
        num_rss_stories = 10
        rss_stories = []
        for i in range(num_rss_stories):
            story = mediawords.test.db.create.create_test_story(db=db, label=i, feed=rss_feed)
            download = db.create('downloads', {
                'stories_id': story['stories_id'],
                'feeds_id': rss_feed['feeds_id'],
                'url': story['url'],
                'host': 'foo',
                'type': 'content',
                'state': 'success',
                'priority': 0,
                'sequence': 0,
                'path': 'postgresql'})
            mediawords.dbi.downloads.store_content(db, download, story['title'])
            rss_stories.append(story)

        db.query(
            "insert into topic_stories (stories_id, topics_id) select s.stories_id, %(a)s from stories s",
            {'a': topic['topics_id']})

        assert db.query("select count(*) from topic_stories").flat()[0] == num_stories + num_rss_stories

        mediawords.tm.stories.merge_foreign_rss_stories(db, topic)

        assert db.query("select count(*) from topic_stories").flat()[0] == num_stories
        assert db.query("select count(*) from topic_seed_urls").flat()[0] == num_rss_stories

        got_topic_stories_ids = db.query("select stories_id from topic_stories").flat()
        expected_topic_stories_ids = [s['stories_id'] for s in stories]
        assert sorted(got_topic_stories_ids) == sorted(expected_topic_stories_ids)

        got_seed_urls = db.query(
            "select topics_id, url, content from topic_seed_urls where topics_id = %(a)s",
            {'a': topic['topics_id']}).hashes()
        expected_seed_urls = \
            [{'url': s['url'], 'topics_id': topic['topics_id'], 'content': s['title']} for s in rss_stories]

        assert sorted(got_seed_urls, key=itemgetter('url')) == sorted(expected_seed_urls, key=itemgetter('url'))

    def test_copy_story_to_new_medium(self) -> None:
        """Test copy_story_to_new_medium."""
        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'copy foo')

        new_medium = mediawords.test.db.create.create_test_medium(db, 'copy new')

        old_medium = mediawords.test.db.create.create_test_medium(db, 'copy old')
        old_feed = mediawords.test.db.create.create_test_feed(db=db, label='copy old', medium=old_medium)
        old_story = mediawords.test.db.create.create_test_story(db=db, label='copy old', feed=old_feed)

        mediawords.test.db.create.add_content_to_test_story(db, old_story, old_feed)

        mediawords.tm.stories.add_to_topic_stories(db, old_story, topic)

        new_story = mediawords.tm.stories.copy_story_to_new_medium(db, topic, old_story, new_medium)

        assert db.find_by_id('stories', new_story['stories_id']) is not None

        for field in 'title url guid publish_date'.split():
            assert old_story[field] == new_story[field]

        topic_story_exists = db.query(
            "select * from topic_stories where topics_id = %(a)s and stories_id = %(b)s",
            {'a': topic['topics_id'], 'b': new_story['stories_id']}).hash()
        assert topic_story_exists is not None

        new_download = db.query(
            "select * from downloads where stories_id = %(a)s",
            {'a': new_story['stories_id']}).hash()
        assert new_download is not None

        content = mediawords.dbi.downloads.fetch_content(db, new_download)
        assert content is not None and len(content) > 0

        story_sentences = db.query(
            "select * from story_sentences where stories_id = %(a)s",
            {'a': new_story['stories_id']}).hashes()
        assert len(story_sentences) > 0

    def test_merge_dup_story(self) -> None:
        """Test merge_dup_story()."""
        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'merge')
        medium = mediawords.test.db.create.create_test_medium(db, 'merge')
        feed = mediawords.test.db.create.create_test_feed(db, 'merge', medium=medium)

        old_story = mediawords.test.db.create.create_test_story(db=db, label='merge old', feed=feed)
        new_story = mediawords.test.db.create.create_test_story(db=db, label='merge new', feed=feed)

        linked_story = mediawords.test.db.create.create_test_story(db=db, label='linked', feed=feed)
        linking_story = mediawords.test.db.create.create_test_story(db=db, label='linking', feed=feed)

        for story in (old_story, new_story, linked_story, linking_story):
            mediawords.tm.stories.add_to_topic_stories(db, story, topic)

        db.create('topic_links', {
            'topics_id': topic['topics_id'],
            'stories_id': old_story['stories_id'],
            'url': old_story['url'],
            'ref_stories_id': linked_story['stories_id']})
        db.create('topic_links', {
            'topics_id': topic['topics_id'],
            'stories_id': linking_story['stories_id'],
            'url': old_story['url'],
            'ref_stories_id': old_story['stories_id']})
        db.create('topic_seed_urls', {
            'topics_id': topic['topics_id'],
            'stories_id': old_story['stories_id']})

        mediawords.tm.stories.merge_dup_story(db, topic, old_story, new_story)

        old_topic_links = db.query(
            "select * from topic_links where topics_id = %(a)s and %(b)s in ( stories_id, ref_stories_id )",
            {'a': topic['topics_id'], 'b': old_story['stories_id']}).hashes()
        assert len(old_topic_links) == 0

        new_topic_links_linked = db.query(
            "select * from topic_links where topics_id = %(a)s and stories_id = %(b)s and ref_stories_id = %(c)s",
            {'a': topic['topics_id'], 'b': new_story['stories_id'], 'c': linked_story['stories_id']}).hashes()
        assert len(new_topic_links_linked) == 1

        new_topic_links_linking = db.query(
            "select * from topic_links where topics_id = %(a)s and ref_stories_id = %(b)s and stories_id = %(c)s",
            {'a': topic['topics_id'], 'b': new_story['stories_id'], 'c': linking_story['stories_id']}).hashes()
        assert len(new_topic_links_linking) == 1

        old_topic_stories = db.query(
            "select * from topic_stories where topics_id = %(a)s and stories_id = %(b)s",
            {'a': topic['topics_id'], 'b': old_story['stories_id']}).hashes()
        assert len(old_topic_stories) == 0

        topic_merged_stories_maps = db.query(
            "select * from topic_merged_stories_map where target_stories_id = %(a)s and source_stories_id = %(b)s",
            {'a': new_story['stories_id'], 'b': old_story['stories_id']}).hashes()
        assert len(topic_merged_stories_maps) == 1

    def test_merge_dup_media_story(self) -> None:
        """Test merge_dup_media_story()."""
        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'merge')
        medium = mediawords.test.db.create.create_test_medium(db, 'merge')
        feed = mediawords.test.db.create.create_test_feed(db, 'merge', medium=medium)
        old_story = mediawords.test.db.create.create_test_story(db=db, label='merge old', feed=feed)

        new_medium = mediawords.test.db.create.create_test_medium(db, 'merge new')

        db.update_by_id('media', medium['media_id'], {'dup_media_id': new_medium['media_id']})

        cloned_story = mediawords.tm.stories.merge_dup_media_story(db, topic, old_story)

        for field in 'url guid publish_date title'.split():
            assert cloned_story[field] == old_story[field]

        topic_story = db.query(
            "select * from topic_stories where stories_id = %(a)s and topics_id = %(b)s",
            {'a': cloned_story['stories_id'], 'b': topic['topics_id']}).hash()
        assert topic_story is not None

        merged_story = mediawords.tm.stories.merge_dup_media_story(db, topic, old_story)
        assert merged_story['stories_id'] == cloned_story['stories_id']

    def test_merge_dup_stories(self) -> None:
        """Test merge_dup_stories()."""
        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'merge')
        medium = mediawords.test.db.create.create_test_medium(db, 'merge')
        feed = mediawords.test.db.create.create_test_feed(db, 'merge', medium=medium)

        num_stories = 10
        stories = []
        for i in range(num_stories):
            story = mediawords.test.db.create.create_test_story(db, "merge " + str(i), feed=feed)
            mediawords.tm.stories.add_to_topic_stories(db, story, topic)
            stories.append(story)
            for j in range(i):
                db.query(
                    """
                    insert into story_sentences (stories_id, sentence_number, sentence, media_id, publish_date)
                        select stories_id, %(b)s, 'foo bar', media_id, publish_date
                            from stories where stories_id = %(a)s
                    """,
                    {'a': story['stories_id'], 'b': j})

        mediawords.tm.stories._merge_dup_stories(db, topic, stories)

        stories_ids = [s['stories_id'] for s in stories]
        merged_stories = db.query(
            "select stories_id from topic_stories where topics_id = %(a)s and stories_id = any(%(b)s)",
            {'a': topic['topics_id'], 'b': stories_ids}).flat()

        assert merged_stories == [stories_ids[-1]]

    def test_find_and_merge_dup_stories(self) -> None:
        """Test find_and_merge_dup_stories()."""
        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'merge')
        medium = mediawords.test.db.create.create_test_medium(db, 'merge')
        feed = mediawords.test.db.create.create_test_feed(db, 'merge', medium=medium)

        num_stories = 10
        stories = []
        for i in range(num_stories):
            story = mediawords.test.db.create.create_test_story(db, "merge " + str(i), feed=feed)
            db.update_by_id('stories', story['stories_id'], {'title': "long dup title foo bar baz"})
            mediawords.tm.stories.add_to_topic_stories(db, story, topic)
            stories.append(story)
            for j in range(i):
                db.query(
                    """
                    insert into story_sentences (stories_id, sentence_number, sentence, media_id, publish_date)
                        select stories_id, %(b)s, 'foo bar', media_id, publish_date
                            from stories where stories_id = %(a)s
                    """,
                    {'a': story['stories_id'], 'b': j})

        mediawords.tm.stories.find_and_merge_dup_stories(db, topic)

        stories_ids = [s['stories_id'] for s in stories]
        merged_stories = db.query(
            "select stories_id from topic_stories where topics_id = %(a)s and stories_id = any(%(b)s)",
            {'a': topic['topics_id'], 'b': stories_ids}).flat()

        assert merged_stories == [stories_ids[-1]]
