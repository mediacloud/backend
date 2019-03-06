from dataclasses import dataclass
from datetime import datetime
from http import HTTPStatus
from typing import Optional, List

from dateutil.relativedelta import relativedelta

from mediawords.util.config import get_config as py_get_config
from mediawords.util.log import create_logger
from mediawords.util.parse_json import decode_json
from mediawords.util.web.user_agent import UserAgent

log = create_logger(__name__)

__START_MONTH_OFFSET = -13
"""API returns stats only up to 12 months before current date."""

__END_MONTH_OFFSET = -2
"""API returns stats only down to 1 month before current date."""

__MAIN_DOMAIN_ONLY = False
"""Include subdomains into domain stats."""


def similarweb_api_key() -> str:
    """Return SimilarWeb API key or raise exception."""
    config = py_get_config()
    api_key = config['similarweb']['api_key']
    if not api_key:
        raise McEstimatedVisitsException("API key is unset.")
    return api_key


@dataclass(frozen=True)
class DomainVisit(object):
    """Estimated visits count for domain on specific month."""
    month: datetime
    count: int


@dataclass(frozen=True)
class Domain(object):
    """Estimated visits domain."""
    domain: str
    main_domain_only: bool
    last_updated: datetime
    visits: List[DomainVisit]


class McEstimatedVisitsException(Exception):
    """estimated_visits() exception."""
    pass


def estimated_visits(domain: str, api_key: Optional[str] = None) -> Optional[Domain]:
    """Fetch estimated visits for domain; return None if stats for domain were not found."""

    if not api_key:
        api_key = similarweb_api_key()

    now = datetime.today()

    start_date = (now + relativedelta(months=__START_MONTH_OFFSET)).strftime('%Y-%m')
    end_date = (now + relativedelta(months=__END_MONTH_OFFSET)).strftime('%Y-%m')

    api_url = (
        "https://api.similarweb.com/v1/website/{domain}/total-traffic-and-engagement/visits?api_key={api_key}&"
        "start_date={start_date}&end_date={end_date}&main_domain_only={main_domain_only}&granularity=monthly"
    ).format(
        domain=domain,
        api_key=api_key,
        main_domain_only=str(__MAIN_DOMAIN_ONLY).lower(),
        start_date=start_date,
        end_date=end_date,
    )

    ua = UserAgent()
    result = ua.get(api_url)
    if not result.is_success():
        raise Exception(f"Invalid response for domain {domain}: {result.decoded_content()}")

    response = decode_json(result.decoded_content())

    # noinspection PyTypeChecker
    if response['meta']['status'] != 'Success':
        meta = response['meta']
        # noinspection PyTypeChecker
        if meta['error_code'] == HTTPStatus.UNAUTHORIZED and 'Data not found' in meta['error_message']:
            log.warning(f"Data was not found for domain {domain}.")
            return None
        else:
            raise McEstimatedVisitsException(f"Response was not successful for domain {domain}: {response}")

    # noinspection PyTypeChecker
    last_updated = datetime.strptime(response['meta']['last_updated'], '%Y-%m-%d')

    medium_visits = []
    for visit in response['visits']:
        visit_month = datetime.strptime(visit['date'], '%Y-%m-%d')
        visit_count = int(visit['visits'])
        medium_visits.append(DomainVisit(month=visit_month, count=visit_count))

    # noinspection PyArgumentList
    return Domain(
        domain=domain,
        main_domain_only=__MAIN_DOMAIN_ONLY,
        last_updated=last_updated,
        visits=medium_visits,
    )
