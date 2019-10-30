from typing import Dict, Optional

from furl import furl

from mediawords.util.config.common import CommonConfig
from mediawords.util.log import create_logger
from mediawords.util.network import wait_for_tcp_port_to_open
from mediawords.util.parse_json import encode_json, decode_json
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import fatal_error
from mediawords.util.web.user_agent import Request, UserAgent

log = create_logger(__name__)

EXTRACTOR_SERVICE_TIMEOUT = 60
"""Seconds to wait for the extraction service to start."""

EXTRACT_TIMEOUT = 60
"""Seconds to wait for extraction of a single story to complete."""

EXTRACT_RETRIES = 3
"""How many times to attempt extracting the same story."""


class McExtractArticleFromPageException(Exception):
    """extract_article_html_from_page_html() exception."""
    pass


def extract_article_html_from_page_html(content: str, config: Optional[CommonConfig] = None) -> Dict[str, str]:
    """
    Using full page HTML as a parameter, extract part of HTML that contains the news article.
    :param content: Full page HTML.
    :param config: Optional CommonConfig object, useful for testing.
    :return: Dictionary with HTML that contains the news article content ("extracted_html" key) and extractor version
             tag ("extractor_version" key).
    """
    content = decode_object_from_bytes_if_needed(content)

    if not config:
        config = CommonConfig()

    ua = UserAgent()
    api_url = config.extractor_api_url()

    # Wait up to a minute for extraction to finish
    ua.set_timeout(EXTRACT_TIMEOUT)

    # Wait for the extractor's HTTP port to become open as the service might be still starting up somewhere
    api_uri = furl(api_url)
    api_url_hostname = str(api_uri.host)
    api_url_port = int(api_uri.port)
    assert api_url_hostname, f"API URL hostname is not set for URL {api_url}"
    assert api_url_port, f"API URL port is not set for URL {api_url}"

    if not wait_for_tcp_port_to_open(
            port=api_url_port,
            hostname=api_url_hostname,
            retries=EXTRACTOR_SERVICE_TIMEOUT,
    ):
        # Instead of throwing an exception, just crash the whole application
        # because there's no point in continuing on running it whatsoever:
        #
        # 1) If the extractor service didn't come up in a given time, it won't
        #    suddenly show up
        # 2) If it's a test that's doing the extraction, it can't do its job
        #    and should fail one way or another; exit(1) is just one of the
        #    ways how it can fail
        # 3) If it's some production code that needs something to get
        #    extracted, and if we were to throw an exception instead of doing
        #    exit(1), the caller might treat this exception as a failure to
        #    extract this one specific input HTML file, and so it might
        #    mis-extract a bunch of stories that way (making it hard for us to
        #    spot the problem and time-consuming to fix it later (e.g. there
        #    would be a need to manually re-extract a million of stories))
        #
        # A better solution instead of exit(1) might be to throw different
        # kinds of exceptions and handle them appropriately in the caller, but
        # with the Perl-Python codebase that's a bit hard to do.
        fatal_error(
            "Extractor service at {url} didn't come up in {timeout} seconds, exiting...".format(
                url=api_url,
                timeout=EXTRACTOR_SERVICE_TIMEOUT,
            )
        )

    request_json = encode_json({'html': content})

    http_request = Request(method='POST', url=api_url)
    http_request.set_content_type('application/json; charset=utf-8')
    http_request.set_content(request_json)

    # Try extracting multiple times
    #
    # UserAgent's set_timing() would only retry on retryable HTTP status codes and doesn't retry on connection errors by
    # default as such retries might have side effects, e.g. an API getting called multiple times. So, we retry
    # extracting the content a couple of times manually.
    http_response = None
    extraction_succeeded = False
    for retry in range(EXTRACT_RETRIES):

        if retry > 0:
            log.warning(f"Retrying #{retry + 1}...")

        http_response = ua.request(http_request)
        if http_response.is_success():
            extraction_succeeded = True
            break
        else:
            log.error(f"Extraction attempt {retry + 1} failed: {http_response.decoded_content()}")

    if not extraction_succeeded:
        raise McExtractArticleFromPageException(
            f"Extraction of {len(content)} characters; failed; last error: {http_response.decoded_content()}"
        )

    response_json = http_response.decoded_content()
    response = decode_json(response_json)

    assert 'extracted_html' in response, "Response is expected to have 'extracted_html' key."
    assert 'extractor_version' in response, "Response is expected to have 'extractor_version' key."

    return response
