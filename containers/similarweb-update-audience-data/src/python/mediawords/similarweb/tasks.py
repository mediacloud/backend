from mediawords.db import DatabaseHandler
from mediawords.db.exceptions.handler import McRequireByIDException
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.url import normalize_url_lossy
from mediawords.similarweb.similarweb import SimilarWebClient


class SimilarWebException(Exception):
    """Used for errors from the SimilarWeb server"""


def check_if_is_domain_exact_match(url: str, domain: str) -> bool:
    """See if the domain would likely resolve to the same place as the url.

    Note that this currently considers query parameters important, so
    'nytimes.com?ref=twitter.com' will be different from 'nytimes.com'

    Parameters
    ----------
    url : str
        Raw url, perhaps from a media source

    domain : str
        Cleaned domain, perhaps from SimilarWebClient.get_domain

    Returns
    -------
    bool, whether the two urls are likely the same.
    """
    return normalize_url_lossy(url) == domain


def update(db: DatabaseHandler, media_id: int, client: SimilarWebClient):
    """Updates a media_id in the database, along with the summary table.

    Parameters
    ----------
    db : DatabaseHandler
        Connection to the database

    media_id : int
        Media id to fetch audience data for

    client : SimilarWebClient
        client to use when querying SimilarWeb
    """
    # MC_REWRITE_TO_PYTHON: remove after rewrite to Python
    if isinstance(media_id, bytes):
        media_id = decode_object_from_bytes_if_needed(media_id)

    media_id = int(media_id)
    try:
        media_data = db.require_by_id('media', media_id)
    except McRequireByIDException:
        raise ValueError('No media found with id {}'.format(media_id))

    url = media_data['url']
    similarweb_data = client.get(url)

    meta = similarweb_data['meta']
    domain = meta['request']['domain']
    is_domain_exact_match = check_if_is_domain_exact_match(url, domain)

    if 'visits' in similarweb_data:
        visits = []
        for row in similarweb_data['visits']:
            visits.append(row['visits'])
            if visits[-1] is not None:
                month_visits = int(visits[-1])
            else:
                month_visits = None
            db.query("""
                INSERT INTO similarweb_metrics (domain, month, visits)
                VALUES (%(domain)s, %(month)s, %(visits)s)
                ON CONFLICT (domain, month) DO UPDATE
                SET domain = %(domain)s, month=%(month)s
            """, {
                'domain': domain,
                'month': row['date'],
                'visits': month_visits,
            })
        if len(visits) == 0:
            monthly_audience = 0
        else:
            # careful of None values
            monthly_audience = int(sum(j if j else 0 for j in visits) / len(visits))
        db.query("""
            INSERT INTO similarweb_media_metrics (similarweb_domain, domain_exact_match, monthly_audience, media_id)
            VALUES (%(similarweb_domain)s, %(domain_exact_match)s, %(monthly_audience)s, %(media_id)s)
            ON CONFLICT (media_id) DO UPDATE
            SET similarweb_domain = %(similarweb_domain)s,
                domain_exact_match = %(domain_exact_match)s,
                monthly_audience = %(monthly_audience)s
        """, {
            'similarweb_domain': domain,
            'domain_exact_match': is_domain_exact_match,
            'monthly_audience': monthly_audience,
            'media_id': media_id,
        })
    elif 'error_message' in meta:
        raise SimilarWebException(meta['error_message'])
    else:
        raise SimilarWebException('Was not able to fetch SimilarWeb data for {} for unknown reason'.format(url))
