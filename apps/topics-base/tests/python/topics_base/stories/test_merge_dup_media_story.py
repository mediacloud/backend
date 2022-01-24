from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic, create_test_medium, create_test_feed, create_test_story

from topics_base.stories import merge_dup_media_story


def test_merge_dup_media_story():
    """Test merge_dup_media_story()."""
    db = connect_to_db()

    topic = create_test_topic(db, 'merge')
    medium = create_test_medium(db, 'merge')
    feed = create_test_feed(db, 'merge', medium=medium)
    old_story = create_test_story(db=db, label='merge old', feed=feed)

    new_medium = create_test_medium(db, 'merge new')

    db.update_by_id('media', medium['media_id'], {'dup_media_id': new_medium['media_id']})

    cloned_story = merge_dup_media_story(db, topic, old_story)

    for field in 'url guid publish_date title'.split():
        assert cloned_story[field] == old_story[field]

    topic_story = db.query("""
        SELECT *
        FROM topic_stories
        WHERE
            stories_id = %(stories_id)s AND
            topics_id = %(topics_id)s
    """, {
        'stories_id': cloned_story['stories_id'],
        'topics_id': topic['topics_id'],
    }).hash()
    assert topic_story is not None

    merged_story = merge_dup_media_story(db, topic, old_story)
    assert merged_story['stories_id'] == cloned_story['stories_id']
