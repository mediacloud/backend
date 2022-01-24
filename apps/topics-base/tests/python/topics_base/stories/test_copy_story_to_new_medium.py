from mediawords.db import connect_to_db
from mediawords.dbi.downloads.store import fetch_content
from mediawords.test.db.create import (
    create_test_topic,
    create_test_medium,
    create_test_feed,
    create_test_story,
    add_content_to_test_story,
)
from topics_base.stories import add_to_topic_stories, copy_story_to_new_medium


def test_copy_story_to_new_medium():
    """Test copy_story_to_new_medium."""
    db = connect_to_db()

    topic = create_test_topic(db, 'copy foo')

    new_medium = create_test_medium(db, 'copy new')

    old_medium = create_test_medium(db, 'copy old')
    old_feed = create_test_feed(db=db, label='copy old', medium=old_medium)
    old_story = create_test_story(db=db, label='copy old', feed=old_feed)

    add_content_to_test_story(db, old_story, old_feed)

    add_to_topic_stories(db, old_story, topic)

    new_story = copy_story_to_new_medium(db, topic, old_story, new_medium)

    assert db.find_by_id('stories', new_story['stories_id']) is not None

    for field in 'title url guid publish_date'.split():
        assert old_story[field] == new_story[field]

    topic_story_exists = db.query("""
        SELECT *
        FROM topic_stories
        WHERE
            topics_id = %(topics_id)s AND
            stories_id = %(stories_id)s
    """, {
        'topics_id': topic['topics_id'],
        'stories_id': new_story['stories_id'],
    }).hash()
    assert topic_story_exists is not None

    new_download = db.query("""
        SELECT *
        FROM downloads
        WHERE stories_id = %(stories_id)s
    """, {
        'stories_id': new_story['stories_id'],
    }).hash()
    assert new_download is not None

    content = fetch_content(db, new_download)
    assert content is not None and len(content) > 0

    story_sentences = db.query("""
        SELECT *
        FROM story_sentences
        WHERE stories_id = %(stories_id)s
    """, {
        'stories_id': new_story['stories_id'],
    }).hashes()
    assert len(story_sentences) > 0
