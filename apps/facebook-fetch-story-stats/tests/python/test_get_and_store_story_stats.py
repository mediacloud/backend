import pytest
from facebook_fetch_story_stats.exceptions import McFacebookSoftFailureException
from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_story_stack

from facebook_fetch_story_stats import get_and_store_story_stats


def test_get_and_store_story_stats():
    db = connect_to_db()

    media = create_test_story_stack(db=db, data={'A': {'B': [1, 2, 3]}})
    story = media['A']['feeds']['B']['stories']['1']

    story['url'] = 'http://google.com'
    returned_stats = get_and_store_story_stats(db=db, story=story)

    stored_stats = db.query("""
        SELECT *
        FROM story_statistics
        WHERE stories_id = %(stories_id)s
    """, {'stories_id': story['stories_id']}).hash()

    assert stored_stats, "story_statistics row exists after initial insert."

    assert stored_stats.get('facebook_share_count', None) == returned_stats.share_count, "Share count."
    assert stored_stats.get('facebook_comment_count', None) == returned_stats.comment_count, "Comment count."
    assert stored_stats.get('facebook_reaction_count', None) == returned_stats.reaction_count, "Reaction count."
    assert stored_stats.get('facebook_api_error', None) is None, "Null URL share count error."

    story['url'] = 'boguschema://foobar'

    with pytest.raises(McFacebookSoftFailureException):
        get_and_store_story_stats(db=db, story=story)

    stored_stats = db.query("""
        SELECT *
        FROM story_statistics
        WHERE stories_id = %(stories_id)s
    """, {'stories_id': story['stories_id']}).hash()

    assert stored_stats, "story_statistics row exists after initial insert."

    assert stored_stats.get('facebook_share_count', None) is None, "Share count should be unset after error."
    assert stored_stats.get('facebook_comment_count', None) is None, "Comment count should be unset after error."
    assert stored_stats.get('facebook_reaction_count', None) is None, "Reaction count should be unset after error."
    assert stored_stats.get('facebook_api_error', None) is not None, "Facebook should have reported an error."
