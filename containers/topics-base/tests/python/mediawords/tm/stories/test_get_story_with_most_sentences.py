#!/usr/bin/env py.test

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story

# noinspection PyProtectedMember
from mediawords.tm.stories import _get_story_with_most_sentences


def test_get_story_with_most_sentences():
    """Test _get_story_with_most_senences()."""
    db = connect_to_db()

    medium = create_test_medium(db, "foo")
    feed = create_test_feed(db=db, label="foo", medium=medium)

    num_filled_stories = 5
    stories = []
    for i in range(num_filled_stories):
        story = create_test_story(db=db, label="foo" + str(i), feed=feed)
        stories.append(story)
        for n in range(1, i + 1):
            db.create('story_sentences', {
                'stories_id': story['stories_id'],
                'media_id': medium['media_id'],
                'sentence': 'foo',
                'sentence_number': n,
                'publish_date': story['publish_date']})

    empty_stories = []
    for i in range(2):
        story = create_test_story(db=db, label="foo empty" + str(i), feed=feed)
        empty_stories.append(story)
        stories.append(story)

    assert _get_story_with_most_sentences(db, stories) == stories[num_filled_stories - 1]

    assert _get_story_with_most_sentences(db, [empty_stories[0]]) == empty_stories[0]
    assert _get_story_with_most_sentences(db, empty_stories) == empty_stories[0]
