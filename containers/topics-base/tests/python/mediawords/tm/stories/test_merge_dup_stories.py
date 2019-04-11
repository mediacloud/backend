#!/usr/bin/env py.test

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic, create_test_medium, create_test_feed, create_test_story

# noinspection PyProtectedMember
from mediawords.tm.stories import add_to_topic_stories, _merge_dup_stories


def test_merge_dup_stories():
    """Test merge_dup_stories()."""
    db = connect_to_db()

    topic = create_test_topic(db, 'merge')
    medium = create_test_medium(db, 'merge')
    feed = create_test_feed(db, 'merge', medium=medium)

    num_stories = 10
    stories = []
    for i in range(num_stories):
        story = create_test_story(db, "merge " + str(i), feed=feed)
        add_to_topic_stories(db, story, topic)
        stories.append(story)
        for j in range(i):
            db.query(
                """
                insert into story_sentences (stories_id, sentence_number, sentence, media_id, publish_date)
                    select stories_id, %(b)s, 'foo bar', media_id, publish_date
                        from stories where stories_id = %(a)s
                """,
                {'a': story['stories_id'], 'b': j})

    _merge_dup_stories(db, topic, stories)

    stories_ids = [s['stories_id'] for s in stories]
    merged_stories = db.query(
        "select stories_id from topic_stories where topics_id = %(a)s and stories_id = any(%(b)s)",
        {'a': topic['topics_id'], 'b': stories_ids}).flat()

    assert merged_stories == [stories_ids[-1]]
