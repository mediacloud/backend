import copy

from mediawords.dbi.stories import is_new
from mediawords.test.db import create_test_story_stack
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
from mediawords.util.sql import increment_day


class TestStories(TestDatabaseWithSchemaTestCase):
    def test_is_new(self):
        def __is_new(base_story: dict, story_changes: dict = None) -> bool:
            """Wrapper around is_new() which optionally modifies the story dict in a provided way."""
            story_ = copy.deepcopy(base_story)
            if story_changes is not None:
                for key, value in story_changes.items():
                    story_[key] = value
            return is_new(db=self.db(), story=story_)

        data = {
            'A': {
                'B': [1, 2, 3],
                'C': [4, 5, 6],
            },
            'D': {
                'E': [7, 8, 9],
            }
        }
        media = create_test_story_stack(db=self.db(), data=data)

        for medium in data.keys():
            medium = media[medium]
            for feed in medium['feeds'].values():
                for story in feed['stories'].values():
                    publish_date = story['publish_date']
                    plus_two_days = increment_day(date=publish_date, days=2)
                    minus_two_days = increment_day(date=publish_date, days=-2)

                    # Identical
                    assert __is_new(base_story=story) is False

                    # media_id diff
                    assert __is_new(base_story=story,
                                    story_changes={'media_id': story['media_id'] + 1}) is True

                    # url+guid diff, title same
                    assert __is_new(base_story=story,
                                    story_changes={'url': "diff", 'guid': "diff"}) is False

                    # title+url diff, guid same
                    assert __is_new(base_story=story,
                                    story_changes={'url': "diff", 'title': "diff"}) is False

                    # title+guid diff, url same
                    assert __is_new(base_story=story,
                                    story_changes={'guid': "diff", 'title': "diff"}) is True

                    # date +2days
                    assert __is_new(base_story=story,
                                    story_changes={'url': "diff", 'guid': "diff",
                                                   'publish_date': plus_two_days}) is True

                    assert __is_new(base_story=story,
                                    story_changes={'url': "diff", 'guid': "diff",
                                                   'publish_date': minus_two_days}) is True
