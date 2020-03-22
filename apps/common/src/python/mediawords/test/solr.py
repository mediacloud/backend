from typing import Dict, Any, List

from mediawords.db import DatabaseHandler
from mediawords.job import JobBroker
from mediawords.solr import query_solr
from mediawords.test.db.create import create_test_topic, create_test_story_stack, add_content_to_test_story_stack
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.tags import lookup_or_create_tag


def assert_story_query(db: DatabaseHandler,
                       q: str,
                       expected_story: Dict[str, Any],
                       label: str = 'test story query') -> None:
    """
    Run the given query against Solr, adding an 'and stories_id:{expected_story['stories_id']}' to make it return at
    most one story.

    Verify that the query succeeds and returns only the "expected_story".
    """
    q = decode_object_from_bytes_if_needed(q)
    expected_story = decode_object_from_bytes_if_needed(expected_story)
    label = decode_object_from_bytes_if_needed(label)

    expected_stories_id = expected_story['stories_id']

    r = query_solr(db=db, params={'q': f"{q} and stories_id:{expected_stories_id}", 'rows': 1_000_000})

    docs = r.get('response', {}).get('docs', None)

    assert docs, f"No response.docs found in Solr results: {docs}"

    got_stories_ids = [_['stories_id'] for _ in docs]

    assert [expected_stories_id] == got_stories_ids, f"{label}: {q}"


def _add_story_tags_to_stories(db: DatabaseHandler, stories: List[Dict[str, Any]]) -> None:
    """Add story tags to stories for Solr indexing."""
    stories = decode_object_from_bytes_if_needed(stories)

    tags = []
    num_tags = 5

    for i in range(1, num_tags + 1):
        tags.append(lookup_or_create_tag(db=db, tag_name=f"test:test_{i}"))

    for story in stories:
        assert isinstance(story, dict)
        tag = tags.pop()
        tags.insert(0, tag)
        db.query("""
            INSERT INTO stories_tags_map (stories_id, tags_id)
            VALUES (%(stories_id)s, %(tags_id)s)
        """, {
            'stories_id': story['stories_id'],
            'tags_id': tag['tags_id'],
        })


def _add_timespans_to_stories(db: DatabaseHandler, stories: List[Dict[str, Any]]) -> None:
    """Add timespans to stories for solr indexing."""
    stories = decode_object_from_bytes_if_needed(stories)

    topic = create_test_topic(db=db, label="solr dump test")

    snapshot = db.create(table='snapshots', insert_hash={
        'topics_id': topic['topics_id'],
        'snapshot_date': '2018-01-01',
        'start_date': '2018-01-01',
        'end_date': '2018-01-01',
    })

    timespans = []
    for i in range(1, 5 + 1):
        timespan = db.create(table='timespans', insert_hash={
            'snapshots_id': snapshot['snapshots_id'],
            'start_date': '2018-01-01',
            'end_date': '2018-01-01',
            'story_count': 1,
            'story_link_count': 1,
            'medium_count': 1,
            'medium_link_count': 1,
            'post_count': 1,
            'period': 'overall',
        })
        timespans.append(timespan)

    for story in stories:
        assert isinstance(story, dict)

        timespan = timespans.pop()
        timespans.insert(0, timespan)

        db.query("""
            insert into snap.story_link_counts (
                timespans_id,
                stories_id,
                media_inlink_count,
                inlink_count,
                outlink_count
            ) values (
                %(timespans_id)s,
                %(stories_id)s,
                1,
                1,
                1
            )
        """, {
            'timespans_id': timespan['timespans_id'],
            'stories_id': story['stories_id'],
        })


def queue_all_stories(db: DatabaseHandler, stories_queue_table: str = 'solr_import_stories') -> None:
    stories_queue_table = decode_object_from_bytes_if_needed(stories_queue_table)

    db.begin()

    db.query(f"TRUNCATE TABLE {stories_queue_table}")

    # "SELECT FROM processed_stories" because only processed stories should get imported. "ORDER BY" so that the
    # import is more efficient when pulling blocks of stories out.
    db.query(f"""
        INSERT INTO {stories_queue_table}
            SELECT stories_id
            FROM processed_stories
            GROUP BY stories_id
            ORDER BY stories_id
    """)

    db.commit()


def setup_test_index(db: DatabaseHandler) -> None:
    """
    Run a full Solr import based on the current PostgreSQL database.

    Due to a failsafe built into generate_and_import_data(), the delete of the collection data will fail if there are
    more than 100 million sentences in the index (to prevent accidental deletion of production data).
    """

    queue_all_stories(db)

    JobBroker(queue_name='MediaWords::Job::ImportSolrDataForTesting').run_remotely(full=True, throttle=False)


def create_test_story_stack_for_indexing(db: DatabaseHandler, data: dict) -> dict:
    data = decode_object_from_bytes_if_needed(data)

    story_stack = create_test_story_stack(db=db, data=data)

    media = add_content_to_test_story_stack(db=db, story_stack=story_stack)

    test_stories = db.query("SELECT * FROM stories ORDER BY md5(stories_id::text)").hashes()

    # Add ancillary data so that it can be queried in Solr
    _add_story_tags_to_stories(db=db, stories=test_stories)
    _add_timespans_to_stories(db=db, stories=test_stories)

    return media


def create_indexed_test_story_stack(db: DatabaseHandler, data: dict) -> dict:
    """
    Create a test story stack, add content to the stories, and index them.

    The stories will have associated "timespans_id", "stories_tags_map", and "processed_stories" entries added as well.

    Returns the test story stack as returned by create_test_story_stack().
    """
    data = decode_object_from_bytes_if_needed(data)

    media = create_test_story_stack_for_indexing(db=db, data=data)

    setup_test_index(db=db)

    return media
