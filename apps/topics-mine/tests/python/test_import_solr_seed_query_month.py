import mediawords.db
from mediawords.test.db.create import create_test_topic
from mediawords.test.solr import create_test_story_stack_for_indexing, setup_test_index
import topics_mine.mine
import topics_mine.test

from mediawords.util.log import create_logger
log = create_logger(__name__)

def test_import_solr_seed_query_month():
    db = mediawords.db.connect_to_db()
    num_stories = 200

    topic = topics_mine.test.create_topic_for_import(db=db, num_stories=num_stories)

    i = 0
    while topics_mine.mine.import_solr_seed_query_month(db, topic, i):
        date_stories = db.query(
            """
            select * from stories
                where
                    publish_date >= %(a)s::timestamp + ((%(b)s || ' months')::interval) and
                    publish_date <= %(a)s::timestamp + ((%(c)s || ' months')::interval) and
                    publish_date <= %(d)s
            """,
            {'a': topic['start_date'], 'b': i, 'c': i + 1, 'd': topic['end_date']}).hashes()

        date_stories_urls = [s['url'] for s in date_stories]

        count_topic_seed_urls = db.query(
            "select count(distinct url) from topic_seed_urls where url = any(%(a)s)",
            {'a': date_stories_urls}).flat()[0]

        assert len(date_stories) > 0, f"offset {i}"
        assert len(date_stories) == count_topic_seed_urls, f"topic seed urls for month offset {i}"

        i += 1

        

