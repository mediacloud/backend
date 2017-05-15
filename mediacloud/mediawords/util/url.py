import re
from typing import Optional
from urllib.parse import urlparse, parse_qs, urlsplit, urlunsplit, urlencode, urljoin
import url_normalize

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.url_shorteners import URL_SHORTENER_HOSTNAMES

l = create_logger(__name__)

# URL regex (http://stackoverflow.com/a/7160778/200603)
__URL_REGEX = re.compile(
    r'^(?:http|ftp)s?://'  # http:// or https://
    r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+(?:[A-Z]{2,6}\.?|[A-Z0-9-]{2,}\.?)|'  # domain...
    r'localhost|'  # localhost...
    r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'  # ...or ip
    r'(?::\d+)?'  # optional port
    r'(?:/?|[/?]\S+)$', re.IGNORECASE)

# Regular expressions for URL's path that, when matched, mean that the URL is a homepage URL
__HOMEPAGE_URL_PATH_REGEXES = [

    # Empty path (e.g. http://www.nytimes.com)
    re.compile(r'^$', re.I),

    # One or more slash (e.g. http://www.nytimes.com/, http://m.wired.com///)
    re.compile(r'^/+$', re.I),

    # Limited number of either all-lowercase or all-uppercase (but not both)
    # characters and no numbers, e.g.:
    #
    # * /en/,
    # * /US
    # * /global/,
    # * /trends/explore
    #
    # but not:
    #
    # * /oKyFAMiZMbU
    # * /1uSjCJp
    re.compile(r'^[a-z/\-_]{1,18}/?$'),
    re.compile(r'^[A-Z/\-_]{1,18}/?$'),
]


# noinspection SpellCheckingInspection
def fix_common_url_mistakes(url: str) -> Optional[str]:
    """Fixes common URL mistakes (mistypes, etc.)."""
    url = decode_object_from_bytes_if_needed(url)

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


def is_http_url(url: str) -> bool:
    """Returns true if URL is in the "http" ("https") scheme."""
    url = decode_object_from_bytes_if_needed(url)
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


def __canonical_url(url: str) -> str:
    """Make URL canonical (lowercase scheme and host, remove default port, etc.)"""
    return url_normalize.url_normalize(url)


class McNormalizeURLException(Exception):
    pass


# noinspection SpellCheckingInspection
def normalize_url(url: str) -> str:
    """Normalize URL

    * Fix common mistypes, e.g. "http://http://..."
    * Run URL through normalization, i.e. standardize URL's scheme and hostname case, remove default port, uppercase
      all escape sequences, un-escape octets that can be represented as plain characters, remove whitespace before /
      after the URL string)
    * Remove #fragment
    * Remove various ad tracking query parameters, e.g. "utm_source", "utm_medium", "PHPSESSID", etc.

    Return normalized URL on success; raise on error"""
    url = decode_object_from_bytes_if_needed(url)
    if url is None:
        raise McNormalizeURLException("URL is None")
    if len(url) == 0:
        raise McNormalizeURLException("URL is empty")

    url = fix_common_url_mistakes(url)
    url = __canonical_url(url)

    if not is_http_url(url):
        raise McNormalizeURLException("URL is not valid")

    scheme, netloc, path, query_string, fragment = urlsplit(url)
    query = parse_qs(query_string, keep_blank_values=True)

    # Remove #fragment
    fragment = ''

    parameters_to_remove = []

    # Facebook parameters (https://developers.facebook.com/docs/games/canvas/referral-tracking)
    parameters_to_remove += [
        'fb_action_ids',
        'fb_action_types',
        'fb_source',
        'fb_ref',
        'action_object_map',
        'action_type_map',
        'action_ref_map',
        'fsrc_fb_noscript',
    ]

    # metrika.yandex.ru parameters
    parameters_to_remove += [
        'yclid',
        '_openstat',
    ]

    if 'facebook.com' in netloc.lower():
        # Additional parameters specifically for the facebook.com host
        parameters_to_remove += [
            'ref',
            'fref',
            'hc_location',
        ]

    if 'nytimes.com' in netloc.lower():
        # Additional parameters specifically for the nytimes.com host
        parameters_to_remove += [
            'emc',
            'partner',
            '_r',
            'hp',
            'inline',
            'smid',
            'WT.z_sma',
            'bicmp',
            'bicmlukp',
            'bicmst',
            'bicmet',
            'abt',
            'abg',
        ]

    if 'livejournal.com' in netloc.lower():
        # Additional parameters specifically for the livejournal.com host
        parameters_to_remove += [
            'thread',
            'nojs',
        ]

    if 'google.' in netloc.lower():
        # Additional parameters specifically for the google.[com,lt,...] host
        parameters_to_remove += [
            'gws_rd',
            'ei',
        ]

    # Some other parameters (common for tracking session IDs, advertising, etc.)
    parameters_to_remove += [
        'PHPSESSID',
        'PHPSESSIONID',
        'cid',
        's_cid',
        'sid',
        'ncid',
        'ir',
        'ref',
        'oref',
        'eref',
        'ns_mchannel',
        'ns_campaign',
        'ITO',
        'wprss',
        'custom_click',
        'source',
        'feedName',
        'feedType',
        'skipmobile',
        'skip_mobile',
        'altcast_code',
    ]

    # Make the sorting default (e.g. on Reddit)
    # Some other parameters (common for tracking session IDs, advertising, etc.)
    parameters_to_remove += ['sort']

    # Some Australian websites append the "nk" parameter with a tracking hash
    if 'nk' in query:
        for nk_value in query['nk']:
            if re.search(r'^[0-9a-fA-F]+$', nk_value, re.I):
                parameters_to_remove += ['nk']
                break

    # Delete the "empty" parameter (e.g. in http://www-nc.nytimes.com/2011/06/29/us/politics/29marriage.html?=_r%3D6)
    parameters_to_remove += ['']

    # Remove cruft parameters
    for parameter in parameters_to_remove:
        if ' ' in parameter:
            l.warning('Invalid cruft parameter "%s"' % parameter)
        query.pop(parameter, None)

    for name in list(query.keys()):  # copy of list to be able to delete

        # Remove parameters that start with '_' (e.g. '_cid') because they're
        # more likely to be the tracking codes
        if name.startswith('_'):
            query.pop(name)

        # Remove GA parameters, current and future (e.g. "utm_source",
        # "utm_medium", "ga_source", "ga_medium")
        # (https://support.google.com/analytics/answer/1033867?hl=en)
        if name.startswith('ga_') or name.startswith('utm_'):
            query.pop(name)

    url = urlunsplit((scheme, netloc, path, urlencode(query, doseq=True), fragment))

    # Remove empty values in query string, e.g. http://bash.org/?244321=
    url = url.replace('=&', '&')
    url = re.sub(r'=$', '', url)

    return url


# noinspection SpellCheckingInspection
def normalize_url_lossy(url: str) -> Optional[str]:
    """Do some simple transformations on a URL to make it match other equivalent URLs as well as possible; normalization
    is "lossy" (makes the whole URL lowercase, removes subdomain parts "m.", "data.", "news.", ... in some cases)"""
    url = decode_object_from_bytes_if_needed(url)
    if url is None:
        return None
    if len(url) == 0:
        return None

    url = fix_common_url_mistakes(url)

    url = url.lower()

    # r2.ly redirects through the hostname, ala http://543.r2.ly
    if 'r2.ly' not in url:
        url = re.sub(
            r'^(https?://)(m|beta|media|data|image|www?|cdn|topic|article|news|archive|blog|video|search|preview|'
            + 'login|shop|sports?|act|donate|press|web|photos?|\d+?).?\.(.*\.)',
            r"\1\3", url, re.I)

    # collapse the vast array of http://pronkraymond83483.podomatic.com/ urls into http://pronkpops.podomatic.com/
    url = re.sub(r'http://.*pron.*\.podomatic\.com', 'http://pronkpops.podomatic.com', url)

    # get rid of anchor text
    url = re.sub(r'#.*', '', url)

    # get rid of multiple slashes in a row
    url = re.sub(r'(//.*/)/+', r"\1", url)

    url = re.sub(r'^https:', 'http:', url)

    # canonical_url might raise an encoding error if url is not invalid; just skip the canonical url step in the case
    # noinspection PyBroadException
    try:
        url = __canonical_url(url)
    except:
        pass

    # add trailing slash
    if re.search(r'https?://[^/]*$', url):
        url += '/'

    return url


def __is_shortened_url(url: str) -> bool:
    """Returns true if URL is a shortened URL (e.g. with Bit.ly)."""
    url = decode_object_from_bytes_if_needed(url)
    if url is None:
        l.debug("URL is None")
        return False
    if len(url) == 0:
        l.debug("URL is empty")
        return False
    if not is_http_url(url):
        l.debug("URL is not valid")
        return False

    uri = urlparse(url)

    if uri.path is not None and uri.path in ['', '/']:
        # Assume that most of the URL shorteners use something like
        # bit.ly/abcdef, so if there's no path or if it's empty, it's not a
        # shortened URL
        return False

    uri_host = uri.hostname.lower()
    if uri_host in URL_SHORTENER_HOSTNAMES:
        return True

    return False


def is_homepage_url(url: str) -> bool:
    """Returns true if URL is homepage (e.g. http://www.wired.com/) and not a child page
    (e.g. http://m.wired.com/threatlevel/2011/12/sopa-watered-down-amendment/)."""
    url = decode_object_from_bytes_if_needed(url)
    if url is None:
        l.debug("URL is None.")
        return False
    if len(url) == 0:
        l.debug("URL is empty.")
        return False

    if not is_http_url(url):
        l.debug("URL '%s' is invalid." % url)
        return False

    # Remove cruft from the URL first
    try:
        url = normalize_url(url)
    except McNormalizeURLException as ex:
        l.debug("Unable to normalize URL '%s' before checking if it's a homepage: %s" % (url, ex))
        return False

    # The shortened URL may lead to a homepage URL, but the shortened URL
    # itself is not a homepage URL
    if __is_shortened_url(url):
        return False

    # If we still have something for a query of the URL after the
    # normalization, always assume that the URL is *not* a homepage
    scheme, netloc, uri_path, query_string, fragment = urlsplit(url)
    if len(query_string) > 0:
        return False

    for homepage_url_path_regex in __HOMEPAGE_URL_PATH_REGEXES:
        if re.search(homepage_url_path_regex, uri_path):
            return True

    return False


class McGetURLHostException(Exception):
    pass


def get_url_host(url: str) -> str:
    """Return hostname of an URL. If we can't parse out the host name, just return the URL."""
    url = decode_object_from_bytes_if_needed(url)
    if url is None:
        raise McGetURLHostException("URL is None")
    if len(url) == 0:
        raise McGetURLHostException("URL is empty")

    fixed_url = fix_common_url_mistakes(url)

    uri = urlparse(fixed_url)

    host = uri.hostname

    if host is not None and len(host) > 0:
        return host
    else:
        return url


# noinspection SpellCheckingInspection
def get_url_distinctive_domain(url: str) -> str:
    """Return a truncated form of URL's host (domain) that distinguishes it from others, e.g.:

    * www.whitehouse.gov => whitehouse.gov
    * www.blogspot.com => blogspot.com
    * kardashian.blogspot.com => kardashian.blogspot.com

    Return original URL if unable to process the URL."""

    try:
        url = decode_object_from_bytes_if_needed(url)

        url = fix_common_url_mistakes(url)

        host = get_url_host(url)
        if host is None:
            return url

        name_parts = host.split('.')
        n = len(name_parts) - 1

        if re.search(r'\.(gov|org|com?)\...$', host, re.I):
            # foo.co.uk -> foo.co.uk instead of co.uk
            parts = [str(name_parts[n - 2]), str(name_parts[n - 1]), str(name_parts[n])]
            domain = '.'.join(parts)
        elif re.search(r'\.(edu|gov)$', host, re.I):
            parts = [str(name_parts[n - 2]), str(name_parts[n - 1])]
            domain = '.'.join(parts)
        elif re.search(
                        r'go.com|wordpress.com|blogspot|livejournal.com|privet.ru|wikia.com|feedburner.com'
                        + '|24open.ru|patch.com|tumblr.com', host, re.I
        ):
            # identify sites in these domains as the whole host name (abcnews.go.com instead of go.com)
            domain = host
        else:
            parts = [str(name_parts[n - 1] or ''), str(name_parts[n] or '')]
            domain = '.'.join(parts)

        return domain.lower()

    except Exception as ex:
        l.debug("get_url_distinctive_domain falling back to url: " + str(ex))
        return url.lower()


def meta_refresh_url_from_html(html: str, base_url: str = None) -> Optional[str]:
    """From the provided HTML, determine the <meta http-equiv="refresh" /> URL (if any)."""

    def __get_meta_refresh_url_from_tag(inner_tag: str, inner_base_url=None) -> Optional[str]:
        """Given a <meta ...> tag, return the url from the content="url=XXX" attribute.  return undef if no such url is
        found."""
        if not re.search(r'http-equiv\s*?=\s*?["\']\s*?refresh\s*?["\']', inner_tag, re.I):
            return None

        # content="url='http://foo.bar'"
        inner_url = None

        match = re.search(r'content\s*?=\s*?"\d*?\s*?;?\s*?URL\s*?=\s*?\'(.+?)\'', inner_tag, re.I)
        if match:
            inner_url = match.group(1)
        else:
            # content="url='http://foo.bar'"
            match = re.search(r'content\s*?=\s*?\'\d*?\s*?;?\s*?URL\s*?=\s*?"(.+?)"', inner_tag, re.I)
            if match:
                inner_url = match.group(1)
            else:
                # Fallback
                match = re.search(r'content\s*?=\s*?["\']\d*?\s*?;?\s*?URL\s*?=\s*?(.+?)["\']', inner_tag, re.I)
                if match:
                    inner_url = match.group(1)

        if is_http_url(inner_url):
            return inner_url

        if inner_base_url is not None:
            return urljoin(base=inner_base_url, url=inner_url)

        return None

    html = decode_object_from_bytes_if_needed(html)
    base_url = decode_object_from_bytes_if_needed(base_url)

    tags = re.findall(r'(<\s*meta[^>]+>)', html, re.I)
    for tag in tags:
        url = __get_meta_refresh_url_from_tag(tag, base_url)
        if url is not None:
            return url

    return None


def link_canonical_url_from_html(html: str, base_url: str = None) -> Optional[str]:
    """From the provided HTML, determine the <link rel="canonical" /> URL (if any)."""
    html = decode_object_from_bytes_if_needed(html)
    base_url = decode_object_from_bytes_if_needed(base_url)

    link_elements = re.findall(r'(<\s*?link.+?>)', html, re.I)
    for link_element in link_elements:
        if re.search(r'rel\s*?=\s*?["\']\s*?canonical\s*?["\']', link_element, re.I):
            url = re.search(r'href\s*?=\s*?["\'](.+?)["\']', link_element, re.I)
            if url:
                url = url.group(1)
                if not re.search(__URL_REGEX, url):
                    # Maybe it's absolute path?
                    if base_url is not None:
                        return urljoin(base=base_url, url=url)
                    else:
                        l.debug("HTML <link rel=\"canonical\"/> found, but the new URL '%s' doesn't seem to be valid."
                                % url)
                else:
                    # Looks like URL, so return it
                    return url
    return None


class McHTTPURLsInStringException(Exception):
    pass


# MC_REWRITE_TO_PYTHON: Perl doesn't support sets, but this method should return a set
def http_urls_in_string(string: str) -> list:
    """Extract http(s):// URLs from a string.

    Returns a set of unique URLs in a string, raises HTTPURLsInStringException on error."""
    string = decode_object_from_bytes_if_needed(string)
    if string is None:
        raise McHTTPURLsInStringException("String is None")
    if len(string) == 0:
        raise McHTTPURLsInStringException("String is empty")

    urls = re.findall(r'http[s]?://(?:[a-zA-Z]|[0-9]|[$-_@.&+]|[!*(),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+', string, re.I)
    http_urls = []
    for url in urls:
        if is_http_url(url):
            http_urls.append(url)

    # Unique URLs
    http_urls = list(set(http_urls))

    return http_urls


def get_url_path_fast(url: str) -> str:
    """Return URLs path."""
    url = decode_object_from_bytes_if_needed(url)

    if not is_http_url(url):
        return ''

    # Don't bother with the regex (Perl's version didn't work anyway)
    uri = urlparse(url)
    return uri.path
