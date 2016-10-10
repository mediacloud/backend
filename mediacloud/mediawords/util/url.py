import re
from urllib.parse import urlparse

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_string_from_bytes_if_needed

l = create_logger(__name__)


# URL regex (http://stackoverflow.com/a/7160778/200603)
__URL_REGEX = re.compile(
    r'^(?:http|ftp)s?://'  # http:// or https://
    r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+(?:[A-Z]{2,6}\.?|[A-Z0-9-]{2,}\.?)|'  # domain...
    r'localhost|'  # localhost...
    r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'  # ...or ip
    r'(?::\d+)?'  # optional port
    r'(?:/?|[/?]\S+)$', re.IGNORECASE)


def fix_common_url_mistakes(url):
    """Fixes common URL mistakes (mistypes, etc.)."""
    url = decode_string_from_bytes_if_needed(url)

    if url is None:
        return None

    # Fix broken URLs that look like this: http://http://www.al-monitor.com/pulse
    url = re.sub(r'(https?://)https?:?//', r"\1", url, flags=re.I)

    # Fix URLs with only one slash after "http" ("http:/www.")
    url = re.sub(r'(https?:/)(www)', r"\1/\2", url, flags=re.I)

    # replace backslashes with forward
    url = re.sub(r'\\', r'/', url)

    # http://newsmachete.com?page=2 -> http://newsmachete.com/?page=2
    url = re.sub(r'(https?://[^/]+)\?', r"\1/?", url)

    return url


def is_http_url(url):
    """Returns true if URL is in the "http" ("https") scheme."""
    url = decode_string_from_bytes_if_needed(url)
    if url is None:
        l.debug("URL is None")
        return False
    if len(url) == 0:
        l.debug("URL is empty")
        return False
    if not re.search(__URL_REGEX, url):
        l.debug("URL '%s' does not match URL's regexp" % url)
        return False

    uri = urlparse(url)

    if not uri.scheme:
        l.debug("Scheme is undefined for URL %s" % url)
        return False
    if not uri.scheme.lower() in ['http', 'https']:
        l.debug("Scheme is not HTTP(s) for URL %s" % url)
        return False

    return True
