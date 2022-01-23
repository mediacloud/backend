import mediawords.db
from mediawords.test.db.create import create_test_topic, create_test_topic_stories
import topics_mine.mine

from mediawords.util.log import create_logger
log = create_logger(__name__)

def test_fetch_links():
    db = mediawords.db.connect_to_db()
    
    num_urls = 100

    topic = create_test_topic(db, 'foo')
    create_test_topic_stories(db, topic, 1, num_urls);

    topics_mine.mine.EXTRACT_STORY_LINKS_CHUNK_SIZE = int(num_urls / 2) - 1

    topics_mine.mine.mine_topic_stories(db, topic)

    count_spidered_stories = db.query("select count(*) from topic_stories where link_mined").flat()[0]
    assert count_spidered_stories == num_urls
