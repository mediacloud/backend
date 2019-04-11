#!/usr/bin/env py.test

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story
from mediawords.util.guess_date import GuessDateResult, GUESS_METHOD_TAG_SET, INVALID_TAG, INVALID_TAG_SET
from mediawords.tm.stories import assign_date_guess_tag
from mediawords.tm.stories.get_story_date_tag import get_story_date_tag


def test_assign_guess_date_tag():
    """Test assign_guess_date_tag()."""
    db = connect_to_db()

    # def __init__(self, found: bool, guess_method: str = None, timestamp: int = None):
    medium = create_test_medium(db, 'foo')
    feed = create_test_feed(db=db, label='foo', medium=medium)
    story = create_test_story(db=db, label='foo', feed=feed)

    result = GuessDateResult(found=True, guess_method='Extracted from url')
    assign_date_guess_tag(db, story, result, None)
    (tag, tag_set) = get_story_date_tag(db, story)

    assert tag is not None
    assert tag['tag'] == 'guess_by_url'
    assert tag_set['name'] == GUESS_METHOD_TAG_SET

    result = GuessDateResult(found=True, guess_method='Extracted from tag:\n\n<meta/>')
    assign_date_guess_tag(db, story, result, None)
    (tag, tag_set) = get_story_date_tag(db, story)

    assert tag is not None
    assert tag['tag'] == 'guess_by_tag_meta'
    assert tag_set['name'] == GUESS_METHOD_TAG_SET

    result = GuessDateResult(found=False, guess_method=None)
    assign_date_guess_tag(db, story, result, None)
    (tag, tag_set) = get_story_date_tag(db, story)

    assert tag is not None
    assert tag['tag'] == INVALID_TAG
    assert tag_set['name'] == INVALID_TAG_SET

    result = GuessDateResult(found=False, guess_method=None)
    assign_date_guess_tag(db, story, result, '2017-01-01')
    (tag, tag_set) = get_story_date_tag(db, story)

    assert tag is not None
    assert tag['tag'] == 'fallback_date'
    assert tag_set['name'] == GUESS_METHOD_TAG_SET
