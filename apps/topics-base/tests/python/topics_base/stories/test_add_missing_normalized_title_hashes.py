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
    null_count = db.query("""
        WITH topic_story_ids AS (
            SELECT stories_id
            FROM topic_stories
            WHERE topics_id = %(topics_id)s
        )
        SELECT COUNT(*)
        FROM stories
        WHERE
            normalized_title_hash IS NULL AND
            stories_id IN (
                SELECT stories_id
                FROM topic_story_ids
            )
    """, {
        'topics_id': topic['topics_id'],
    }).flat()[0]

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
    db.query(
        "SELECT run_command_on_shards('stories', %(command)s)",
        {
            'command': """
                -- noinspection SqlResolveForFile @ trigger/"stories_add_normalized_title"
                BEGIN;
                LOCK TABLE pg_proc IN ACCESS EXCLUSIVE MODE;
                ALTER TABLE %s DISABLE TRIGGER stories_add_normalized_title;
                COMMIT;
            """,
        }
    )

    db.query("""
        WITH all_story_ids AS (
            SELECT stories_id
            FROM stories
        )
        UPDATE stories SET
            normalized_title_hash = NULL
        WHERE stories_id IN (
            SELECT stories_id
            FROM all_story_ids
        )
    """)

    db.query(
        "SELECT run_command_on_shards('stories', %(command)s)",
        {
            'command': """
                -- noinspection SqlResolveForFile @ trigger/"stories_add_normalized_title"
                BEGIN;
                LOCK TABLE pg_proc IN ACCESS EXCLUSIVE MODE;
                ALTER TABLE %s ENABLE TRIGGER stories_add_normalized_title;
                COMMIT;
            """,
        }
    )

    assert __count_null_title_stories(db=db, topic=topic) == num_stories

    _add_missing_normalized_title_hashes(db, topic)

    assert __count_null_title_stories(db=db, topic=topic) == 0
