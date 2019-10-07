from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic, create_test_medium, create_test_feed, create_test_story

from topics_base.stories import add_to_topic_stories, find_and_merge_dup_stories


def test_find_and_merge_dup_stories():
    db = connect_to_db()

    topic = create_test_topic(db, 'dupstories')
    medium = create_test_medium(db, 'dupstories')
    feed = create_test_feed(db, 'dupstories', medium=medium)

    num_stories = 9
    for i in range(num_stories):
        story = create_test_story(db, "dupstories " + str(i), feed=feed)
        add_to_topic_stories(db, story, topic)
        modi = i % 3
        divi = i // 3
        if modi == 0:
            db.update_by_id('stories', story['stories_id'], {'title': 'TITLE ' + str(divi)})
        elif modi == 1:
            db.update_by_id('stories', story['stories_id'], {'title': 'title ' + str(divi)})
        else:
            db.update_by_id('stories', story['stories_id'], {'Title': 'title ' + str(divi)})

    find_and_merge_dup_stories(db, topic)

    num_topic_stories = db.query(
        "select count(*) from topic_stories where topics_id = %(a)s",
        {'a': topic['topics_id']}).flat()[0]

    assert num_topic_stories == 3

    num_distinct_titles = db.query(
        "select count(distinct normalized_title_hash) from snap.live_stories where topics_id = %(a)s",
        {'a': topic['topics_id']}).flat()[0]

    assert num_distinct_titles == 3
