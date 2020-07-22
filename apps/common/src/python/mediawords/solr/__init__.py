"""
Functions for querying the Solr server.

    results = query_solr( db, { 'q': 'obama' } )

    sentences = results['response']['docs']
    for sentence in sentences:
        print(f"Found sentence ID: {sentence['story_sentences_id']}")

More information about Solr integration at docs/solr.markdown.
"""

import abc
import copy
import re
from typing import Union, List, Dict, Any, Optional

from mediawords.db import DatabaseHandler
from mediawords.solr.params import SolrParams
from mediawords.solr.request import solr_request
from mediawords.util.log import create_logger
from mediawords.util.parse_json import decode_json
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class _AbstractSolrException(Exception, metaclass=abc.ABCMeta):
    """Abstract .solr exception."""
    pass


class _AbstractSolrInternalErrorException(_AbstractSolrException):
    """Internal code error (most likely a bug in the code)."""
    pass


class McUppercaseBooleanOperatorsInvalidTypeException(_AbstractSolrInternalErrorException):
    """Exception thrown when weird stuff gets passed to _uppercase_boolean_operators()."""
    pass


class McQuerySolrInternalErrorException(_AbstractSolrInternalErrorException):
    """Exception thrown when query_solr() receives something that it didn't expect."""
    pass


class _AbstractSolrInvalidQueryException(_AbstractSolrException):
    """Invalid Solr query."""
    pass


class McInsertCollectionMediaIDsInvalidQueryException(_AbstractSolrInvalidQueryException):
    """Invalid Solr query encountered in _insert_collection_media_ids()."""
    pass


class McQuerySolrInvalidQueryException(_AbstractSolrInvalidQueryException):
    """Invalid Solr query in query_solr()."""
    pass


class McQuerySolrRangeQueryException(_AbstractSolrInvalidQueryException):
    """Exception thrown on range queries which are not allowed."""
    pass


def _uppercase_boolean_operators(query: Union[List[str], str]) -> Union[List[str], str]:
    """
    Convert any "and", "or", or "not" operations in the argument to uppercase.

    If the argument is a list, call ourselves on all elements of the list.
    """
    query = decode_object_from_bytes_if_needed(query)

    if not query:
        return query

    def upper_repl(match) -> str:
        return match.group(1).upper()

    if isinstance(query, list):
        query = [_uppercase_boolean_operators(_) for _ in query]
    elif isinstance(query, str):
        query = re.sub(r'\b(and|or|not)\b', upper_repl, query)
    else:
        raise McUppercaseBooleanOperatorsInvalidTypeException(f"Invalid query type: {query}")

    return query


def _insert_collection_media_ids(db: DatabaseHandler, q: str) -> str:
    """
    Transform any "tags_id_media:" or "collections_id:" clauses into "media_id:" clauses with the "media_ids" that
    corresponds to the given tags.
    """

    q = decode_object_from_bytes_if_needed(q)

    def get_media_ids_clause(match) -> str:
        """Given the argument of "tags_id_media:" or "collections_id:" clause, return the corresponding "media_ids"."""
        arg = match.group(2)

        tags_ids = []
        if re.search(r'^\d+', arg):
            tags_ids.append(arg)

        else:
            parens_match = re.search(r'^\((.*)\)$', arg)

            if parens_match:
                parens = parens_match.group(1)

                parens = re.sub(r'or', ' ', parens, flags=re.IGNORECASE)
                parens = parens.strip()

                if re.search(r'[^\d\s]', parens):
                    raise McInsertCollectionMediaIDsInvalidQueryException((
                        f'Only "or" clauses allowed inside "tags_id_media:" or "collections_id:" clauses: {parens}; '
                        f'full match: {arg}'
                    ))

                for tags_id in re.split(r'\s+', parens):
                    tags_ids.append(tags_id)

            elif re.search(r'^\[', arg):
                raise McQuerySolrRangeQueryException(
                    'Range queries not allowed for "tags_id_media:" or "collections_id:" clauses'
                )

            else:
                raise McInsertCollectionMediaIDsInvalidQueryException(
                    f'Unrecognized format of "tags_id_media:" or "collections_id:" clause: {arg}'
                )

        media_ids = db.query("""
            SELECT media_id
            FROM media_tags_map
            WHERE tags_id IN %(tags_ids)s
            ORDER BY media_id
        """, {'tags_ids': tuple(tags_ids)}).flat()

        # Replace empty list with an id that will always return nothing from Solr
        if not media_ids:
            media_ids = [-1]

        media_clause = f"media_id:({' '.join([str(_) for _ in media_ids])})"

        return media_clause

    if not q:
        return q

    q = re.sub(r'(tags_id_media|collections_id):(\d+|\([^)]*\)|\[[^\]]*\])', get_media_ids_clause, q)

    return q


def _replace_smart_quotes(query: Union[List[str], str]) -> Union[List[str], str]:
    """
    Replace smart quotes with straight versions so that solr will treat them correctly.
    """
    if query is None:
        return None
    elif isinstance(query, list):
        return [_replace_smart_quotes(_) for _ in query]
    elif isinstance(query, str):
        return query.replace(u"\u201c", '"').replace(u"\u201d", '"')


def query_solr(db: DatabaseHandler, params: SolrParams) -> Dict[str, Any]:
    """
    Execute a query on the Solr server using the given parameters. Return a maximum of 1 million sentences.

    The "params" argument is a dictionary of query parameters to Solr, detailed here:

        https://lucene.apache.org/solr/guide/6_6/common-query-parameters.html.

    The query ("params['q']") is transformed: lower case boolean operators are made uppercase to make Solr recognize
    them as boolean queries.

    Return decoded response in the format described here:

        https://lucene.apache.org/solr/guide/6_6/response-writers.html#ResponseWriters-JSONResponseWriter
    """
    params = decode_object_from_bytes_if_needed(params)

    # Avoid editing the dictionary itself
    params = copy.deepcopy(params)

    if not params:
        raise McQuerySolrInternalErrorException('Parameters must be set.')

    if not isinstance(params, dict):
        raise McQuerySolrInternalErrorException('Parameters must be a dictionary.')

    params['wt'] = 'json'

    if 'rows' in params:
        params['rows'] = int(params['rows'])
    else:
        params['rows'] = 1000

    if 'df' not in params:
        params['df'] = 'text'

    params['rows'] = min(params['rows'], 10_000_000)

    if 'q' not in params:
        params['q'] = ''

    # "fq" might be nonexistent or None
    if not params.get('fq', None):
        params['fq'] = []

    if not isinstance(params['fq'], list):
        params['fq'] = [params['fq']]

    if ':[' in params['q']:
        raise McQuerySolrRangeQueryException(
            "Range queries are not allowed in the main query. Please use a filter query instead for range queries."
        )

    # if params['q']:
    #     params['q'] = f"{{!complexphrase inOrder=false}} {params['q']}"

    params['q'] = _uppercase_boolean_operators(params['q'])
    params['q'] = _uppercase_boolean_operators(params['q'])

    params['fq'] = _replace_smart_quotes(params['fq'])
    params['fq'] = _replace_smart_quotes(params['fq'])

    if params['q']:
        params['q'] = _insert_collection_media_ids(db=db, q=params['q'])
    if params['fq']:
        params['fq'] = [_insert_collection_media_ids(db=db, q=_) for _ in params['fq']]

    response_json = solr_request(
        path='select',
        params={},
        content=params,
        content_type='application/x-www-form-urlencoded; charset=utf-8',
    )

    try:
        response = decode_json(response_json)
    except Exception as ex:
        raise McQuerySolrInternalErrorException(f"Error parsing Solr JSON: {ex}\nJSON: {response_json}")

    if 'error' in response:
        raise McQuerySolrInvalidQueryException(f"Error received from Solr: {response_json}")

    return response


def _get_intersection_of_lists(lists: List[List[int]]) -> List[int]:
    """Given a list of lists, each of which points to a list of IDs, return an intersection between them."""
    lists = decode_object_from_bytes_if_needed(lists)

    if not lists:
        log.error("Lists are empty")
        return []

    intersection = set(lists[0])

    for cur_list in lists[1:]:
        intersection = intersection.intersection(set(cur_list))

    return sorted(list(intersection))


def _get_stories_ids_from_stories_only_q(q: str) -> Optional[List[int]]:
    """
    Transform the pseudoquery fields in the query and then run a simple pattern to detect queries that consists of one
    or more AND'ed "stories_id:..." clauses.

    For those cases, just return the story IDs list rather than running it through Solr.

    Return None if the query does not match.
    """
    q = decode_object_from_bytes_if_needed(q)

    if not q:
        return None

    q = re.sub(r'^\s*\(\s*(?P<inside_parens>.*)\s*\)\s*$', r'\g<inside_parens>', q)
    q = q.strip()

    if 'and' in q.lower():
        p = q.lower().index('and')
    else:
        p = -1

    if p > 0:
        q_a = q[:p - 1]
        a_stories_ids = _get_stories_ids_from_stories_only_q(q=q_a)
        if a_stories_ids is None:
            return None

        q_b = q[p + 4:]
        b_stories_ids = _get_stories_ids_from_stories_only_q(q=q_b)
        if b_stories_ids is None:
            return None

        r = _get_intersection_of_lists(lists=[a_stories_ids, b_stories_ids])
        return r

    story_match = re.search(r'^stories_id:(\d+)$', q)
    if story_match:
        stories_id = int(story_match.group(1))
        r = [stories_id]
        return r

    if re.search(r'^stories_id:\([\s\d]+\)$', q):
        stories_ids = []
        for story_match in re.findall(r'(\d+)', q):
            stories_id = int(story_match)
            stories_ids.append(stories_id)
        return stories_ids

    return None


def _get_stories_ids_from_stories_only_params(params: SolrParams) -> Optional[List[int]]:
    """
    Transform the pseudoquery fields in the "q" and "fq" params and then run a simple pattern to detect queries that
    consists of one or more AND'ed "stories_id:..." clauses in the "q" param and all "fq" params.

    Return None if either the "q" or any of the "fq" params do not match.
    """
    params = decode_object_from_bytes_if_needed(params)

    # Avoid editing the dictionary itself
    params = copy.deepcopy(params)

    q = params.get('q', '')
    fqs = params.get('fq', [])
    start = params.get('start', None)
    rows = params.get('rows', None)

    if start is not None:
        start = int(start)
    if rows is not None:
        rows = int(rows)

    # Return None if there are any unrecognized params
    param_keys = set(list(params.keys()))
    allowed_params = {'q', 'fq', 'start', 'rows'}
    if not param_keys.issubset(allowed_params):
        log.warning(f"Parameters have unrecognized keys: {param_keys - allowed_params}; all keys: {param_keys}")
        return None

    if not q:
        log.error("'q' is unset.")
        return None

    stories_ids_lists = []

    if fqs:
        if not isinstance(fqs, list):
            fqs = [fqs]

        for fq in fqs:
            stories_ids = _get_stories_ids_from_stories_only_q(q=fq)
            if stories_ids is None:
                return None
            else:
                stories_ids_lists.append(stories_ids)

    # If there are stories_ids only "fqs" and a '*:*' "q", just use the "fqs"
    if stories_ids_lists and q == '*:*':
        r = _get_intersection_of_lists(lists=stories_ids_lists)

    # If there were no "fqs" and a '*:*' "q", return None
    elif q == '*:*':
        return None

    # Otherwise, combine "q" and "fqs"
    else:
        stories_ids = _get_stories_ids_from_stories_only_q(q=q)
        if stories_ids is None:
            return None

        r = _get_intersection_of_lists(lists=[stories_ids] + stories_ids_lists)

    if start is not None:
        r = r[start:]

    if rows is not None:
        r = r[:rows]

    return r


def get_solr_num_found(db: DatabaseHandler, params: SolrParams) -> int:
    """Execute the query and return only the number of documents found."""
    params = decode_object_from_bytes_if_needed(params)

    # Avoid editing the dictionary itself
    params = copy.deepcopy(params)

    params['rows'] = 0

    res = query_solr(db=db, params=params)

    num_found = res['response']['numFound']

    return num_found


def search_solr_for_stories_ids(db: DatabaseHandler, params: SolrParams) -> List[int]:
    """
    Return a list of all of the "stories_ids" that match the Solr query.

    Using Solr side grouping on the "stories_id" field.
    """
    params = decode_object_from_bytes_if_needed(params)

    # Avoid editing the dictionary itself
    params = copy.deepcopy(params)

    stories_ids = _get_stories_ids_from_stories_only_params(params)
    if stories_ids:
        return stories_ids

    params['fl'] = 'stories_id'

    response = query_solr(db=db, params=params)

    stories_ids = [_['stories_id'] for _ in response['response']['docs']]

    return stories_ids


def search_solr_for_processed_stories_ids(db: DatabaseHandler,
                                          q: str,
                                          fq: Optional[Union[str, List[str]]],
                                          last_ps_id: int,
                                          num_stories: int,
                                          sort_by_random: bool = False) -> List[int]:
    """
    Return the first "num_stories" "processed_stories_id" that match the given query, sorted by "processed_stories_id"
    and with "processed_stories_id" greater than "last_ps_id".

    Returns at most "num_stories" stories.

    If "sort_by_random" is True, tell Solr to sort results by random order.
    """

    q = decode_object_from_bytes_if_needed(q)
    fq = decode_object_from_bytes_if_needed(fq)
    if isinstance(last_ps_id, bytes):
        last_ps_id = decode_object_from_bytes_if_needed(last_ps_id)
    if isinstance(num_stories, bytes):
        num_stories = decode_object_from_bytes_if_needed(num_stories)
    if isinstance(sort_by_random, bytes):
        sort_by_random = decode_object_from_bytes_if_needed(sort_by_random)

    last_ps_id = int(last_ps_id)
    num_stories = int(num_stories)
    sort_by_random = bool(int(sort_by_random))

    if not num_stories:
        return []

    if fq:
        if not isinstance(fq, list):
            fq = [fq]
    else:
        fq = []

    if last_ps_id:
        min_ps_id = last_ps_id + 1
        fq.append(f"processed_stories_id:[{min_ps_id} TO *]")

    params = {
        'q': q,
        'fq': fq,
        'fl': 'processed_stories_id',
        'rows': num_stories,
        'sort': 'random_1 asc' if sort_by_random else 'processed_stories_id asc',
    }

    response = query_solr(db=db, params=params)

    ps_ids = [_['processed_stories_id'] for _ in response['response']['docs']]

    return ps_ids


def search_solr_for_media_ids(db: DatabaseHandler, params: SolrParams) -> List[int]:
    """Return all of the media IDs that match the Solr query."""
    params = decode_object_from_bytes_if_needed(params)

    # Avoid editing the dictionary itself
    params = copy.deepcopy(params)

    params['fl'] = 'media_id'
    params['facet'] = 'true'
    params['facet.limit'] = 1_000_000
    params['facet.field'] = 'media_id'
    params['facet.mincount'] = 1
    params['rows'] = 0

    response = query_solr(db=db, params=params)

    counts = response['facet_counts']['facet_fields']['media_id']

    # Every second element (?)
    media_ids = counts[::2]

    return media_ids
