"""Various helper utilities for sitemap parsing."""
import datetime
import html
import re
import time
from typing import Optional

import dateutil
from furl import furl

from mediawords.util.compress import gunzip, McGunzipException
from mediawords.util.log import create_logger
from mediawords.util.web.user_agent import UserAgent, Response
from mediawords.util.sitemap.exceptions import McSitemapsException

log = create_logger(__name__)

# Sitemaps might get heavy
__MAX_SITEMAP_SIZE = 100 * 1024 * 1024

# See https://support.google.com/news/publisher-center/answer/74288?hl=en for supported date formats
__DATE_REGEXES = {

    # Complete date: YYYY-MM-DD (e.g. 1997-07-16)
    '%Y-%m-%d': re.compile(
        r'^\d\d\d\d-\d\d-\d\d$'
    ),

    # Complete date plus hours and minutes: YYYY-MM-DDThh:mmTZD (e.g. 1997-07-16T19:20+01:00)
    '%Y-%m-%dT%H:%M%z': re.compile(
        r'^\d\d\d\d-\d\d-\d\dT\d\d:\d\d(\w{1,4}|[+\-]\d\d:\d\d)$'
    ),

    # Complete date plus hours, minutes, and seconds: YYYY-MM-DDThh:mm:ssTZD (e.g. 1997-07-16T19:20:30+01:00)
    '%Y-%m-%dT%H:%M:%S%z': re.compile(
        r'^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d(\w{1,4}|[+\-]\d\d:\d\d)$'
    ),

    # Complete date plus hours, minutes, seconds, and a decimal fraction of a second: YYYY-MM-DDThh:mm:ss.sTZD
    # (e.g. 1997-07-16T19:20:30.45+01:00)
    '%Y-%m-%dT%H:%M:%S.%f%z': re.compile(
        r'^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d\.\d+?(\w{1,4}|[+\-]\d\d:\d\d)$'
    ),

}


def sitemap_useragent() -> UserAgent:
    ua = UserAgent()
    ua.set_max_size(__MAX_SITEMAP_SIZE)
    return ua


def html_unescape_strip(string: Optional[str]) -> Optional[str]:
    """Decode HTML entities, strip string, set to None if it's empty; ignore None as input."""
    if string:
        string = html.unescape(string)
        string = string.strip()
        if not string:
            string = None
    return string


def parse_sitemap_publication_date(date_string: str) -> datetime.datetime:
    """Fast <publication_date> parser.

    dateutil.parser.parse() is a bit slow with huge feeds, so in the class, we pre-match the date with a regex and
    parse it with a faster strptime() with a fallback to a full-blown (and slower) date parser.
    """

    if not date_string:
        raise McSitemapsException("Date string is unset.")

    date = None

    for date_format, date_regex in __DATE_REGEXES.items():

        if re.match(date_regex, date_string):
            date = datetime.datetime.strptime(date_string, date_format)
            break

    if date is None:
        log.warning("Parsing date of unsupported format '{}'".format(date_string))
        date = dateutil.parser.parse(date_string)

    return date


def get_url_retry_on_client_errors(url: str,
                                   ua: UserAgent,
                                   retry_count: int = 5,
                                   sleep_between_retries: int = 1) -> Response:
    """Fetch URL, retry on client errors (which, as per implementation, might be request timeouts too)."""
    assert retry_count > 0, "Retry count must be positive."

    response = None
    for retry in range(0, retry_count):
        log.info("Fetching URL {}...".format(url))
        response = ua.get(url)
        if response.is_success():
            return response
        else:
            log.warning("Request for URL {} failed: {}".format(url, response.message()))

            if response.error_is_client_side():
                log.info("Retrying URL {} in {} seconds...".format(url, sleep_between_retries))
                time.sleep(sleep_between_retries)

            else:
                log.info("Not retrying for URL {}".format(url))
                return response

    log.info("Giving up on URL {}".format(url))
    return response


def __response_is_gzipped_data(response: Response) -> bool:
    """Return True if Response looks like it's gzipped."""
    url_path = str(furl(response.request().url()).path)
    content_type = response.content_type()

    if url_path.lower().endswith('.gz') or 'gzip' in content_type.lower():
        return True

    else:
        return False


def ungzipped_response_content(response: Response) -> str:
    """Return HTTP response's decoded content, gunzip it if neccessary."""

    if __response_is_gzipped_data(response):
        gzipped_data = response.raw_data()
        try:
            data = gunzip(gzipped_data)
        except McGunzipException as ex:
            log.error("Unable to gunzip response {}: {}".format(response, ex))
            data = response.decoded_content()

    else:
        data = response.decoded_content()

    return data
