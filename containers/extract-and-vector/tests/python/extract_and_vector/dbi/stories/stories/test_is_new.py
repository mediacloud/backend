from mediawords.db import DatabaseHandler
# noinspection PyProtectedMember
from mediawords.dbi.stories.stories import is_new
from .setup_test_stories import TestStories
from mediawords.test.db.create import create_test_story_stack
from mediawords.util.sql import increment_day


class TestIsNew(TestStories):

    def test_is_new(self):

        def _test_story(db: DatabaseHandler, story_: dict, num_: int) -> None:

            assert is_new(
                db=db,
                story=story_,
            ) is False, "{} identical".format(num_)

            assert is_new(
                db=db,
                story={**story_, **{
                    'media_id': story['media_id'] + 1,
                }},
            ) is True, "{} media_id diff".format(num_)

            assert is_new(
                db=db,
                story={**story_, **{
                    'url': 'diff',
                    'guid': 'diff',
                }},
            ) is False, "{} URL + GUID diff, title same".format(num_)

            assert is_new(
                db=db,
                story={**story_, **{
                    'url': 'diff',
                    'title': 'diff',
                }},
            ) is False, "{} title + URL diff, GUID same".format(num_)

            assert is_new(
                db=db,
                story={**story_, **{
                    'guid': 'diff',
                    'title': 'diff',
                }},
            ) is True, "{} title + GUID diff, URL same".format(num_)

            assert is_new(
                db=db,
                story={**story_, **{
                    'url': 'diff',
                    'guid': 'diff',
                    'publish_date': increment_day(date=story['publish_date'], days=2),
                }},
            ) is True, "{} date + 2 days".format(num_)

            assert is_new(
                db=db,
                story={**story_, **{
                    'url': 'diff',
                    'guid': 'diff',
                    'publish_date': increment_day(date=story['publish_date'], days=-2),
                }},
            ) is True, "{} date - 2 days".format(num_)

        data = {
            'A': {
                'B': [1, 2, 3],
                'C': [4, 5, 6],
            },
            'D': {
                'E': [7, 8, 9],
            }
        }

        media = create_test_story_stack(db=self.db, data=data)
        for media_name, feeds in data.items():
            for feeds_name, stories in feeds.items():
                for num in stories:
                    story = media[media_name]['feeds'][feeds_name]['stories'][str(num)]
                    _test_story(db=self.db, story_=story, num_=num)
