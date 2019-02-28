#!/usr/bin/env python3

import argparse
import csv
import sys
from datetime import datetime
import functools
from collections import OrderedDict
from concurrent.futures.process import ProcessPoolExecutor
from dataclasses import dataclass
from typing import Optional, List
from urllib.parse import urlparse

from dateutil.relativedelta import relativedelta

from mediawords.util.log import create_logger
from mediawords.util.parse_json import decode_json
from mediawords.util.url import is_http_url, fix_common_url_mistakes
from mediawords.util.web.user_agent import UserAgent

log = create_logger(__name__)

# SimilarWeb blocks us with many workers
__MULTIPROCESSING_WORKER_POOL_SIZE = 2


def _url_domain(url: str) -> Optional[str]:
    try:
        url = url.strip()
        url = fix_common_url_mistakes(url)

        assert is_http_url(url), f"URL not HTTP(S) URL: {url}."

        uri = urlparse(url)

        hostname_parts = uri.hostname.split('.')

        while len(hostname_parts) > 0 and hostname_parts[0] == 'www':
            hostname_parts.pop(0)

        hostname = '.'.join(hostname_parts)

        return hostname

    except Exception as ex:
        log.warning(f"Unable to get domain from URL '{url}': {ex}")
        return None


@dataclass(frozen=True)
class MediumVisit(object):
    date: datetime
    count: int


@dataclass(frozen=True)
class Medium(object):
    media_id: int
    name: str
    url: str
    domain: Optional[str]


@dataclass(frozen=True)
class MediumWithVisits(Medium):
    last_updated: datetime
    visits: List[MediumVisit]


def __process_csv_row(row: OrderedDict, api_key: str, start_date: datetime, end_date: datetime) -> Medium:
    assert row, "Row is unset."
    assert api_key, "API key is unset."

    media_id = int(row['media_id'])
    medium_name = row['name'].strip()
    url = row['url'].strip()
    domain = _url_domain(url)

    medium_without_visits = Medium(
        media_id=media_id,
        name=medium_name,
        url=url,
        domain=domain,
    )

    if not domain:
        log.warning(f"Unable to get domain for URL {url}.")
        return medium_without_visits

    api_url = (
        "https://api.similarweb.com/v1/website/{domain}/total-traffic-and-engagement/visits?"
        "api_key={api_key}&start_date={start_date}&end_date={end_date}&main_domain_only=true&granularity=monthly"
    ).format(
        domain=domain,
        api_key=api_key,
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
        # noinspection PyTypeChecker
        if response['meta']['error_code'] == 401:
            log.warning(f"Data was not found for domain {domain}.")
            return medium_without_visits
        else:
            raise Exception(f"Response was not successful for domain {domain}: {response}")

    # noinspection PyTypeChecker
    last_updated = datetime.strptime(response['meta']['last_updated'], '%Y-%m-%d')

    medium_visits = []
    for visit in response['visits']:
        visit_date = datetime.strptime(visit['date'], '%Y-%m-%d')
        visit_count = int(visit['visits'])
        medium_visits.append(MediumVisit(date=visit_date, count=visit_count))

    # noinspection PyArgumentList
    return MediumWithVisits(
        media_id=media_id,
        name=medium_name,
        url=url,
        domain=domain,
        last_updated=last_updated,
        visits=medium_visits,
    )


def goodbye_dump(media_csv_path: str, api_key: str):
    now = datetime.today()

    start_month_offset = -13
    end_month_offset = -2

    start_date = (now + relativedelta(months=start_month_offset)).strftime('%Y-%m')
    end_date = (now + relativedelta(months=end_month_offset)).strftime('%Y-%m')

    csv_header = ['media_id', 'name', 'url', 'domain', 'last_updated']
    for month_offset in range(start_month_offset, end_month_offset + 1):
        csv_header.append('visits-{}'.format((now + relativedelta(months=month_offset)).strftime('%Y-%m')))

    with ProcessPoolExecutor(max_workers=__MULTIPROCESSING_WORKER_POOL_SIZE) as executor:
        with open(media_csv_path, "r", encoding='utf-8') as f:

            writer = csv.writer(sys.stdout)
            writer.writerow(csv_header)

            reader = csv.DictReader(f)
            for medium in executor.map(
                    functools.partial(
                        __process_csv_row,
                        api_key=api_key,
                        start_date=start_date,
                        end_date=end_date,
                    ),
                    reader,
                    chunksize=__MULTIPROCESSING_WORKER_POOL_SIZE * 2,
            ):

                row = [
                    medium.media_id,
                    medium.name,
                    medium.url,
                    medium.domain,
                ]

                if isinstance(medium, MediumWithVisits):
                    row.append(medium.last_updated.strftime('%Y-%m-%d'))

                    for visit in medium.visits:
                        row.append(visit.count)

                else:
                    for x in range(len(csv_header) - len(row)):
                        row.append(None)

                assert len(row) == len(csv_header)
                writer.writerow(row)
                sys.stdout.flush()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Run SimilarWeb goodbye dump.')
    parser.add_argument('-m', '--media_csv_path', type=str, required=True, help='Path to media CSV.')
    parser.add_argument('-a', '--api_key', type=str, required=True, help='SimilarWeb API key.')
    args = parser.parse_args()
    goodbye_dump(media_csv_path=args.media_csv_path, api_key=args.api_key)
