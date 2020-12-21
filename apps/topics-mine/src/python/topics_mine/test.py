import mediawords.db
from mediawords.test.db.create import create_test_topic
from mediawords.test.solr import create_test_story_stack_for_indexing, setup_test_index
import topics_mine.mine

from mediawords.util.log import create_logger
log = create_logger(__name__)

def create_topic_for_import(db: mediawords.db.DatabaseHandler, num_stories : int = 200) -> dict:
    """create a test topic and stories for import into the topic.

    return the topic.
    """
    topic = create_test_topic(db, 'import')

    stack = {'medium_1': {'feed_1': [f"story_{_}" for _ in range(num_stories)]}}
    create_test_story_stack_for_indexing(db, stack)

    all_media = db.query("select * from media").hashes()
    all_stories = db.query("select * from stories").hashes()

    topic['start_date'] = '2020-01-01'
    topic['end_date'] = '2020-06-01'
    topic['solr_seed_query'] = '*:*'
    topic['solr_seed_query_run'] = False

    db.update_by_id('topics', topic['topics_id'], topic)

    for m in all_media:
        db.query(
            "insert into topics_media_map (topics_id, media_id) values (%(a)s, %(b)s)",
            {'a': topic['topics_id'], 'b': m['media_id']})

    # distribute one story each day.  this is kludgy but should work from a fresh databse with
    # sequential stories_ids.  assumes that there are more stories than days in the date range above
    stories = db.query("select * from stories").hashes()
    for (i, story) in enumerate(stories):
        db.query(
                """
                update stories set publish_date = %(a)s::timestamp + ((%(b)s || ' days')::interval)
                    where stories_id = %(c)s
                """,
                {'a': topic['start_date'], 'b': i, 'c': story['stories_id']})

    setup_test_index(db)

    return topic
