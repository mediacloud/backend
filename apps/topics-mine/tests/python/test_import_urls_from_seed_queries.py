import csv
import io

import mediawords.db
from mediawords.test.db.create import create_test_topic, create_test_topic_stories
import topics_mine.mine

from mediawords.util.log import create_logger
log = create_logger(__name__)

def test_import_urls_from_seed_queries():
    db = mediawords.db.connect_to_db()

    num_stories = 100

    topic = create_test_topic(db, 'foo')
    topic['pattern'] = '.*'
    topic = db.update_by_id('topics', topic['topics_id'], topic)
    
    date = topic['start_date']

    posts = [{'author': i, 'publish_date': date, 'content': f'http://u.u/{i}'} for i in range(num_stories)]

    csv_io = io.StringIO()
    csv_writer = csv.DictWriter(csv_io, fieldnames=posts[0].keys())
    csv_writer.writeheader()
    [csv_writer.writerow(p) for p in posts]

    seed_csv = csv_io.getvalue()

    tsq = {
        'topics_id': topic['topics_id'],
        'source': 'csv',
        'platform': 'generic_post',
        'query': seed_csv
    }
    tsq = db.create('topic_seed_queries', tsq)

    topics_mine.mine.import_urls_from_seed_queries(db, topic, None)

    num_tsus = db.query("select count(distinct url) from topic_seed_urls").flat()[0]

    assert num_tsus == num_stories
