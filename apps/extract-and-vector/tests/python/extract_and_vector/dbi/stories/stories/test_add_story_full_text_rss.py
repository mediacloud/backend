from mediawords.dbi.stories.stories import add_story
from .setup_test_stories import TestStories


class TestAddStoryFullTextRSS(TestStories):

    def test_add_story_full_text_rss(self):
        """Test add_story() with only parent media's full_text_rss set to True."""

        media_id = self.test_medium['media_id']
        feeds_id = self.test_feed['feeds_id']

        self.db.update_by_id(
            table='media',
            object_id=media_id,
            update_hash={'full_text_rss': True},
        )

        story = {
            'media_id': media_id,
            'url': 'http://add.story/',
            'guid': 'http://add.story/',
            'title': 'test add story',
            'description': 'test add story',
            'publish_date': '2016-10-15 08:00:00',
            'collect_date': '2016-10-15 10:00:00',
            # 'full_text_rss' to be inferred from parent "media" item
        }
        added_story = add_story(db=self.db, story=story, feeds_id=feeds_id)
        assert added_story
        assert 'stories_id' in added_story
        assert story['url'] == added_story['url']
        assert added_story['full_text_rss'] is True
