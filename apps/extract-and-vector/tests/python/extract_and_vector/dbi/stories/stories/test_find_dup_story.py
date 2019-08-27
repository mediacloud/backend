from mediawords.db import DatabaseHandler
# noinspection PyProtectedMember
from mediawords.dbi.stories.stories import find_dup_story
from .setup_test_stories import TestStories
from mediawords.test.db.create import create_test_story_stack
from mediawords.util.sql import increment_day


class TestFindDupStory(TestStories):
    __slots__ = [
        'unique_string_generator',
    ]

    def new_unique_str(self) -> str:
        """Return a new unique string each call."""
        self.unique_string_generator += 1
        return str(self.unique_string_generator)

    def test_find_dup_story(self):

        def _test_story(db: DatabaseHandler, story_: dict, num_: int) -> None:

            assert find_dup_story(
                db=db,
                story=story_,
            ) == story_, "{} identical".format(num_)

            assert find_dup_story(
                db=db,
                story={**story_, **{
                    'media_id': story['media_id'] + 1,
                }},
            ) is None, "{} media_id diff".format(num_)

            assert find_dup_story(
                db=db,
                story={**story_, **{
                    'url': self.new_unique_str(),
                    'guid': self.new_unique_str()
                }},
            ) == story_, "{} URL + GUID diff, title same".format(num_)

            assert find_dup_story(
                db=db,
                story={**story_, **{
                    'url': self.new_unique_str(),
                    'title': self.new_unique_str()
                }},
            ) == story_, "{} title + URL diff, GUID same".format(num_)

            assert find_dup_story(
                db=db,
                story={**story_, **{
                    'guid': self.new_unique_str(),
                    'title': self.new_unique_str(),
                }},
            ) == story_, "{} title + GUID diff, URL same".format(num_)

            assert find_dup_story(
                db=db,
                story={**story_, **{
                    'url': story_['url'].upper(),
                    'guid': self.new_unique_str(),
                    'title': self.new_unique_str(),
                }},
            ) == story_, "{} title + GUID diff, nornmalized url same ".format(num_)

            assert find_dup_story(
                db=db,
                story={**story_, **{
                    'url': self.new_unique_str(),
                    'guid': self.new_unique_str(),
                    'publish_date': increment_day(date=story['publish_date'], days=2),
                }},
            ) is None, "{} date + 2 days".format(num_)

            assert find_dup_story(
                db=db,
                story={**story_, **{
                    'url': self.new_unique_str(),
                    'guid': self.new_unique_str(),
                    'publish_date': increment_day(date=story['publish_date'], days=-2),
                }},
            ) is None, "{} date - 2 days".format(num_)

            # verify that we can find dup story by the url or guid of a previously dup'd story
            dup_url = self.new_unique_str()
            dup_guid = self.new_unique_str()

            nondup_url = self.new_unique_str()
            nondup_guid = 'bogus unique guid'
            nondup_title = 'bogus unique title'

            dup_story = find_dup_story(db, {**story_, **{'url': dup_url, 'guid': dup_guid}})
            assert dup_story == story_

            assert find_dup_story(db, {**story, **{'url': dup_url, 'title': nondup_title}}) == story_
            assert find_dup_story(db, {**story, **{'guid': dup_guid, 'title': nondup_title}}) == story_

            nondup_story = {**story, **{'url': nondup_url, 'guid': nondup_guid, 'title': nondup_title}}
            assert find_dup_story(db, nondup_story) is None

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
                    _test_story(db=self.db(), story_=story, num_=num)
