from typing import List, Dict, Any

# noinspection PyProtectedMember
from mediawords.dbi.stories.extractor_version import (
    _get_extractor_version_tag_set,
    _get_tags_id,
    extractor_version_tag_sets_name,
    update_extractor_version_tag,
    _purge_extractor_version_caches,
)
from mediawords.test.db import create_test_medium, create_test_feed, create_test_story
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase


class TestExtractorVersion(TestDatabaseWithSchemaTestCase):

    def setUp(self):
        super().setUp()

        _purge_extractor_version_caches()

    def test_get_tags_id(self):
        tag_set = _get_extractor_version_tag_set(db=self.db())
        tag_sets_id = tag_set['tag_sets_id']

        tag_name = 'arbitary tag'

        tags_id = _get_tags_id(db=self.db(), tag_sets_id=tag_sets_id, tag_name=tag_name)
        assert tags_id

        # See if caching works
        cached_tags_id = _get_tags_id(db=self.db(), tag_sets_id=tag_sets_id, tag_name=tag_name)
        assert cached_tags_id == tags_id

    def test_get_extractor_version_tag_set(self):
        tag_set = _get_extractor_version_tag_set(db=self.db())
        assert tag_set['name'] == 'extractor_version'

        # See if caching works
        cached_tag_set = _get_extractor_version_tag_set(db=self.db())
        assert tag_set == cached_tag_set

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

        update_extractor_version_tag(db=self.db(), story=test_story)

        story_extractor_tags = self.__story_extractor_tags(stories_id=test_story['stories_id'])
        assert len(story_extractor_tags) == 1
