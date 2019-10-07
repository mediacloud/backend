from mediawords.db import connect_to_db, DatabaseHandler
from mediawords.test.db.create import (
    create_test_topic,
    create_test_medium,
    create_test_feed,
    create_test_story,
)

# noinspection PyProtectedMember
from topics_base.stories import add_to_topic_stories, _add_missing_normalized_title_hashes


def __count_null_title_stories(db: DatabaseHandler, topic: dict) -> int:
    """Count the stories in the topic with a null normalized_title_hash."""
    null_count = db.query(
        """
        select count(*)
            from stories s
                join topic_stories ts using ( stories_id )
            where
                ts.topics_id = %(a)s and
                s.normalized_title_hash is null
        """,
        {'a': topic['topics_id']}).flat()[0]

    return null_count


def test_add_missing_normalized_title_hashes():
    db = connect_to_db()

    topic = create_test_topic(db, 'titles')
    medium = create_test_medium(db, 'titles')
    feed = create_test_feed(db, 'titles', medium=medium)

    num_stories = 10
    for i in range(num_stories):
        story = create_test_story(db, "titles " + str(i), feed=feed)
        add_to_topic_stories(db, story, topic)

    # disable trigger so that we can actually set normalized_title_hash to null
    db.query("alter table stories disable trigger stories_add_normalized_title")
    # noinspection SqlWithoutWhere
    db.query("update stories set normalized_title_hash = null")
    db.query("alter table stories enable trigger stories_add_normalized_title")

    assert __count_null_title_stories(db=db, topic=topic) == num_stories

    _add_missing_normalized_title_hashes(db, topic)

    assert __count_null_title_stories(db=db, topic=topic) == 0
