import mediawords.db
from mediawords.test.db.create import create_test_topic
from topics_mine.mine import _fetch_twitter_urls

from mediawords.util.log import create_logger
log = create_logger(__name__)

def test_fetch_twitter_urls():
    db = mediawords.db.connect_to_db()
    
    topic = create_test_topic(db, 'foo')

    num_urls = 100

    # add a bunch of urls with non-twitter urls.  the fetch-twitter-urls job will fail with a python error
    # when the urls cannot be parsed for twitter statuses, but that's fine becase all we are testing here
    # is that each url makes it into the fetch_twitter_url job pool

    tfus = []
    for i in range(num_urls):
        tfu = {
            'topics_id': topic['topics_id'],
            'url': 'http://not.a.twitter.url',
            'state':  'tweet pending'
        }
        tfu = db.create("topic_fetch_urls", tfu)

        tfus.append(tfu)

    tfu_ids = [tfu['topic_fetch_urls_id'] for tfu in tfus]

    _fetch_twitter_urls(db, topic, tfu_ids)

    # if every url passed to the queue gets tagged with a url error, that means they all got processed
    # by the fetch-twitter-urls pool
    count_processed_tfus = db.query(
        """
        select count(*) from topic_fetch_urls
            where state = 'python error' and message like '%McFetchTwitterUrlsDataException%'
        """).flat()[0]

    assert count_processed_tfus == num_urls
