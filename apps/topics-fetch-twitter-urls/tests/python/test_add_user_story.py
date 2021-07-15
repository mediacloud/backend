from mediawords.db import connect_to_db
from mediawords.dbi.downloads.store import get_content_for_first_download
from mediawords.test.db.create import create_test_topic, create_test_medium, create_test_feed, create_test_story

# noinspection PyProtectedMember
from topics_fetch_twitter_urls.fetch_twitter_urls import _add_user_story


def test_add_user_story():
    """Test _add_user_story()."""
    db = connect_to_db()

    topic = create_test_topic(db, 'test')
    medium = create_test_medium(db, 'test')
    feed = create_test_feed(db, 'test', medium)
    source_story = create_test_story(db, 'source', feed)

    topics_id = topic['topics_id']

    db.create('topic_stories', {'topics_id': topics_id, 'stories_id': source_story['stories_id']})

    topic_link = db.create(
        'topic_links',
        {
            'topics_id': topics_id,
            'url': 'u',
            'stories_id': source_story['stories_id'],
        }
    )

    tfu = db.create(
        'topic_fetch_urls',
        {
            'topics_id': topics_id,
            'url': 'u',
            'state': 'pending',
            'topic_links_id': topic_link['topic_links_id'],
        }
    )

    user = {
        'id': 123,
        'screen_name': 'test_screen_name',
        'name': 'test screen name',
        'description': 'test user description'
    }

    story = _add_user_story(db, topic, user, [tfu])

    got_story = db.require_by_id('stories', story['stories_id'])

    assert got_story['title'] == f"{user['name']} ({user['screen_name']}) | Twitter"
    assert got_story['url'] == f"https://twitter.com/{user['screen_name']}"

    got_topic_link = db.require_by_id('topic_links', topic_link['topic_links_id'])
    assert got_topic_link['ref_stories_id'] == story['stories_id']

    content = f"{user['name']} ({user['screen_name']}): {user['description']}"
    assert get_content_for_first_download(db, story) == content

    got_topic_story = db.query("""
        SELECT *
        FROM topic_stories
        WHERE
            stories_id = %(stories_id)s AND
            topics_id = %(topics_id)s
    """, {
        'stories_id': story['stories_id'],
        'topics_id': topic['topics_id'],
    }).hash()
    assert got_topic_story is not None
    assert got_topic_story['link_mined']

    got_undateable_tag = db.query("""
        SELECT *
        FROM stories_tags_map AS stm
            INNER JOIN tags AS t USING (tags_id)
            INNER JOIN tag_sets USING (tag_sets_id)
        WHERE
            stories_id = %(stories_id)s AND
            tag = 'undateable' AND
            name = 'date_invalid'
    """, {
        'stories_id': got_story['stories_id']
    }).hash()

    assert got_undateable_tag
