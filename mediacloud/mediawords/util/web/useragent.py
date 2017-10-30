import requests
from http import HTTPStatus
from urllib.parse import urlparse
from typing import Dict, List, Union

from mediawords.util.config import get_config as py_get_config
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.url import fix_common_url_mistakes, is_http_url, get_url_distinctive_domain
from mediawords.util.web.ua.request import Request
from mediawords.util.web.ua.response import Response


class McUserAgentException(Exception):
    """UserAgent exception."""
    pass


class McCrawlerAuthenticatedDomainsException(McUserAgentException):
    """crawler_authenticated_domains exception."""
    pass


class McGetException(McUserAgentException):
    """get() exception."""
    pass


class McGetFollowHTTPHTMLRedirectsException(McUserAgentException):
    """get_follow_http_html_redirects() exception."""
    pass


class McParallelGetException(McUserAgentException):
    """parallel_get() exception."""
    pass


class McRequestException(McUserAgentException):
    """request() exception."""
    pass


class UserAgent(object):
    """Class for downloading stuff from the web."""

    __DEFAULT_MAX_SIZE = 10 * 1024 * 1024  # Superglue (TV) feeds could grow big
    __DEFAULT_MAX_REDIRECT = 15
    __TIMEOUT = 20

    # On which HTTP codes should requests be retried (if retrying is enabled)
    __DETERMINED_HTTP_CODES = {
        HTTPStatus.REQUEST_TIMEOUT.value,
        HTTPStatus.INTERNAL_SERVER_ERROR.value,
        HTTPStatus.BAD_GATEWAY.value,
        HTTPStatus.SERVICE_UNAVAILABLE.value,
        HTTPStatus.GATEWAY_TIMEOUT.value,
        HTTPStatus.TOO_MANY_REQUESTS.value,
    }

    __slots__ = [

        # "requests" session
        '__session',

    ]

    def __init__(self):
        """Constructor."""

        self.__session = requests.Session()

        config = py_get_config()
        self.__session.headers.update({
            'From': config['mediawords']['owner'],
            'User-Agent': config['mediawords']['user_agent'],
            'Accept-Charset': 'utf-8',
        })

        self.__session.max_redirects = self.__DEFAULT_MAX_REDIRECT

        # FIXME:
        # $ua->timeout( $TIMEOUT );
        # $ua->max_size( $DEFAULT_MAX_SIZE );

        # FIXME:
        # $ua->add_handler( request_prepare => \&_lwp_request_callback );

        # FIXME:
        # # Disable retries by default; if client wants those, it should call
        # # timing() itself, e.g. set it to '1,2,4,8'
        # $ua->timing('');

        # FIXME:
        # my %http_codes_hr = map { $_ => 1 } @DETERMINED_HTTP_CODES;
        # $ua->codes_to_determinate( \%http_codes_hr );

        # FIXME:
        # # Callbacks won't be called if timing() is unset
        # $ua->before_determined_callback( ... )
        # $ua->after_determined_callback( ... )

    @staticmethod
    def __get_domain_http_auth_lookup() -> Dict[str, Dict[str, str]]:
        """Read the mediawords.crawler_authenticated_domains list from mediawords.yml and generate a lookup hash with
        the host domain as the key and the user:password credentials as the value."""
        config = py_get_config()
        domain_http_auth_lookup = {}

        domains = None
        if 'crawler_authenticated_domains' in config['mediawords']:
            domains = config['mediawords']['crawler_authenticated_domains']

        if domains is not None:
            for domain in domains:

                if 'domain' not in domain:
                    raise McCrawlerAuthenticatedDomainsException(
                        '"domain" is not present in HTTP auth configuration.'
                    )
                if 'user' not in domain:
                    raise McCrawlerAuthenticatedDomainsException(
                        '"user" is not present in HTTP auth configuration.'
                    )
                if 'password' not in domain:
                    raise McCrawlerAuthenticatedDomainsException(
                        '"password" is not present in HTTP auth configuration.'
                    )

                domain_http_auth_lookup[domain['domain'].lower()] = domain

        return domain_http_auth_lookup

    @staticmethod
    def __url_with_http_auth(url: str) -> str:
        """If there are http auth credentials for the requested site, add them to the URL."""
        url = decode_object_from_bytes_if_needed(url)

        auth_lookup = UserAgent.__get_domain_http_auth_lookup()

        domain = get_url_distinctive_domain(url=url).lower()

        if domain in auth_lookup.items():
            auth = auth_lookup[domain]
            uri = urlparse(url)

            # https://stackoverflow.com/a/21629125/200603
            # noinspection PyProtectedMember
            uri._replace(username=auth['user'])
            # noinspection PyProtectedMember
            uri._replace(password=auth['password'])

            url = uri.geturl()

        return url

    def get(self, url: str) -> Response:
        """GET an URL."""
        url = decode_object_from_bytes_if_needed(url)

        if url is None:
            raise McGetException("URL is None.")

        url = fix_common_url_mistakes(url)

        if not is_http_url(url):
            raise McGetException("URL is not HTTP(s): %s" % url)

        # Add HTTP authentication
        url = self.__url_with_http_auth(url=url)

        # FIXME
        raise NotImplementedError

    def get_follow_http_html_redirects(self, url: str) -> Response:
        """GET an URL while resolving HTTP / HTML redirects."""
        # FIXME
        raise NotImplementedError

    def parallel_get(self, urls: List[str]) -> List[Response]:
        """GET multiple URLs in parallel."""
        # FIXME
        raise NotImplementedError

    def get_string(self, url: str) -> Union[str, None]:
        """Return URL content as string, None on error."""

        response = self.get(url=url)
        if response.is_success():
            return response.decoded_content()
        else:
            return None

    def request(self, request: Request) -> Response:
        """Execute a request, return a response."""
        # FIXME
        raise NotImplementedError

    def timing(self) -> Union[List[int], None]:
        """Return list of integer seconds; if None, retries are disabled."""
        # FIXME
        raise NotImplementedError

    def set_timing(self, timing: Union[List[int], None]) -> None:
        """Set list of integer seconds; if None, retries are disabled."""
        # FIXME
        raise NotImplementedError

    def timeout(self) -> int:
        """Return timeout."""
        # FIXME
        raise NotImplementedError

    def set_timeout(self, timeout: int) -> None:
        """Set timeout."""
        if timeout <= 0:
            raise McUserAgentException("Timeout is zero or negative.")
        # FIXME
        raise NotImplementedError

    def max_redirect(self) -> int:
        """Return max. number of redirects."""
        # FIXME
        raise NotImplementedError

    def set_max_redirect(self, max_redirect: int) -> None:
        """Set max. number of redirects."""
        if max_redirect < 0:
            raise McUserAgentException("Max. redirect count is negative.")
        raise NotImplementedError

    def max_size(self) -> int:
        """Return max. download size."""
        # FIXME
        raise NotImplementedError

    def set_max_size(self, max_size: int) -> None:
        """Set max. download size."""
        if max_size <= 0:
            raise McUserAgentException("Max. size is zero or negative.")
        raise NotImplementedError
