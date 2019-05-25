import re
from io import StringIO
from typing import Union

from lxml import etree

from mediawords.util.parse_html import meta_refresh_url_from_html, link_canonical_url_from_html
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.url import is_http_url
from mediawords.util.web.user_agent.request.request import Request

log = create_logger(__name__)


# FIXME rename "archive_site_url" to "url"
# FIXME refactor into class one day

def target_request_from_meta_refresh_url(content: str, archive_site_url: str) -> Union[Request, None]:
    """Given a URL and content from website with META refresh, return a request for the original URL."""

    content = decode_object_from_bytes_if_needed(content)
    archive_site_url = decode_object_from_bytes_if_needed(archive_site_url)

    if content is None:
        return None

    target_url = meta_refresh_url_from_html(html=content, base_url=archive_site_url)
    if target_url is None:
        return None

    if not is_http_url(target_url):
        log.error("URL matched, but is not HTTP(s): %s" % target_url)
        return None

    return Request(method='GET', url=target_url)


# noinspection PyUnusedLocal
def target_request_from_archive_org_url(content: Union[str, None], archive_site_url: str) -> Union[Request, None]:
    """Given a URL and content from archive.org, return a request for the original URL."""

    content = decode_object_from_bytes_if_needed(content)
    archive_site_url = decode_object_from_bytes_if_needed(archive_site_url)

    matches = re.match(
        pattern=r'^https?://web\.archive\.org/web/(?P<date>\d+?/)?(?P<target_url>https?://.+?)$',
        string=archive_site_url,
        flags=re.IGNORECASE
    )
    if matches:
        target_url = matches.group('target_url')

        if is_http_url(target_url):
            return Request(method='GET', url=target_url)
        else:
            log.error("URL matched, but is not HTTP(s): %s" % target_url)

    return None


def target_request_from_archive_is_url(content: str, archive_site_url: str) -> Union[Request, None]:
    """Given a URL and content from archive.is, return a request for the original URL."""
    content = decode_object_from_bytes_if_needed(content)
    archive_site_url = decode_object_from_bytes_if_needed(archive_site_url)

    if content is None:
        return None

    if re.match(pattern=r'^https?://archive\.is/(.+?)$', string=archive_site_url, flags=re.IGNORECASE):
        canonical_link = link_canonical_url_from_html(html=content)
        if canonical_link is not None:
            matches = re.match(
                pattern=r'^https?://archive\.is/\d+?/(?P<target_url>https?://.+?)$',
                string=canonical_link,
                flags=re.IGNORECASE
            )
            if matches:
                target_url = matches.group('target_url')

                if is_http_url(target_url):
                    return Request(method='GET', url=target_url)
                else:
                    log.error("URL matched, but is not HTTP(s): %s" % target_url)

            else:
                log.error(
                    "Unable to parse original URL from archive.is response '%s': %s" %
                    (archive_site_url, canonical_link,)
                )
        else:
            log.error("Unable to parse original URL from archive.is response '%s'" % archive_site_url)

    return None


def target_request_from_linkis_com_url(content: str, archive_site_url: str) -> Union[Request, None]:
    """Given the content of a linkis.com web page, find the original URL in the content, which may be in one of sereral
    places in the DOM, and return a request for said URL."""

    content = decode_object_from_bytes_if_needed(content)
    archive_site_url = decode_object_from_bytes_if_needed(archive_site_url)

    if content is None:
        return None

    if not re.match(pattern='^https?://[^/]*linkis.com/', string=archive_site_url, flags=re.IGNORECASE):
        return None

    # list of dom search patterns to find nodes with a url and the
    # attributes to use from those nodes as the url.
    #
    # for instance the first item matches:
    #
    #     <meta property="og:url" content="http://foo.bar">
    #
    try:
        html_parser = etree.HTMLParser()
        html_tree = etree.parse(StringIO(content), html_parser)

        dom_maps = [
            ('//meta[@property="og:url"]', 'content'),
            ('//a[@class="js-youtube-ln-event"]', 'href'),
            ('//iframe[@id="source_site"]', 'src'),
        ]

        for xpath, url_attribute in dom_maps:
            nodes = html_tree.xpath(xpath)

            if len(nodes) > 0:
                first_node = nodes[0]
                matched_url = first_node.get(url_attribute)
                if matched_url is not None:
                    if not re.match(pattern='^https?://linkis.com', string=matched_url, flags=re.IGNORECASE):

                        if is_http_url(matched_url):
                            return Request(method='GET', url=matched_url)
                        else:
                            log.error("URL matched, but is not HTTP(s): %s" % matched_url)

    except Exception as ex:
        log.warning("Unable to parse HTML for URL %s: %s" % (archive_site_url, str(ex),))

    # As a last resort, look for the longUrl key in a JavaScript array
    matches = re.search(pattern=r'"longUrl":\s*"(?P<target_url>[^"]+)"', string=content, flags=re.IGNORECASE)
    if matches:
        target_url = matches.group('target_url')

        # kludge to de-escape \'d characters in javascript -- 99% of urls
        # are captured by the dom stuff above, we shouldn't get to this
        # point often
        target_url = target_url.replace('\\', '')

        if not re.match(pattern='^https?://linkis.com', string=target_url, flags=re.IGNORECASE):
            if is_http_url(target_url):
                return Request(method='GET', url=target_url)
            else:
                log.error("URL matched, but is not HTTP(s): %s" % target_url)

    log.warning("No URL found for linkis URL: %s" % archive_site_url)

    return None


def target_request_from_alarabiya_url(content: str, archive_site_url: str) -> Union[Request, None]:
    """alarabiya uses an interstitial that requires JavaScript. If the download URL matches alarabiya and returns the
    'requires JavaScript' page, manually parse out the necessary cookie and add it to the $ua so that the request will
    work."""

    content = decode_object_from_bytes_if_needed(content)
    archive_site_url = decode_object_from_bytes_if_needed(archive_site_url)

    if not is_http_url(archive_site_url):
        log.error("Archive site URL is not HTTP(s): %s" % archive_site_url)
        return None

    if content is None:
        return None

    if not re.search(pattern='alarabiya', string=archive_site_url, flags=re.IGNORECASE):
        return None

    if not re.search(pattern='This site requires JavaScript and Cookies to be enabled',
                     string=content,
                     flags=re.IGNORECASE):
        return None

    matches = re.search(pattern=r"setCookie\('(?P<cookie_name>[^']+)', '(?P<cookie_value>[^']+)'",
                        string=content,
                        flags=re.IGNORECASE)
    if matches:
        cookie_name = matches.group('cookie_name')
        cookie_value = matches.group('cookie_value')

        request = Request(method='GET', url=archive_site_url)
        request.set_header(name='Cookie', value="%s=%s" % (cookie_name, cookie_value,))
        return request

    else:
        log.warning("Unable to parse cookie from alarabiya URL %s: %s" % (archive_site_url, content,))

    return None
