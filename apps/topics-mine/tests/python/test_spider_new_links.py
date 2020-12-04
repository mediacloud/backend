import mediawords.db
from mediawords.test.db.create import create_test_topic, create_test_topic_stories
import topics_mine.mine

from mediawords.util.log import create_logger
log = create_logger(__name__)

def test_fetch_links():
    db = mediawords.db.connect_to_db()
    
    num_urls = 10

    topic = create_test_topic(db, 'foo')
    create_test_topic_stories(db, topic, 1, num_urls);

    # add a bunch of urls with bad urls.  the fetch-link job will fail with a python error
    # but that's fine becase all we are testing here is that each url makes it into the job pool
    db.query("delete from topic_links")
    links = db.query(
        """
        insert into topic_links (topics_id, stories_id, url)
            select topics_id, stories_id, 'U ' || stories_id::text from topic_stories
            returning *
        """).hashes()

    topics_mine.mine.spider_new_links(db, topic, 1, None)

    count_processed_tfus = db.query("select count(*) from topic_fetch_urls where state = 'request failed'").flat()[0]
    assert count_processed_tfus == num_urls

    count_spidered_links = db.query("select count(*) from topic_links where link_spidered").flat()[0]
    assert count_spidered_links == num_urls
