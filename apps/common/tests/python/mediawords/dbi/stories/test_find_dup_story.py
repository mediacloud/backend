from mediawords.db import DatabaseHandler, connect_to_db
# noinspection PyProtectedMember
from mediawords.dbi.stories.stories import _find_dup_story
from mediawords.test.db.create import create_test_story_stack
from mediawords.util.text import random_string
from mediawords.util.sql import increment_day


def test_find_dup_story():

    def _test_story(db: DatabaseHandler, story_: dict, num_: int) -> None:

        assert _find_dup_story(
            db=db,
            story=story_,
        ) == story_, "{} identical".format(num_)

        assert _find_dup_story(
            db=db,
            story={**story_, **{
                'media_id': story['media_id'] + 1,
            }},
        ) is None, "{} media_id diff".format(num_)

        assert _find_dup_story(
            db=db,
            story={**story_, **{
                'url': random_string(16),
                'guid': random_string(16),
            }},
        ) == story_, "{} URL + GUID diff, title same".format(num_)

        assert _find_dup_story(
            db=db,
            story={**story_, **{
                'url': random_string(16),
                'title': random_string(16),
            }},
        ) == story_, "{} title + URL diff, GUID same".format(num_)

        assert _find_dup_story(
            db=db,
            story={**story_, **{
                'guid': random_string(16),
                'title': random_string(16),
            }},
        ) == story_, "{} title + GUID diff, URL same".format(num_)

        assert _find_dup_story(
            db=db,
            story={**story_, **{
                'url': story_['url'].upper(),
                'guid': random_string(16),
                'title': random_string(16),
            }},
        ) == story_, "{} title + GUID diff, normalized url same ".format(num_)

        assert _find_dup_story(
            db=db,
            story={**story_, **{
                'url': random_string(16),
                'guid': random_string(16),
                'publish_date': increment_day(date=story['publish_date'], days=2),
            }},
        ) is None, "{} date + 2 days".format(num_)

        assert _find_dup_story(
            db=db,
            story={**story_, **{
                'url': random_string(16),
                'guid': random_string(16),
                'publish_date': increment_day(date=story['publish_date'], days=-2),
            }},
        ) is None, "{} date - 2 days".format(num_)

        # verify that we can find dup story by the url or guid of a previously dup'd story
        dup_url = random_string(16)
        dup_guid = random_string(16)

        nondup_url = random_string(16)
        nondup_guid = 'bogus unique guid'
        nondup_title = 'bogus unique title'

        dup_story = _find_dup_story(db, {**story_, **{'url': dup_url, 'guid': dup_guid}})
        assert dup_story == story_

        assert _find_dup_story(db, {**story, **{'url': dup_url, 'title': nondup_title}}) == story_
        assert _find_dup_story(db, {**story, **{'guid': dup_guid, 'title': nondup_title}}) == story_

        nondup_story = {**story, **{'url': nondup_url, 'guid': nondup_guid, 'title': nondup_title}}
        assert _find_dup_story(db, nondup_story) is None

    db = connect_to_db()

    data = {
        'A': {
            'B': [1, 2, 3],
            'C': [4, 5, 6],
        },
        'D': {
            'E': [7, 8, 9],
        }
    }

    media = create_test_story_stack(db=db, data=data)
    for media_name, feeds in data.items():
        for feeds_name, stories in feeds.items():
            for num in stories:
                story = media[media_name]['feeds'][feeds_name]['stories'][str(num)]
                _test_story(db=db, story_=story, num_=num)
