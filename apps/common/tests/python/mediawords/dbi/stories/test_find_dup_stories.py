from mediawords.db import DatabaseHandler, connect_to_db
# noinspection PyProtectedMember
from mediawords.dbi.stories.stories import _find_dup_stories
from mediawords.test.db.create import create_test_story_stack
from mediawords.util.text import random_string
from mediawords.util.sql import increment_day


def _test_story(db: DatabaseHandler, story: dict, num: int) -> None:
    assert _find_dup_stories(
        db=db,
        story=story,
    ) == [story], f"{num} identical"

    assert _find_dup_stories(
        db=db,
        story={**story, **{
            'media_id': story['media_id'] + 1,
        }},
    ) == [], f"{num} media_id diff"

    assert _find_dup_stories(
        db=db,
        story={**story, **{
            'url': random_string(16),
            'guid': random_string(16),
        }},
    ) == [story], f"{num} URL + GUID diff, title same"

    assert _find_dup_stories(
        db=db,
        story={**story, **{
            'url': random_string(16),
            'title': random_string(16),
        }},
    ) == [story], f"{num} title + URL diff, GUID same"

    assert _find_dup_stories(
        db=db,
        story={**story, **{
            'guid': random_string(16),
            'title': random_string(16),
        }},
    ) == [story], f"{num} title + GUID diff, URL same"

    assert _find_dup_stories(
        db=db,
        story={**story, **{
            'url': story['url'].upper(),
            'guid': random_string(16),
            'title': random_string(16),
        }},
    ) == [story], f"{num} title + GUID diff, normalized url same"

    assert _find_dup_stories(
        db=db,
        story={**story, **{
            'url': random_string(16),
            'guid': random_string(16),
            'publish_date': increment_day(date=story['publish_date'], days=2),
        }},
    ) == [], f"{num} date + 2 days"

    assert _find_dup_stories(
        db=db,
        story={**story, **{
            'url': random_string(16),
            'guid': random_string(16),
            'publish_date': increment_day(date=story['publish_date'], days=-2),
        }},
    ) == [], f"{num} date - 2 days"

    # verify that we can find dup story by the url or guid of a previously dup'd story
    dup_url = random_string(16)
    dup_guid = random_string(16)

    nondup_url = random_string(16)
    nondup_guid = 'bogus unique guid'
    nondup_title = 'bogus unique title'

    dup_stories = _find_dup_stories(db, {**story, **{'url': dup_url, 'guid': dup_guid}})
    assert dup_stories == [story]

    assert _find_dup_stories(db, {**story, **{'url': dup_url, 'title': nondup_title}}) == [story]
    assert _find_dup_stories(db, {**story, **{'guid': dup_guid, 'title': nondup_title}}) == [story]

    nondup_story = {**story, **{'url': nondup_url, 'guid': nondup_guid, 'title': nondup_title}}
    assert _find_dup_stories(db, nondup_story) == []


def test_find_dup_stories():
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
                _test_story(db=db, story=story, num=num)
