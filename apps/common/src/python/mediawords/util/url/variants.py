import re
from typing import List

from mediawords.db import DatabaseHandler
from mediawords.util.parse_html import link_canonical_url_from_html
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.url import fix_common_url_mistakes, is_http_url, normalize_url, is_homepage_url
from mediawords.util.web.user_agent import UserAgent

log = create_logger(__name__)

# Regular expressions for invalid "variants" of the resolved URL
__INVALID_URL_VARIANT_REGEXES = [

    # Twitter's "suspended" accounts
    re.compile('^https?://twitter.com/account/suspended', flags=re.IGNORECASE),
]


class McAllURLVariantsException(Exception):
    """all_url_variants() exception."""
    pass


def __get_merged_stories_ids(db: DatabaseHandler, stories_ids: List[int], n: int = 0) -> List[int]:
    """Gor a given set of stories, get all the stories that are source or target merged stories in
    topic_merged_stories_map. Repeat recursively up to 10 times, or until no new stories are found."""

    stories_ids = decode_object_from_bytes_if_needed(stories_ids)

    # "The crazy load was from a query to our topic_merged_stories_ids to get
    # url variants.  It looks like we have some case of many, many merged story
    # pairs that are causing that query to make postgres sit on a cpu for a
    # super long time.  There's no good reason to query for ridiculous numbers
    # of merged stories, so I just arbitrarily capped the number of merged story
    # pairs to 20 to prevent this query from running away in the future."
    max_stories = 20

    # MC_REWRITE_TO_PYTHON: cast strings to ints
    # noinspection PyTypeChecker
    stories_ids = [int(x) for x in stories_ids]

    if len(stories_ids) == 0:
        return []

    if len(stories_ids) >= max_stories:
        return stories_ids[0:max_stories - 1]

    # MC_REWRITE_TO_PYTHON: change to tuple parameter because Perl database handler proxy can't handle tuples
    stories_ids_list = ', '.join(str(x) for x in stories_ids)

    merged_stories_ids = db.query("""
        SELECT DISTINCT
            target_stories_id,
            source_stories_id
        FROM topic_merged_stories_map
        WHERE target_stories_id IN (%(stories_ids_list)s)
          OR source_stories_id IN (%(stories_ids_list)s)
        LIMIT %(max_stories)s
    """ % {
        'stories_ids_list': stories_ids_list,
        'max_stories': int(max_stories),
    }).flat()

    # MC_REWRITE_TO_PYTHON: Perl database handler proxy (the dreaded "wantarray" part) returns None on empty result
    # sets, a scalar on a single item and arrayref on many items
    if merged_stories_ids is None:
        merged_stories_ids = []
    elif isinstance(merged_stories_ids, int):
        merged_stories_ids = [merged_stories_ids]

    merged_stories_ids = [int(x) for x in merged_stories_ids]

    all_stories_ids = list(set(stories_ids + merged_stories_ids))

    if n > 10 or len(stories_ids) == len(all_stories_ids) or len(stories_ids) >= max_stories:
        return all_stories_ids

    else:
        return __get_merged_stories_ids(db=db, stories_ids=all_stories_ids, n=n + 1)


# MC_REWRITE_TO_PYTHON: should return a set, not a list, but Perl doesn't support set
def __get_topic_url_variants(db: DatabaseHandler, urls: List[str]) -> List[str]:
    """Get any alternative urls for the given url from topic_merged_stories or topic_links."""

    urls = decode_object_from_bytes_if_needed(urls)

    # MC_REWRITE_TO_PYTHON: change to tuple parameter because Perl database handler proxy can't handle tuples
    stories_ids_sql = "SELECT stories_id "
    stories_ids_sql += "FROM stories "
    stories_ids_sql += "WHERE url = ANY(?)"
    stories_ids = db.query(stories_ids_sql, urls).flat()

    # MC_REWRITE_TO_PYTHON: Perl database handler proxy (the dreaded "wantarray" part) returns None on empty result
    # sets, a scalar on a single item and arrayref on many items
    if stories_ids is None:
        stories_ids = []
    elif isinstance(stories_ids, int):
        stories_ids = [stories_ids]

    stories_ids = [int(x) for x in stories_ids]

    all_stories_ids = __get_merged_stories_ids(db=db, stories_ids=stories_ids)
    if len(all_stories_ids) == 0:
        return urls

    all_urls = db.query("""
        SELECT DISTINCT url
        FROM (
            SELECT redirect_url AS url
            FROM topic_links
            WHERE ref_stories_id = ANY(?)

            UNION

            SELECT url
            FROM topic_links
            WHERE ref_stories_id = ANY(?)

            UNION

            SELECT url
            FROM stories
            WHERE stories_id = ANY(?)
        ) AS q
        WHERE q IS NOT NULL
    """, all_stories_ids, all_stories_ids, all_stories_ids).flat()

    # MC_REWRITE_TO_PYTHON: Perl database handler proxy (the dreaded "wantarray" part) returns None on empty result
    # sets, a scalar on a single item and arrayref on many items
    if all_urls is None:
        all_urls = []
    elif isinstance(all_urls, str):
        all_urls = [all_urls]

    return all_urls


# MC_REWRITE_TO_PYTHON: replace return value to set after the rewrite
def all_url_variants(db: DatabaseHandler, url: str) -> List[str]:
    """Given the URL, return all URL variants that we can think of:

    1) Normal URL (the one passed as a parameter)
    2) URL after redirects (i.e., fetch the URL, see if it gets redirected somewhere)
    3) Canonical URL (after removing #fragments, session IDs, tracking parameters, etc.)
    4) Canonical URL after redirects (do the redirect check first, then strip the tracking parameters from the URL)
    5) URL from <link rel="canonical" /> (if any)
    6) Any alternative URLs from topic_merged_stories or topic_links"""

    url = decode_object_from_bytes_if_needed(url)

    if url is None:
        raise McAllURLVariantsException("URL is None.")

    url = fix_common_url_mistakes(url)
    if not is_http_url(url):
        log.warning("URL %s is not a valid HTTP URL." % url)
        return [
            url,
        ]

    # Get URL after HTTP / HTML redirects
    ua = UserAgent()
    response = ua.get_follow_http_html_redirects(url)
    url_after_redirects = response.request().url()
    data_after_redirects = response.decoded_content()

    urls = {

        # Normal URL (don't touch anything)
        'normal': url,

        # Normal URL after redirects
        'after_redirects': url_after_redirects,

        # Canonical URL
        'normalized': normalize_url(url),

        # Canonical URL after redirects
        'after_redirects_normalized': normalize_url(url_after_redirects),
    }

    # If <link rel="canonical" /> is present, try that one too
    if data_after_redirects is not None:
        url_link_rel_canonical = link_canonical_url_from_html(html=data_after_redirects, base_url=url_after_redirects)
        if url_link_rel_canonical is not None and len(url_link_rel_canonical) > 0:
            log.debug(
                (
                    'Found <link rel="canonical" /> for URL %(url_after_redirects)s '
                    '(original URL: %(url)s): %(url_link_rel_canonical)s'
                ) % {
                    "url_after_redirects": url_after_redirects,
                    "url": url,
                    "url_link_rel_canonical": url_link_rel_canonical,
                }
            )

            urls['after_redirects_canonical'] = url_link_rel_canonical

    # If URL gets redirected to the homepage (e.g.
    # http://m.wired.com/threatlevel/2011/12/sopa-watered-down-amendment/ leads
    # to http://www.wired.com/), don't use those redirects
    if not is_homepage_url(url):
        urls = {key: urls[key] for key in urls.keys() if not is_homepage_url(urls[key])}

    distinct_urls = list(set(urls.values()))

    topic_urls = __get_topic_url_variants(db=db, urls=distinct_urls)

    distinct_urls = distinct_urls + topic_urls
    distinct_urls = list(set(distinct_urls))

    # Remove URLs that can't be variants of the initial URL
    for invalid_url_variant_regex in __INVALID_URL_VARIANT_REGEXES:
        distinct_urls = [x for x in distinct_urls if not re.search(pattern=invalid_url_variant_regex, string=x)]

    return distinct_urls
