from furl import furl
import re
from typing import Optional
import url_normalize

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.url.shorteners import URL_SHORTENER_HOSTNAMES

log = create_logger(__name__)

__URL_REGEX = re.compile(r'^https?://[^\s/$.?#].[^\s]*$', re.IGNORECASE)

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


def fix_common_url_mistakes(url: str) -> Optional[str]:
    """Fixes common URL mistakes (mistypes, etc.)."""
    url = decode_object_from_bytes_if_needed(url)

    if url is None:
        return None

    # Remove whitespace
    url = url.strip()

    # Fix broken URLs that look like this: http://http://www.al-monitor.com/pulse
    url = re.sub(r'(https?://)https?:?//', r"\1", url, flags=re.I)

    # Fix URLs with only one slash after "http" ("http:/www.")
    url = re.sub(r'(https?:/)(www)', r"\1/\2", url, flags=re.I)

    # replace backslashes with forward
    url = re.sub(r'\\', r'/', url)

    # Add missing port, e.g. "https://www.gpo.gov:/fdsys/pkg/PL<...>"
    # (is_http_url() returns False on URLs with an empty port but "requests" manages to fetch them just fine, so let's
    # fix it here)
    url = re.sub(r'^(https?://[\w\d\-.]+):($|/)', r"\1\2", url, flags=re.I)

    # http://newsmachete.com?page=2 -> http://newsmachete.com/?page=2
    url = re.sub(r'(https?://[^/]+)\?', r"\1/?", url)

    # URLencode spaces
    url = re.sub(r' ', r'%20', url)

    return url


def is_http_url(url: str) -> bool:
    """Returns true if URL is in the "http" ("https") scheme."""
    url = decode_object_from_bytes_if_needed(url)
    if url is None:
        log.debug("URL is None")
        return False
    if len(url) == 0:
        log.debug("URL is empty")
        return False

    log.debug("Testing if URL '%s' is HTTP(s) URL" % url)

    if not re.search(__URL_REGEX, url):
        log.debug("URL '%s' does not match URL's regexp" % url)
        return False

    try:
        uri = furl(url)

        # Try stringifying URL back from the furl() object to try out all of its accessors
        str(uri)

        # Some URLs become invalid when normalized (which is what "requests" will do), e.g.:
        #
        #     http://michigan-state-football-sexual-assault-charges-arrest-players-names -- valid
        #     http://michigan-state-football-sexual-assault-charges-arrest-players-names/ -- invalid (decoding error)
        #
        # ...so try the same with normalized URL
        normalized_url = url_normalize.url_normalize(url)
        normalized_uri = furl(normalized_url)
        str(normalized_uri)

    except Exception as ex:
        log.debug("Cannot parse URL: %s" % str(ex))
        return False

    if not uri.scheme:
        log.debug("Scheme is undefined for URL %s" % url)
        return False
    if not uri.scheme.lower() in ['http', 'https']:
        log.debug("Scheme is not HTTP(s) for URL %s" % url)
        return False
    if not uri.host:
        log.debug("Host is undefined for URL %s" % url)
        return False

    return True


class McCanonicalURLException(Exception):
    """canonical_url() exception."""
    pass


def canonical_url(url: str) -> str:
    """Make URL canonical (lowercase scheme and host, remove default port, etc.)"""
    # FIXME maybe merge with normalize_url() as both do pretty much the same thing

    url = decode_object_from_bytes_if_needed(url)

    if url is None:
        raise McCanonicalURLException("URL is None.")
    if len(url) == 0:
        raise McCanonicalURLException("URL is empty.")

    url = fix_common_url_mistakes(url)

    if not is_http_url(url):
        raise McCanonicalURLException("URL is not HTTP(s): %s" % url)

    try:
        can_url = url_normalize.url_normalize(url)
    except Exception as ex:
        raise McCanonicalURLException("Failed to create canonical URL from URL %s: %s" % (url, str(ex),))

    return can_url


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

    log.debug("normalize_url: " + url)

    url = fix_common_url_mistakes(url)

    try:
        url = canonical_url(url)
    except Exception as ex:
        raise McNormalizeURLException("Unable to get canonical URL: %s" % str(ex))

    if not is_http_url(url):
        raise McNormalizeURLException("URL is not HTTP(s): %s" % url)

    uri = furl(url)

    # Remove #fragment
    uri.fragment.set(path='')

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

    if 'facebook.com' in uri.host.lower():
        # Additional parameters specifically for the facebook.com host
        parameters_to_remove += [
            'ref',
            'fref',
            'hc_location',
        ]

    if 'nytimes.com' in uri.host.lower():
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

    if 'livejournal.com' in uri.host.lower():
        # Additional parameters specifically for the livejournal.com host
        parameters_to_remove += [
            'thread',
            'nojs',
        ]

    if 'google.' in uri.host.lower():
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
    if 'nk' in uri.query.params:
        for nk_value in uri.query.params['nk']:
            if re.search(r'^[0-9a-fA-F]+$', nk_value, re.I):
                parameters_to_remove += ['nk']
                break

    # Delete the "empty" parameter (e.g. in http://www-nc.nytimes.com/2011/06/29/us/politics/29marriage.html?=_r%3D6)
    parameters_to_remove += ['']

    # Remove cruft parameters
    for parameter in parameters_to_remove:
        if ' ' in parameter:
            log.warning('Invalid cruft parameter "%s"' % parameter)
        uri.query.params.pop(parameter, None)

    for name in list(uri.query.params.keys()):  # copy of list to be able to delete

        # Remove parameters that start with '_' (e.g. '_cid') because they're
        # more likely to be the tracking codes
        if name.startswith('_'):
            uri.query.params.pop(name, None)

        # Remove GA parameters, current and future (e.g. "utm_source",
        # "utm_medium", "ga_source", "ga_medium")
        # (https://support.google.com/analytics/answer/1033867?hl=en)
        if name.startswith('ga_') or name.startswith('utm_'):
            uri.query.params.pop(name, None)

    url = uri.url

    # Remove empty values in query string, e.g. http://bash.org/?244321=
    url = url.replace('=&', '&')
    url = re.sub(r'=$', '', url)

    return url


# noinspection SpellCheckingInspection
def normalize_url_lossy(url: str) -> Optional[str]:
    """Do some simple transformations on a URL to make it match other equivalent URLs as well as possible.

    Normalization is "lossy" (makes the whole URL lowercase, removes subdomain parts "m.", "data.", "news.", ...
    in some cases).

    WARNING: You MUST set media.normalized_url = null for all possibly impacted media if you edit this
    function.  If in doubt, set normalized_url = null for all media.  See mediawords.tm.media.lookup_medium for
    more details.
    """
    url = decode_object_from_bytes_if_needed(url)

    if url is None:
        return None
    if len(url) == 0:
        return None

    url = fix_common_url_mistakes(url)

    url = url.lower()

    # make archive.is links look like the destination link
    url = re.sub(r'^https://archive.is/[a-z0-9]/[a-z0-9]+/(.*)', r'\1', url, flags=re.I)
    if not url.startswith('http'):
        url = 'http://' + url

    # r2.ly redirects through the hostname, ala http://543.r2.ly
    if 'r2.ly' not in url:
        url = re.sub(
            r'^(https?://)(m|beta|media|data|image|www?|cdn|topic|article|news|archive|blog|video|search|preview|'
            r'login|shop|sports?|act|donate|press|web|photos?|\d+?).?\.(.*\.)',
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
        url = url_normalize.url_normalize(url)
    except Exception as ex:
        log.warning("Unable to get canonical URL for URL %s: %s" % (url, str(ex),))

    # add trailing slash
    if re.search(r'https?://[^/]*$', url):
        url += '/'

    return url


def is_shortened_url(url: str) -> bool:
    """Returns true if URL is a shortened URL (e.g. with Bit.ly)."""
    url = decode_object_from_bytes_if_needed(url)
    if url is None:
        log.debug("URL is None")
        return False
    if len(url) == 0:
        log.debug("URL is empty")
        return False
    if not is_http_url(url):
        log.debug("URL is not HTTP(s): %s" % url)
        return False

    uri = furl(url)

    if str(uri.path) is not None and str(uri.path) in ['', '/']:
        # Assume that most of the URL shorteners use something like
        # bit.ly/abcdef, so if there's no path or if it's empty, it's not a
        # shortened URL
        return False

    uri_host = uri.host.lower()
    if uri_host in URL_SHORTENER_HOSTNAMES:
        return True

    # Otherwise match the typical https://wapo.st/4FGH5Re3 format
    if re.match(r'https?://[a-z]{1,4}\.[a-z]{2}/([a-z0-9]){3,12}/?$', url, flags=re.IGNORECASE) is not None:
        return True

    return False


def is_homepage_url(url: str) -> bool:
    """Returns true if URL is homepage (e.g. http://www.wired.com/) and not a child page
    (e.g. http://m.wired.com/threatlevel/2011/12/sopa-watered-down-amendment/)."""
    url = decode_object_from_bytes_if_needed(url)
    if url is None:
        log.debug("URL is None.")
        return False
    if len(url) == 0:
        log.debug("URL is empty.")
        return False

    url = fix_common_url_mistakes(url)

    if not is_http_url(url):
        log.debug("URL '%s' is invalid." % url)
        return False

    # Remove cruft from the URL first
    try:
        url = normalize_url(url)
    except McNormalizeURLException as ex:
        log.debug("Unable to normalize URL '%s' before checking if it's a homepage: %s" % (url, ex))
        return False

    # The shortened URL may lead to a homepage URL, but the shortened URL
    # itself is not a homepage URL
    if is_shortened_url(url):
        return False

    # If we still have something for a query of the URL after the
    # normalization, always assume that the URL is *not* a homepage
    uri = furl(url)
    if len(str(uri.query)) > 0:
        return False

    for homepage_url_path_regex in __HOMEPAGE_URL_PATH_REGEXES:
        if re.search(homepage_url_path_regex, str(uri.path)):
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

    url = fix_common_url_mistakes(url)

    if not is_http_url(url):
        return url

    uri = furl(url)

    host = uri.host

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
                r'|24open.ru|patch.com|tumblr.com', host, re.I
        ):
            # identify sites in these domains as the whole host name (abcnews.go.com instead of go.com)
            domain = host
        else:
            parts = [str(name_parts[n - 1] or ''), str(name_parts[n] or '')]
            domain = '.'.join(parts)

        return domain.lower()

    except Exception as ex:
        log.debug("get_url_distinctive_domain falling back to url: " + str(ex))
        return str(url).lower()


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
        log.warning("String is empty, no HTTP URLs here")
        return []

    urls = re.findall(r'http[s]?://(?:[a-zA-Z]|[0-9]|[$-_@.&+]|[!*(),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+', string, re.I)
    http_urls = []
    for url in urls:

        url = fix_common_url_mistakes(url)

        if is_http_url(url):
            http_urls.append(url)

    # Unique URLs
    http_urls = list(set(http_urls))

    return http_urls


def get_url_path_fast(url: str) -> str:
    """Return URLs path."""
    url = decode_object_from_bytes_if_needed(url)

    url = fix_common_url_mistakes(url)

    if not is_http_url(url):
        return ''

    # Don't bother with the regex (Perl's version didn't work anyway)
    uri = furl(url)
    return str(uri.path)


class McGetBaseURLException(Exception):
    pass


def get_base_url(url: str) -> str:
    """Return base URL, e.g. http://example.com/base/ for http://example.com/base/index.html."""
    # In "http://example.com/first/two" URLs, strip the "two" part, but not when it has a trailing slash

    url = decode_object_from_bytes_if_needed(url)

    if url is None:
        raise McGetBaseURLException("URL is None.")

    url = fix_common_url_mistakes(url)

    if not is_http_url(url):
        raise McGetBaseURLException("URL is not HTTP(S): %s" % url)

    if url.endswith('/'):
        base_url = url
    else:
        base_uri = furl(canonical_url(url))
        base_uri_path_segments = base_uri.path.segments
        del base_uri_path_segments[-1]
        base_url = base_uri.url + '/'

    return base_url


class McURLsAreEqualException(Exception):
    pass


def urls_are_equal(url1: str, url2: str) -> bool:
    """Returns True if (canonical) URLs are equal."""

    url1 = decode_object_from_bytes_if_needed(url1)
    url2 = decode_object_from_bytes_if_needed(url2)

    if url1 is None:
        raise McURLsAreEqualException("URL #1 is None.")
    if url2 is None:
        raise McURLsAreEqualException("URL #2 is None.")

    if len(url1) == 0:
        log.warning("URL #1 is empty.")
    if len(url2) == 0:
        log.warning("URL #2 is empty.")

    url1 = fix_common_url_mistakes(url1)
    url2 = fix_common_url_mistakes(url2)

    if not (is_http_url(url1) and is_http_url(url2)):
        log.warning("One or both of URLs is not a HTTP URL; URL #1: %s; URL #2: %s" % (url1, url2,))
        return False

    try:
        url1 = canonical_url(url1)
        url2 = canonical_url(url2)
    except McCanonicalURLException as ex:
        log.warning(
            "Unable to get canonical URL for one or both of URLs: %(exception)s; URL #1: %(url1)s; URL #2: %(url2)s" % {
                'exception': str(ex),
                'url1': str(url1),
                'url2': str(url2),
            })
        return False

    return url1 == url2
