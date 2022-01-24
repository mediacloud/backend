from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic, create_test_medium, create_test_feed, create_test_story

# noinspection PyProtectedMember
from topics_base.stories import add_to_topic_stories, _merge_dup_story


def test_merge_dup_story():
    """Test _merge_dup_story()."""
    db = connect_to_db()

    topic = create_test_topic(db, 'merge')
    medium = create_test_medium(db, 'merge')
    feed = create_test_feed(db, 'merge', medium=medium)

    old_story = create_test_story(db=db, label='merge old', feed=feed)
    new_story = create_test_story(db=db, label='merge new', feed=feed)

    linked_story = create_test_story(db=db, label='linked', feed=feed)
    linking_story = create_test_story(db=db, label='linking', feed=feed)

    for story in (old_story, new_story, linked_story, linking_story):
        add_to_topic_stories(db, story, topic)

    db.create('topic_links', {
        'topics_id': topic['topics_id'],
        'stories_id': old_story['stories_id'],
        'url': old_story['url'],
        'ref_stories_id': linked_story['stories_id'],
    })
    db.create('topic_links', {
        'topics_id': topic['topics_id'],
        'stories_id': linking_story['stories_id'],
        'url': old_story['url'],
        'ref_stories_id': old_story['stories_id'],
    })
    db.create('topic_seed_urls', {
        'topics_id': topic['topics_id'],
        'stories_id': old_story['stories_id'],
    })

    _merge_dup_story(db, topic, old_story, new_story)

    old_topic_links = db.query("""
        SELECT *
        FROM topic_links
        WHERE
            topics_id = %(topics_id)s AND
            %(stories_id)s IN (stories_id, ref_stories_id)
    """, {
        'topics_id': topic['topics_id'],
        'stories_id': old_story['stories_id'],
    }).hashes()
    assert len(old_topic_links) == 0

    new_topic_links_linked = db.query("""
        SELECT *
        FROM topic_links
        WHERE
            topics_id = %(topics_id)s AND
            stories_id = %(stories_id)s AND
            ref_stories_id = %(ref_stories_id)s
    """, {
        'topics_id': topic['topics_id'],
        'stories_id': new_story['stories_id'],
        'ref_stories_id': linked_story['stories_id'],
    }).hashes()
    assert len(new_topic_links_linked) == 1

    new_topic_links_linking = db.query("""
        SELECT *
        FROM topic_links
        WHERE
            topics_id = %(topics_id)s AND
            ref_stories_id = %(ref_stories_id)s AND
            stories_id = %(stories_id)s
    """, {
        'topics_id': topic['topics_id'],
        'ref_stories_id': new_story['stories_id'],
        'stories_id': linking_story['stories_id'],
    }).hashes()
    assert len(new_topic_links_linking) == 1

    old_topic_stories = db.query("""
        SELECT *
        FROM topic_stories
        WHERE
            topics_id = %(topics_id)s AND
            stories_id = %(stories_id)s
    """, {
        'topics_id': topic['topics_id'],
        'stories_id': old_story['stories_id'],
    }).hashes()
    assert len(old_topic_stories) == 0

    topic_merged_stories_maps = db.query("""
        SELECT *
        FROM topic_merged_stories_map
        WHERE
            target_stories_id = %(target_stories_id)s AND
            source_stories_id = %(source_stories_id)s
    """, {
        'target_stories_id': new_story['stories_id'],
        'source_stories_id': old_story['stories_id'],
    }).hashes()
    assert len(topic_merged_stories_maps) == 1
