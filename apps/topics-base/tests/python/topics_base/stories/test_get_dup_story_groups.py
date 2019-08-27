from mediawords.db import connect_to_db
from mediawords.test.db.create import (
    create_test_topic,
    create_test_medium,
    create_test_feed,
    create_test_story,
)

# noinspection PyProtectedMember
from topics_base.stories import add_to_topic_stories, _get_dup_story_groups


def test_get_dup_story_groups():
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

    dup_story_groups = _get_dup_story_groups(db, topic)

    assert len(dup_story_groups) == 3

    for dsg in dup_story_groups:
        for story in dsg:
            assert dsg[0]['title'].lower() == story['title'].lower()
