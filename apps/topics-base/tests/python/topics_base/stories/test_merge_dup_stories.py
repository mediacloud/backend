from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic, create_test_medium, create_test_feed, create_test_story

# noinspection PyProtectedMember
from topics_base.stories import add_to_topic_stories, _merge_dup_stories


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
            # noinspection SqlInsertValues
            db.query("""
                INSERT INTO story_sentences (
                    stories_id,
                    sentence_number,
                    sentence,
                    media_id,
                    publish_date
                )
                    SELECT
                        stories_id,
                        %(sentence_number)s AS sentence_number,
                        'foo bar' AS sentence,
                        media_id,
                        publish_date
                    FROM stories
                    WHERE stories_id = %(stories_id)s
            """, {
                'stories_id': story['stories_id'],
                'sentence_number': j,
            })

    _merge_dup_stories(db, topic, stories)

    stories_ids = [s['stories_id'] for s in stories]
    merged_stories = db.query("""
        SELECT stories_id
        FROM topic_stories
        WHERE
            topics_id = %(topics_id)s AND
            stories_id = ANY(%(stories_ids)s)
    """, {
        'topics_id': topic['topics_id'],
        'stories_ids': stories_ids,
    }).flat()

    assert merged_stories == [stories_ids[-1]]
