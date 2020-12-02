import mediawords.db
from mediawords.test.db.create import create_test_topic, create_test_topic_stories
from topics_mine.mine import generate_topic_links

from mediawords.util.log import create_logger
log = create_logger(__name__)

def test_generate_topic_links():
    db = mediawords.db.connect_to_db()

    num_stories = 100

    topic = create_test_topic(db, 'foo')
    create_test_topic_stories(db, topic, 1, num_stories)

    stories = db.query("select * from stories").hashes()

    num_topic_stories = db.query("select count(*) from topic_stories").flat()[0]
    assert num_topic_stories == num_stories

    db.query("update stories set description = 'http://foo.com/' || stories_id::text")

    generate_topic_links(db, topic, stories)

    num_unmined_stories = db.query("select count(*) from topic_stories where not link_mined").flat()[0]
    assert num_unmined_stories == 0

    num_mined_links = db.query("select count(*) from topic_links").flat()[0]
    assert num_mined_links == num_stories
