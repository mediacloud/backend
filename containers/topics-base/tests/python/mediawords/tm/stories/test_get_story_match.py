from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium

from mediawords.tm.stories import get_story_match


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
    db.query(
        """
        insert into story_sentences ( stories_id, media_id, publish_date, sentence, sentence_number )
            select stories_id, media_id, publish_date, 'foo', 1 from stories where stories_id = %(a)s
        """,
        {'a': stories[4]['stories_id']})
    # noinspection SqlWithoutWhere
    stories = db.query("update stories set url = 'http://stories.com/' returning *").hashes()

    assert get_story_match(db, 'http://stories.com/') == stories[4]
