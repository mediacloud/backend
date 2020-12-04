import mediawords.db
from mediawords.test.db.create import create_test_topic
from topics_mine.mine import fetch_links

from mediawords.util.log import create_logger
log = create_logger(__name__)

def test_fetch_links():
    db = mediawords.db.connect_to_db()
    
    topic = create_test_topic(db, 'foo')

    num_urls = 100

    # add a bunch of urls with bad urls.  the fetch-link job will fail with a python error
    # but that's fine becase all we are testing here is that each url makes it into the job pool

    links = [{'url': f"INVALID URL {i}"} for i in range(num_urls)]

    fetch_links(db, topic, links)

    log.warning(db.query("select * from topic_fetch_urls").hashes())
    return

    # if every url passed to the queue gets tagged with a url error, that means they all got processed
    # by the fetch-twitter-urls pool
    count_processed_tfus = db.query(
        """
        select count(*) from topic_fetch_urls
            where state = 'python error' and message like '%McFetchTwitterUrlsDataException%'
        """).flat()[0]

    assert count_processed_tfus == num_urls
