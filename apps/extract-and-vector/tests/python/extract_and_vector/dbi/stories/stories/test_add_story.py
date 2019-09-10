from mediawords.dbi.stories.stories import add_story
from .setup_test_stories import TestStories


class TestAddStory(TestStories):

    def test_add_story(self):
        """Test add_story()."""

        media_id = self.test_medium['media_id']
        feeds_id = self.test_feed['feeds_id']

        # Basic story
        story = {
            'media_id': media_id,
            'url': 'http://add.story/',
            'guid': 'http://add.story/',
            'title': 'test add story',
            'description': 'test add story',
            'publish_date': '2016-10-15 08:00:00',
            'collect_date': '2016-10-15 10:00:00',
            'full_text_rss': True,
        }
        added_story = add_story(db=self.db, story=story, feeds_id=feeds_id)
        assert added_story
        assert 'stories_id' in added_story
        assert story['url'] == added_story['url']
        assert added_story['full_text_rss'] is True

        feeds_stories_tag_mapping = self.db.select(
            table='feeds_stories_map',
            what_to_select='*',
            condition_hash={
                'stories_id': added_story['stories_id'],
                'feeds_id': feeds_id,
            }
        ).hashes()
        assert len(feeds_stories_tag_mapping) == 1

        story_urls = self.db.query(
            "select * from story_urls where stories_id = %(a)s",
            {'a': added_story['stories_id']}).hashes()
        assert len(story_urls) == 1
        assert story_urls[0]['url'] == added_story['url']

        # Try adding a duplicate story
        dup_story = add_story(db=self.db, story=story, feeds_id=feeds_id)
        assert dup_story is not None
        assert dup_story['stories_id'] == added_story['stories_id']
