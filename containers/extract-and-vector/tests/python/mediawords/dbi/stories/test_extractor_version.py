#!/usr/bin/env py.test

from typing import List, Dict, Any

# noinspection PyProtectedMember
from mediawords.dbi.stories.extractor_version import extractor_version_tag_sets_name, update_extractor_version_tag
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story
from mediawords.test.testing_database import TestDatabaseTestCase


class TestExtractorVersion(TestDatabaseTestCase):

    def __story_extractor_tags(self, stories_id: int) -> List[Dict[str, Any]]:
        return self.db().query("""
            SELECT stories_tags_map.stories_id,
                   tags.tag AS tags_name,
                   tag_sets.name AS tag_sets_name
            FROM stories_tags_map
                INNER JOIN tags
                    ON stories_tags_map.tags_id = tags.tags_id
                INNER JOIN tag_sets
                    ON tags.tag_sets_id = tag_sets.tag_sets_id
            WHERE stories_tags_map.stories_id = %(stories_id)s
              AND tag_sets.name = %(tag_sets_name)s
        """, {'stories_id': stories_id, 'tag_sets_name': extractor_version_tag_sets_name()}).hashes()

    def test_update_extractor_version_tag(self):
        test_medium = create_test_medium(db=self.db(), label='test medium')
        test_feed = create_test_feed(db=self.db(), label='test feed', medium=test_medium)
        test_story = create_test_story(db=self.db(), label='test story', feed=test_feed)

        story_extractor_tags = self.__story_extractor_tags(stories_id=test_story['stories_id'])
        assert len(story_extractor_tags) == 0

        update_extractor_version_tag(
            db=self.db(),
            stories_id=test_story['stories_id'],
            extractor_version="dummy_extractor",
        )

        story_extractor_tags = self.__story_extractor_tags(stories_id=test_story['stories_id'])
        assert len(story_extractor_tags) == 1
