from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium
from topics_base.stories import get_story_match


def test_get_story_match():
    """Test get_story_match()."""
    db = connect_to_db()

    medium = create_test_medium(db, 'foo')
    num_stories = 10
    stories = []
    for i in range(num_stories):
        story = db.create('stories', {
            'media_id': medium['media_id'],
            'url': ('http://stories-%d.com/foo/bar' % i),
            'guid': ('http://stories-%d.com/foo/bar/guid' % i),
            'title': ('story %d' % i),
            'publish_date': '2017-01-01'
        })
        stories.append(story)

    # None
    assert get_story_match(db, 'http://foo.com') is None

    # straight and normalized versions of url and redirect_url
    assert get_story_match(db, stories[0]['url']) == stories[0]
    assert get_story_match(db, 'http://foo.com', stories[1]['url']) == stories[1]
    assert get_story_match(db, stories[2]['url'] + '#foo') == stories[2]
    assert get_story_match(db, 'http://foo.com', stories[3]['url'] + '#foo') == stories[3]

    # get_preferred_story - return only story with sentences
    # noinspection SqlInsertValues
    db.query("""
        INSERT INTO story_sentences (
            stories_id,
            media_id,
            publish_date,
            sentence,
            sentence_number
        )
            SELECT
                stories_id,
                media_id,
                publish_date,
                'foo' AS sentence,
                1 AS sentence_number
            FROM stories
            WHERE stories_id = %(stories_id)s
    """, {
        'stories_id': stories[4]['stories_id']
    })
    # noinspection SqlWithoutWhere
    db.query("""
        WITH all_story_ids AS (
            SELECT stories_id
            FROM stories
        )
        UPDATE stories SET
            url = 'http://stories.com/'
        WHERE stories_id IN (
            SELECT stories_id
            FROM all_story_ids
        )
        RETURNING *
    """).hashes()

    assert get_story_match(db, 'http://stories.com/')['stories_id'] == stories[4]['stories_id']
