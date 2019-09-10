import time

from mediawords.db import connect_to_db

from mediawords.util.log import create_logger

from crawler_ap.ap import add_new_stories, AP_MEDIUM_NAME

log = create_logger(__name__)


def _mock_get_new_stories():
    """Simple mock to return stories in the form returned by ap.get_new_stories()"""
    stories = []
    for i in range(10):
        story = {
            'url': "https://hosted.ap.org/story/%d" % i,
            'guid': "https://hosted.ap.org/guid/%d" % i,
            'title': "AP Story Title %d" % i,
            'description': "AP Story Description %d" % i,
            'publish_date': '2018-01-01 00:00:00',
            'text': "here is some ap story text for story %d" % i,
            'content': "<xml><body>here is some ap story text for story %d" % i
        }
        stories.append(story)

    return stories


def test_add_new_stories():
    db = connect_to_db()

    db.create('media', {'url': 'ap.com', 'name': AP_MEDIUM_NAME})

    ap_stories = _mock_get_new_stories()

    add_new_stories(db=db, new_stories=ap_stories)

    stories = db.query("select * from stories").hashes()
    assert len(stories) == len(ap_stories)

    story_sentences = []

    # It's extract-and-vector worker that's doing the extraction, so wait for a minute for all of the expected sentences
    # to show up
    for retry in range(60):
        story_sentences = db.query("select * from story_sentences").hashes()
        if len(story_sentences) == len(ap_stories):
            log.info("All stories got extracted, continuing")
            break
        else:
            log.warning("All stories still didn't get extracted, waiting some more...")
            time.sleep(1)

    assert len(story_sentences) == len(ap_stories)

    for ap_story in ap_stories:
        got_story = db.query("select * from stories where title = %(a)s", {'a': ap_story['title']}).hash()
        assert got_story
        for field in ['url', 'guid', 'description', 'publish_date']:
            assert got_story[field] == ap_story[field]

    # try to add the same stories
    add_new_stories(db=db, new_stories=ap_stories)

    # should be same number of stories, since these new ones are dups
    stories = db.query("select * from stories").hashes()
    assert len(stories) == len(ap_stories)
