#!/usr/bin/env py.test

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic, create_test_medium, create_test_feed, create_test_story

from mediawords.tm.stories import add_to_topic_stories, merge_dup_media_stories


def test_merge_dup_media_stories():
    """Test merge_dup_media_stories()."""
    db = connect_to_db()

    topic = create_test_topic(db, 'merge')
    old_medium = create_test_medium(db, 'merge from')
    new_medium = create_test_medium(db, 'merge to')
    feed = create_test_feed(db, 'merge', medium=old_medium)

    num_stories = 10
    for i in range(num_stories):
        story = create_test_story(db, "merge " + str(i), feed=feed)
        add_to_topic_stories(db, story, topic)

    db.update_by_id('media', old_medium['media_id'], {'dup_media_id': new_medium['media_id']})

    merge_dup_media_stories(db, topic)

    got_stories = db.query(
        "select s.* from stories s join topic_stories ts using (stories_id) where topics_id = %(a)s",
        {'a': topic['topics_id']}).hashes()

    assert len(got_stories) == num_stories

    for got_story in got_stories:
        assert got_story['media_id'] == new_medium['media_id']
