import re2

from mediawords.db import DatabaseHandler
from mediawords.db.exceptions.result import McDatabaseResultException


def content_matches_topic(content: str, topic: dict, assume_match: bool = False) -> bool:
    """Test whether the content matches the topic['pattern'] regex.

    Only check the first megabyte of the string to avoid the occasional very long regex check.

    Arguments:
    content - text content
    topic - topic dict from db
    assume_match - assume that the content matches

    Return:
    True if the content matches the topic pattern

    """
    if assume_match:
        return True

    if content is None:
        return False

    content = content[0:1024 * 1024]

    # for some reason I can't reproduce in dev, in production a small number of fields come from
    # the database into the stories fields or the text value produced in the query below in _story_matches_topic
    # as bytes objects, which re2.search chokes on
    if isinstance(content, bytes):
        content = content.decode('utf8', 'backslashreplace')

    r = re2.search(topic['pattern'], content, re2.I | re2.X | re2.S) is not None

    return r


def try_update_topic_link_ref_stories_id(db: DatabaseHandler, topic_fetch_url: dict) -> None:
    """Update the given topic link to point to the given ref_stories_id.

    Use the topic_fetch_url['topic_links_id'] as the id of the topic link to update and the
    topic_fetch_url['stories_id'] as the ref_stories_id.

    There is a unique constraint on topic_links(topics_id, stories_id, ref_stories_id).  This function just does the
    update to topic_links and catches and ignores any errors from that constraint.  Trying and failing on the
    constraint is faster and more reliable than checking before trying (and still maybe failing on the constraint).
    """
    if topic_fetch_url.get('topic_links_id', None) is None:
        return

    try:
        db.query("""
            UPDATE topic_links SET
                ref_stories_id = %(ref_stories_id)s
            WHERE
                topics_id = %(topics_id)s AND
                topic_links_id = %(topic_links_id)s
        """, {
            'topics_id': topic_fetch_url['topics_id'],
            'ref_stories_id': topic_fetch_url['stories_id'],
            'topic_links_id': topic_fetch_url['topic_links_id'],
        })
    except McDatabaseResultException as e:
        # the query will throw a unique constraint error if stories_id,ref_stories already exists.  it's quicker
        # to just catch and ignore the error than to try to avoid id
        if 'unique constraint "topic_links_stories_id_topics_id_ref_stories_id"' not in str(e):
            raise e
