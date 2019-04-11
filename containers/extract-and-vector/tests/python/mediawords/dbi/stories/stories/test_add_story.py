#!/usr/bin/env py.test

from mediawords.dbi.stories.stories import add_story
from mediawords.dbi.stories.stories.setup_test_stories import TestStories


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

        # Try adding a duplicate story
        added_story = add_story(db=self.db, story=story, feeds_id=feeds_id)
        assert added_story is None

        # Try adding a duplicate story with explicit "is new" testing disabled
        added_story = add_story(db=self.db, story=story, feeds_id=feeds_id, skip_checking_if_new=True)
        assert added_story is None
