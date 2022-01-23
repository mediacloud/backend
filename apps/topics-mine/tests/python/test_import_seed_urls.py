import mediawords.db
from mediawords.test.db.create import create_test_topic
import topics_mine.mine

from mediawords.util.log import create_logger
log = create_logger(__name__)

def test_fetch_links():
    db = mediawords.db.connect_to_db()
    
    num_urls = 100

    topic = create_test_topic(db, 'foo')

    for i in range(num_urls):
        tsu = {
            'topics_id': topic['topics_id'],
            'processed': 'false',
            'url': f'INVALID URL {i}'}
        db.create('topic_seed_urls', tsu)

    topics_mine.mine.ADD_NEW_LINKS_CHUNK_SIZE = int(num_urls / 2) - 1
    topics_mine.mine.import_seed_urls(db, topic, None)

    count_processed_tfus = db.query("select count(*) from topic_fetch_urls where state = 'request failed'").flat()[0]
    assert count_processed_tfus == num_urls

    count_processed_urls = db.query("select count(*) from topic_seed_urls where processed").flat()[0]
    assert count_processed_urls == num_urls
