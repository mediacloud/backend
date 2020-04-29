import datetime
import re

from dateutil.relativedelta import relativedelta

from mediawords.db import connect_to_db
from mediawords.solr.query import get_full_solr_query_for_topic
from mediawords.test.db.create import create_test_story_stack_numerated, create_test_topic
from mediawords.util.log import create_logger

log = create_logger(__name__)


def test_get_full_solr_query_for_topic():
    """Test that get_full_solr_query_for_topic() returns the expected query."""
    db = connect_to_db()

    create_test_story_stack_numerated(db=db, num_media=10, num_feeds_per_medium=2, num_stories_per_feed=2)

    # Just need some randomly named tags, so copying media names works as well as anything
    db.query("INSERT INTO tag_sets (name) VALUES ('foo')")

    db.query("""
        INSERT INTO tags (tag, tag_sets_id)
            SELECT media.name, tag_sets_id
            FROM media, tag_sets
    """)

    topic = create_test_topic(db=db, label='Full Solr query')
    topics_id = topic['topics_id']

    db.query("""
        INSERT INTO topics_media_map (topics_id, media_id)
            SELECT %(topics_id)s, media_id
            FROM media
            LIMIT 5
    """, {'topics_id': topics_id})
    db.query("""
        INSERT INTO topics_media_tags_map (topics_id, tags_id)
            SELECT %(topics_id)s, tags_id
            FROM tags
            LIMIT 5
    """, {'topics_id': topics_id})

    # ---

    got_full_solr_query = get_full_solr_query_for_topic(db=db, topic=topic)

    q_matches = re.search(
        r'\( (.*) \) and \( media_id:\( ([\d\s]+) \) or tags_id_media:\( ([\d\s]+) \) \)',
        got_full_solr_query['q'],
    )
    assert q_matches, f"Full Solr query: 'q' matches expected pattern: {got_full_solr_query['q']}"
    query = q_matches.group(1)
    media_ids_list = q_matches.group(2)
    tags_ids_list = q_matches.group(3)

    fq_matches = re.search(
        r'publish_day:\[(\d\d\d\d-\d\d-\d\d)T00:00:00Z TO (\d\d\d\d-\d\d-\d\d)T23:59:59Z\]',
        got_full_solr_query['fq'],
    )
    assert fq_matches, f"Full Solr query: 'fq' matches expected pattern: {got_full_solr_query['fq']}"
    start_date = fq_matches.group(1)
    end_date = fq_matches.group(2)

    assert topic['solr_seed_query'] == query, "Full Solr query: solr_seed_query"

    assert topic['start_date'] == start_date, "Full Solr query: start_date"

    tp_start = datetime.datetime.strptime(topic['start_date'], '%Y-%m-%d')
    expected_end_date = (tp_start + relativedelta(months=1)).strftime('%Y-%m-%d')
    assert end_date == expected_end_date, "Full Solr query: end_date"

    got_media_ids_list = ','.join(sorted(media_ids_list.split(' ')))
    expected_media_ids = db.query("""
        SELECT media_id
        FROM topics_media_map
        WHERE topics_id = %(topics_id)s
    """, {'topics_id': topics_id}).flat()
    expected_media_ids_list = ','.join([str(_) for _ in sorted(expected_media_ids)])
    assert got_media_ids_list == expected_media_ids_list, "Full Solr query: media ids"

    got_tags_ids_list = ','.join([str(_) for _ in sorted(tags_ids_list.split(' '))])
    expected_tags_ids = db.query("""
        SELECT tags_id
        FROM topics_media_tags_map
        WHERE topics_id = %(topics_id)s
    """, {'topics_id': topics_id}).flat()
    expected_tags_ids_list = ','.join([str(_) for _ in sorted(expected_tags_ids)])
    assert got_tags_ids_list == expected_tags_ids_list, "Full Solr query: media ids"

    # ---

    offset_full_solr_query = get_full_solr_query_for_topic(
        db=db,
        topic=topic,
        media_ids=None,
        media_tags_ids=None,
        month_offset=1,
    )
    fq_matches = re.search(
        r'publish_day:\[(\d\d\d\d-\d\d-\d\d)T00:00:00Z TO (\d\d\d\d-\d\d-\d\d)T23:59:59Z\]',
        offset_full_solr_query['fq'],
    )
    assert fq_matches, f"Offset Solr query: matches expected pattern: {got_full_solr_query['fq']}"

    offset_start_date = fq_matches.group(1)
    offset_end_date = fq_matches.group(2)

    tp_start = datetime.datetime.strptime(topic['start_date'], '%Y-%m-%d') + relativedelta(months=1)
    expected_start_date = tp_start.strftime('%Y-%m-%d')
    assert offset_start_date == expected_start_date, "Offset Solr query: start_date"

    expected_end_date = (tp_start + relativedelta(months=1)).strftime('%Y-%m-%d')
    assert offset_end_date == expected_end_date, "Offset Solr query: end_date"

    # ---

    unset_full_solr_query = get_full_solr_query_for_topic(
        db=db,
        topic=topic,
        media_ids=None,
        media_tags_ids=None,
        month_offset=3,
    )
    assert unset_full_solr_query is None, "Solr query offset beyond end date is None"
