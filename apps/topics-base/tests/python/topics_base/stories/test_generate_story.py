from mediawords.db import connect_to_db
from mediawords.dbi.downloads.store import fetch_content
from mediawords.util.guess_date import GUESS_METHOD_TAG_SET
from .get_story_date_tag import get_story_date_tag
from topics_base.stories import generate_story, SPIDER_FEED_NAME


def test_generate_story():
    """Test generate_story()."""
    db = connect_to_db()

    story_content = '<title>foo bar</title><meta content="2016-01-12T03:55:46Z" itemprop="datePublished"/>'
    story_url = 'http://foo.com/foo/bar'
    story = generate_story(db=db, url=story_url, content=story_content)

    assert 'stories_id' in story
    assert story['title'] == 'foo bar'
    assert story['publish_date'] == '2016-01-12 03:55:46'
    assert story['url'] == story_url
    assert story['guid'] == story_url

    medium = db.require_by_id('media', story['media_id'])

    assert medium['name'] == 'foo.com'
    assert medium['url'] == 'http://foo.com/'

    feed = db.query(
        "select f.* from feeds f join feeds_stories_map fsm using ( feeds_id ) where stories_id = %(a)s",
        {'a': story['stories_id']}).hash()

    assert feed is not None
    assert feed['name'] == SPIDER_FEED_NAME

    (date_tag, date_tag_set) = get_story_date_tag(db, story)

    assert date_tag['tag'] == 'guess_by_tag_meta'
    assert date_tag_set['name'] == GUESS_METHOD_TAG_SET

    download = db.query("select * from downloads where stories_id = %(a)s", {'a': story['stories_id']}).hash()

    assert download is not None
    assert download['url'] == story['url']

    content = fetch_content(db, download)

    assert content == story_content

    story = generate_story(
        db=db,
        url='http://fallback.date',
        content='foo',
        fallback_date='2011-11-11',
    )

    assert story['publish_date'] == '2011-11-11 00:00:00'

    matched_story = generate_story(db, story['url'], 'foo')
    assert matched_story['stories_id'] == story['stories_id']

    story = generate_story(db=db, url='invalid url', content='foo')

    assert story is not None
