from operator import itemgetter

from mediawords.db import connect_to_db
from mediawords.dbi.downloads.store import store_content
from mediawords.test.db.create import create_test_topic, create_test_medium, create_test_feed, create_test_story

from topics_base.stories import merge_foreign_rss_stories


def test_merge_foreign_rss_stories():
    """Test merge_foreign_rss_stories()."""
    db = connect_to_db()

    topic = create_test_topic(db, 'foo')

    medium = create_test_medium(db, 'norss')
    feed = create_test_feed(db=db, label='norss', medium=medium)
    num_stories = 10
    stories = [
        create_test_story(db=db, label=str(i), feed=feed)
        for i in range(num_stories)
    ]

    rss_medium = create_test_medium(db, 'rss')
    rss_medium = db.query(
        "update media set foreign_rss_links = 't' where media_id = %(a)s returning *",
        {'a': rss_medium['media_id']}).hash()
    rss_feed = create_test_feed(db=db, label='rss', medium=rss_medium)
    num_rss_stories = 10
    rss_stories = []
    for i in range(num_rss_stories):
        story = create_test_story(db=db, label=str(i), feed=rss_feed)
        download = db.create('downloads', {
            'stories_id': story['stories_id'],
            'feeds_id': rss_feed['feeds_id'],
            'url': story['url'],
            'host': 'foo',
            'type': 'content',
            'state': 'success',
            'priority': 0,
            'sequence': 0,
            'path': 'postgresql'})
        store_content(db, download, story['title'])
        rss_stories.append(story)

    db.query(
        "insert into topic_stories (stories_id, topics_id) select s.stories_id, %(a)s from stories s",
        {'a': topic['topics_id']})

    assert db.query("select count(*) from topic_stories").flat()[0] == num_stories + num_rss_stories

    merge_foreign_rss_stories(db, topic)

    assert db.query("select count(*) from topic_stories").flat()[0] == num_stories
    assert db.query("select count(*) from topic_seed_urls").flat()[0] == num_rss_stories

    got_topic_stories_ids = db.query("select stories_id from topic_stories").flat()
    expected_topic_stories_ids = [s['stories_id'] for s in stories]
    assert sorted(got_topic_stories_ids) == sorted(expected_topic_stories_ids)

    got_seed_urls = db.query(
        "select topics_id, url, content from topic_seed_urls where topics_id = %(a)s",
        {'a': topic['topics_id']}).hashes()
    expected_seed_urls = \
        [{'url': s['url'], 'topics_id': topic['topics_id'], 'content': s['title']} for s in rss_stories]

    assert sorted(got_seed_urls, key=itemgetter('url')) == sorted(expected_seed_urls, key=itemgetter('url'))
