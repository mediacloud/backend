"""Test mediawords.tm.stories."""

import mediawords.test.test_database
import mediawords.tm.stories


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


class TestTMStoriesDB(mediawords.test.test_database.TestDatabaseWithSchemaTestCase):
    """Run tests that require database access."""

    def test_get_story_with_most_sentences(self) -> None:
        """Test _get_story_with_most_senences()."""
        db = self.db()

        medium = mediawords.test.db.create_test_medium(db, "foo")
        feed = mediawords.test.db.create_test_feed(db=db, label="foo", medium=medium)

        num_filled_stories = 5
        stories = []
        for i in range(num_filled_stories):
            story = mediawords.test.db.create_test_story(db=db, label="foo" + str(i), feed=feed)
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
            story = mediawords.test.db.create_test_story(db=db, label="foo empty" + str(i), feed=feed)
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
            medium = mediawords.test.db.create_test_medium(db, "foo " + str(i))
            feed = mediawords.test.db.create_test_feed(db=db, label="foo", medium=medium)
            story = mediawords.test.db.create_test_story(db=db, label="foo", feed=feed)
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
