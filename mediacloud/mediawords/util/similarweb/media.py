from typing import Optional

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.similarweb.api import estimated_visits, similarweb_api_key
from mediawords.util.similarweb.domain import domain_from_url

log = create_logger(__name__)


class McUpdateEstimatedVisitsForMediaIDException(Exception):
    """update_estimated_visits_for_media_id() exception."""
    pass


class McUpdateEstimatedVisitsForMediaIDNonFatalException(McUpdateEstimatedVisitsForMediaIDException):
    """update_estimated_visits_for_media_id() non-fatal exception.

    Fetching stats for this medium failed but others should work just fine.
    """
    pass


class McUpdateEstimatedVisitsForMediaIDFatalException(McUpdateEstimatedVisitsForMediaIDException):
    """update_estimated_visits_for_media_id() fatal exception.

    Something wrong with the way we make API calls, so there's no point in proceeding further."""
    pass


def update_estimated_visits_for_media_id(db: DatabaseHandler, media_id: int, api_key: Optional[str] = None) -> None:
    """Update estimated visits count for media."""
    if isinstance(media_id, bytes):
        media_id = decode_object_from_bytes_if_needed(media_id)

    if not api_key:
        api_key = similarweb_api_key()

    media_id = int(media_id)
    medium = db.require_by_id(table='media', object_id=media_id)

    domain = domain_from_url(medium['url'])
    if not domain:
        raise McUpdateEstimatedVisitsForMediaIDNonFatalException(f"Domain for media ID {media_id} is unset.")

    # Add domain
    domain_row = db.query("""
        INSERT INTO similarweb_domains (domain)
        VALUES (%(domain)s)

        -- No-op update set increase xmax on existing domains
        ON CONFLICT (domain) DO UPDATE SET domain = EXCLUDED.domain
        RETURNING
            similarweb_domains_id,
            (xmax = 0) AS new_domain_created
    """, {'domain': domain}).hash()
    if not domain_row:
        raise McUpdateEstimatedVisitsForMediaIDFatalException(
            f"Unable to find / create domain for media ID {media_id}, domain {domain}."
        )
    domains_id = domain_row['similarweb_domains_id']
    new_domain_created = domain_row['new_domain_created']

    # Establish mapping between domain and media source
    db.query("""
        INSERT INTO media_similarweb_domains_map (media_id, similarweb_domains_id)
        VALUES (%(media_id)s, %(similarweb_domains_id)s)
        ON CONFLICT (media_id, similarweb_domains_id) DO NOTHING
    """, {
        'media_id': media_id,
        'similarweb_domains_id': domains_id,
    })

    # If domain already exists, we assume that the stats were fetched for that domain (or at least were attempted to be
    # fetched) so we don't do it again
    if new_domain_created:

        # Fetch stats for domain
        try:
            domain_stats = estimated_visits(domain=domain, api_key=api_key)
        except Exception as ex:
            # If estimated_visits() threw an exception, it means that the request didn't succeed and there's no point in
            # continuing further until we fix something (reduce the amount of workers if they've rate-limited us, or fix
            # the start - end dates)
            raise McUpdateEstimatedVisitsForMediaIDFatalException(
                f"API request failed while fetching stats for media ID {media_id}, domain {domain}: {ex}"
            )

        if domain_stats:

            for visits in domain_stats.visits:
                db.query("""
                    INSERT INTO similarweb_estimated_visits (similarweb_domains_id, month, main_domain_only, visits)
                    VALUES (%(similarweb_domains_id)s, %(month)s, %(main_domain_only)s, %(visits)s)

                    -- Some other worker might have already fetched the stats for a duplicate domain in that time
                    ON CONFLICT (similarweb_domains_id, month, main_domain_only) DO NOTHING
                """, {
                    'similarweb_domains_id': domains_id,
                    'month': visits.month,
                    'main_domain_only': domain_stats.main_domain_only,
                    'visits': visits.count,
                })

        else:

            log.warning(f"Visits for media ID {media_id}, domain {domain} were not found.")

    else:

        log.info(f"Stats already exist for domain {domain}, not refetching for media ID {media_id}.")
