"""
Functions for parsing Solr queries.
"""

import datetime
import re
from typing import Dict, Any, Optional, List

from dateutil.relativedelta import relativedelta

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


def __get_solr_query_month_clause(topic: Dict[str, Any], month_offset: int) -> Optional[str]:
    """
    For the given topic, get a Solr 'publish_date' clause that will return one month of the seed query, starting at
    'start_date' and offset by 'month_offset' months.

    Return None if 'month_offset' puts the start date past the topic start date.
    """
    topic = decode_object_from_bytes_if_needed(topic)
    if isinstance(month_offset, bytes):
        month_offset = decode_object_from_bytes_if_needed(month_offset)

    month_offset = int(month_offset)

    topic_start = datetime.datetime.strptime(topic['start_date'], '%Y-%m-%d')
    topic_end = datetime.datetime.strptime(topic['end_date'], '%Y-%m-%d')

    offset_start = topic_start + relativedelta(months=month_offset)
    offset_end = offset_start + relativedelta(months=1)

    if offset_start > topic_end:
        return None

    if offset_end > topic_end:
        offset_end = topic_end

    solr_start = offset_start.strftime('%Y-%m-%d') + 'T00:00:00Z'
    solr_end = offset_end.strftime('%Y-%m-%d') + 'T23:59:59Z'

    date_clause = f"publish_day:[{solr_start} TO {solr_end}]"

    return date_clause


class McGetFullSolrQueryForTopicException(Exception):
    pass


def get_full_solr_query_for_topic(db: DatabaseHandler,
                                  topic: dict,
                                  media_ids: List[int] = None,
                                  media_tags_ids: List[int] = None,
                                  month_offset: int = 0) -> Optional[Dict[str, str]]:
    """
    Get the full Solr query by combining the 'solr_seed_query' with generated clauses for start and end date from
    topics and media clauses from 'topics_media_map' and 'topics_media_tags_map'.

    Only return a query for up to a month of the given a query, using the zero indexed 'month_offset' to fetch
    'month_offset' to return months after the first.

    Return None if the 'month_offset' puts the query start date beyond the topic end date. Otherwise return dictionary
    in the form of { 'q': query, 'fq': filter_query }.

    FIXME topic passed as a parameter might not even exist yet, e.g. this gets called as part of topics/create.
    """
    topic = decode_object_from_bytes_if_needed(topic)
    media_ids = decode_object_from_bytes_if_needed(media_ids)
    media_tags_ids = decode_object_from_bytes_if_needed(media_tags_ids)
    if isinstance(month_offset, bytes):
        month_offset = decode_object_from_bytes_if_needed(month_offset)

    if media_ids:
        media_ids = [int(media_id) for media_id in media_ids]
    if media_tags_ids:
        media_tags_ids = [int(media_tag_id) for media_tag_id in media_tags_ids]

    date_clause = __get_solr_query_month_clause(topic=topic, month_offset=month_offset)
    if not date_clause:
        return None

    solr_query = f"( {topic['solr_seed_query']} )"

    media_clauses = []
    topics_id = topic.get('topics_id', None)

    if topics_id:

        if not media_ids:
            media_ids = db.query("""
                SELECT media_id
                FROM topics_media_map
                WHERE topics_id = %(topics_id)s
            """, {'topics_id': topics_id}).flat()

        if not media_tags_ids:
            media_tags_ids = db.query("""
                SELECT tags_id
                FROM topics_media_tags_map
                WHERE topics_id = %(topics_id)s
            """, {'topics_id': topics_id}).flat()

    if media_ids:
        media_ids_list = ' '.join([str(_) for _ in media_ids])
        media_clauses.append(f"media_id:( {media_ids_list} )")

    if media_tags_ids:
        media_tags_ids_list = ' '.join([str(_) for _ in media_tags_ids])
        media_clauses.append(f"tags_id_media:( {media_tags_ids_list} )")

    if not re.search(r'media_id:|tags_id_media:', topic.get('solr_seed_query', '')):
        if not media_clauses:
            raise McGetFullSolrQueryForTopicException("Query must include at least one media source or media set")

    if media_clauses:
        media_clause_list = ' or '.join(media_clauses)
        solr_query += f" and ( {media_clause_list} )"

    solr_params = {
        'q': solr_query,
        'fq': date_clause,
    }

    log.debug(f"Full Solr query: {solr_params}")

    return solr_params
