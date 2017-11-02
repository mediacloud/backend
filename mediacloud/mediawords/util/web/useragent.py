import errno
import fcntl
from furl import furl
from http import HTTPStatus
import os
import re
import requests
from requests.adapters import HTTPAdapter
from requests.auth import HTTPBasicAuth
import time
from typing import Dict, List, Union
from urllib3 import Retry
from urllib.parse import quote

from mediawords.util.config import get_config as py_get_config
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sql import sql_now
from mediawords.util.url import fix_common_url_mistakes, is_http_url, get_url_distinctive_domain, canonical_url
from mediawords.util.web.ua.request import Request
from mediawords.util.web.ua.response import Response

log = create_logger(__name__)


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
    __DEFAULT_TIMEOUT = 20

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

        # Timeout
        '__timeout',

        # Max. data size
        '__max_size',

        # Delays between retries
        '__timing',

    ]

    def __init__(self):
        """Constructor."""

        # "requests" session to carry the cookie pool around
        self.__session = requests.Session()

        config = py_get_config()
        self.__session.headers.update({
            'From': config['mediawords']['owner'],
            'User-Agent': config['mediawords']['user_agent'],
            'Accept-Charset': 'utf-8',
        })

        self.set_max_redirect(self.__DEFAULT_MAX_REDIRECT)

        self.__timeout = None
        self.set_timeout(self.__DEFAULT_TIMEOUT)

        self.__max_size = None
        self.set_max_size(self.__DEFAULT_MAX_SIZE)

        # Disable retries by default; if client wants those, it should call
        # timing() itself, e.g. set it to '1,2,4,8'
        self.__timing = None
        self.set_timing(None)

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
        """If there are HTTP auth credentials for the requested site, add them to the URL."""
        url = decode_object_from_bytes_if_needed(url)

        auth_lookup = UserAgent.__get_domain_http_auth_lookup()

        domain = get_url_distinctive_domain(url=url).lower()

        if domain in auth_lookup:
            auth = auth_lookup[domain]
            uri = furl(url)

            # https://stackoverflow.com/a/21629125/200603
            uri.username = auth['user']
            uri.password = auth['password']

            url = uri.url

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

        request = Request(method='GET', url=url)

        return self.request(request)

    def __get_follow_http_html_redirects_inner_follow_redirects(self,
                                                                response: Response,
                                                                meta_redirects_left: int) -> Union[Response, None]:

        from mediawords.util.web.ua.html_redirects import (
            target_request_from_meta_refresh_url,
            target_request_from_archive_org_url,
            target_request_from_archive_is_url,
            target_request_from_linkis_com_url,
            target_request_from_alarabiya_url,
        )

        if response is None:
            raise McGetFollowHTTPHTMLRedirectsException("Response is None.")

        if response.is_success():

            # Check if the returned document contains <meta http-equiv="refresh" />
            base_uri = furl(canonical_url(response.request().url()))
            if response.request().url().endswith('/'):
                # In "http://example.com/first/two" URLs, strip the "two" part (but not when it has a trailing slash)
                base_uri_path_segments = base_uri.path.segments
                del base_uri_path_segments[-1]
                # noinspection PyProtectedMember
                base_uri._replace(path='/' + '/'.join(base_uri_path_segments))

            base_url = base_uri.url

            html_redirect_functions = [
                target_request_from_meta_refresh_url,
                target_request_from_archive_org_url,
                target_request_from_archive_is_url,
                target_request_from_linkis_com_url,
                target_request_from_alarabiya_url,
            ]
            for html_redirect_function in html_redirect_functions:
                request_after_meta_redirect = html_redirect_function(
                    content=response.decoded_content(),
                    archive_site_url=base_url,
                )
                if request_after_meta_redirect is not None:
                    if response.request().url() != request_after_meta_redirect.url():

                        log.debug("URL after HTML redirects: %s" % request_after_meta_redirect.url())

                        orig_redirect_response = self.request(request=request_after_meta_redirect)
                        redirect_response = orig_redirect_response

                        # Response might have its previous() already set due to HTTP redirects,
                        # so we have to find the initial response first
                        previous = None
                        for x in range(self.max_redirect() + 1):
                            previous = redirect_response.previous()
                            if previous is None:
                                break
                            redirect_response = previous

                        if previous is not None:
                            raise McGetFollowHTTPHTMLRedirectsException(
                                "Can't find the initial redirected response; URL: %s" %
                                request_after_meta_redirect.url()
                            )

                        log.debug("Setting previous of URL %(url)s to %(previous_url)s" % {
                            'url': redirect_response.request().url(),
                            'previous_url': response.request().url(),
                        })
                        redirect_response.set_previous(response)

                        meta_redirects_left = meta_redirects_left - 1

                        return self.__get_follow_http_html_redirects_inner(
                            response=orig_redirect_response,
                            meta_redirects_left=meta_redirects_left,
                        )

            # No <meta /> refresh, the current URL is the final one
            return response

        else:
            log.debug("Request to %s was unsuccessful: %s" % (response.request().url(), response.status_line(),))

            # Return the original URL and give up
            return None

    def __get_follow_http_html_redirects_inner_redirects_exhausted(self,
                                                                   response: Response) -> Union[Response, None]:

        if response is None:
            raise McGetFollowHTTPHTMLRedirectsException("Response is None.")

        # If one of the URLs that we've been redirected to contains another encoded URL, assume
        # that we're hitting a paywall and the URLencoded URL is the right one
        urls_redirected_to = []

        for x in range(self.max_redirect() + 1):
            previous = response.previous()
            if previous is None:
                break

            url_redirected_to = previous.request().url()
            encoded_url_redirected_to = quote(url_redirected_to)

            for redir_url in urls_redirected_to:
                if re.search(pattern=re.escape(encoded_url_redirected_to),
                             string=redir_url,
                             flags=re.IGNORECASE | re.UNICODE):
                    log.debug("""
                        Encoded URL %(encoded_url_redirected_to)s is a substring of another URL %(matched_url)s, so I'll
                        assume that %(url_redirected_to)s is the correct one.
                    """ % {
                        'encoded_url_redirected_to': encoded_url_redirected_to,
                        'matched_url': redir_url,
                        'url_redirected_to': url_redirected_to,
                    })
                    return previous

            urls_redirected_to.append(url_redirected_to)

        # Return the original URL (unless we find a URL being a substring of another URL, see below)
        return None

    def __get_follow_http_html_redirects_inner(self,
                                               response: Response,
                                               meta_redirects_left: int) -> Union[Response, None]:

        if response is None:
            raise McGetFollowHTTPHTMLRedirectsException("Response is None.")

        if meta_redirects_left > 0:
            return self.__get_follow_http_html_redirects_inner_follow_redirects(
                response=response,
                meta_redirects_left=meta_redirects_left,
            )

        else:
            return self.__get_follow_http_html_redirects_inner_redirects_exhausted(response=response)

    def get_follow_http_html_redirects(self, url: str) -> Response:
        """GET an URL while resolving HTTP / HTML redirects."""
        url = decode_object_from_bytes_if_needed(url)

        if url is None:
            raise McGetFollowHTTPHTMLRedirectsException("URL is None.")

        url = fix_common_url_mistakes(url)

        if not is_http_url(url):
            raise McGetFollowHTTPHTMLRedirectsException("URL is not HTTP(s): %s" % url)

        if self.max_redirect() == 0:
            raise McGetFollowHTTPHTMLRedirectsException(
                "User agent's max_redirect is 0, subroutine might loop indefinitely."
            )

        response = self.get(url)

        response_after_redirects = self.__get_follow_http_html_redirects_inner(
            response=response,
            meta_redirects_left=self.max_redirect()
        )
        if response_after_redirects is None:
            # One of the redirects failed -- return original response
            return response

        else:
            return response_after_redirects

    def parallel_get(self, urls: List[str]) -> List[Response]:
        """GET multiple URLs in parallel."""
        # FIXME per-domain limit?
        # FIXME is "timeout" being used?
        # FIXME is "per_domain_timeout" being used?

        urls = decode_object_from_bytes_if_needed(urls)

        # Original implementation didn't raise on undefined / empty list of URLs
        if urls is None:
            return []
        if len(urls) == 0:
            return []

        config = py_get_config()

        num_parallel = config['mediawords'].get(['web_store_num_parallel'], None)
        if num_parallel is None:
            raise McParallelGetException('"web_store_num_parallel" is not set.')

        timeout = config['mediawords'].get('web_store_timeout', None)
        if timeout is None:
            raise McParallelGetException('"web_store_timeout" is not set.')

        per_domain_timeout = config['mediawords'].get('web_store_per_domain_timeout', None)
        if per_domain_timeout is None:
            raise McParallelGetException('"web_store_per_domain_timeout" is not set.')

        # FIXME
        raise NotImplementedError

    def get_string(self, url: str) -> Union[str, None]:
        """Return URL content as string, None on error."""

        response = self.get(url=url)
        if response.is_success():
            return response.decoded_content()
        else:
            return None

    @staticmethod
    def __blacklist_request_if_needed(request: Request) -> Request:
        """If request's URL is blacklisted, update the request to point to a blacklisted URL."""
        # FIXME there should be a better way to block those unwanted requests

        if request is None:
            raise McRequestException("Request is None.")

        url = request.url()
        if url is None:
            raise McRequestException("URL is None.")
        if len(url) == 0:
            raise McRequestException("URL is empty.")

        config = py_get_config()

        blacklist_url_pattern = None
        if 'blacklist_url_pattern' in config['mediawords']:
            blacklist_url_pattern = config['mediawords']['blacklist_url_pattern']

        if blacklist_url_pattern is not None and len(blacklist_url_pattern) > 0:
            if re.search(pattern=blacklist_url_pattern, string=url, flags=re.IGNORECASE | re.UNICODE):
                request.set_url("http://blacklistedsite.localhost/%s" % url)

        return request

    @staticmethod
    def __log_request(request: Request) -> None:
        """Log HTTP request."""
        # FIXME use Python's logging facilities

        if request is None:
            raise McRequestException("Request is None.")

        url = request.url()
        if url is None:
            raise McRequestException("URL is None.")
        if len(url) == 0:
            raise McRequestException("URL is empty.")

        config = py_get_config()

        http_request_log_path = os.path.join(config['mediawords']['data_dir'], 'logs', 'http_request.log')

        with open(http_request_log_path, 'a') as f:

            while True:
                try:
                    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except IOError as e:
                    # raise on unrelated IOErrors
                    if e.errno != errno.EAGAIN:
                        raise
                    else:
                        log.warning("Waiting for HTTP request log lock...")
                        time.sleep(0.1)

            f.write("%s %s\n" % (sql_now(), url,))

            # Doesn't write "invalidating blacklist url <...> because it's apparent from the URL itself

            fcntl.flock(f, fcntl.LOCK_UN)

        # Processes from various users (web service, workers, ...) will want to write to the same file
        os.chmod(http_request_log_path, 0o666)

    def request(self, request: Request) -> Response:
        """Execute a request, return a response.

        All other helpers are supposed to use request() internally as it implements max. size, callbacks, blacklisted
        URLs etc."""

        if request is None:
            raise McRequestException("Request is None.")

        request = self.__blacklist_request_if_needed(request=request)

        self.__log_request(request=request)

        method = request.method()
        if method is None:
            raise McRequestException("Request's method is None.")

        url = request.url()
        if url is None:
            raise McRequestException("Request's URL is None.")

        headers = request.headers()
        if headers is None:
            raise McRequestException("Request's headers is None.")

        auth_username = request.auth_username()
        auth_password = request.auth_password()
        if ((auth_username is None and auth_password is not None) or
                (auth_username is not None and auth_password is None)):
            raise McRequestException("Either both or none of HTTP authentication credentials must be not None.")

        auth = None
        if auth_username is not None and auth_password is not None:
            if ((len(auth_username) == 0 and len(auth_password) > 0) or
                    (len(auth_username) > 0 and len(auth_password) == 0)):
                raise McRequestException("Either both or none of HTTP authentication credentials must be not Empty.")

            auth = HTTPBasicAuth(auth_username, auth_password)

        data = request.content()

        try:
            requests_response = self.__session.request(
                method=method,
                url=url,
                data=data,
                headers=headers,
                auth=auth,
                timeout=self.timeout(),

                # To be able to enforce max_size
                stream=True,
            )

        except Exception as ex:

            # Client-side error
            error = str(ex)
            log.warning("Client-side error while processing request %s: %s" % (str(request), error,))
            response = Response(
                code=HTTPStatus.BAD_REQUEST.value,
                message="Client-side error",
                headers={
                    # LWP::UserAgent compatibility
                    'Client-Warning': 'Client-side error',
                },
                data=error,
            )
            response.set_error_is_client_side(True)

        else:

            if requests_response is None:
                raise McRequestException("Response from 'requests' is None.")

            data = ""
            data_size = 0
            chunk_size = 1024 * 10
            max_size = self.max_size()
            for chunk in requests_response.iter_content(chunk_size=chunk_size, decode_unicode=True):
                data += chunk
                data_size += len(chunk)
                if max_size is not None:
                    if data_size > max_size:
                        log.warning("Data size exceeds %d for URL %s" % (max_size, url,))
                        break

            response = Response(
                code=requests_response.status_code,
                message=requests_response.reason,
                headers=requests_response.headers,
                data=data,
            )

        response.set_request(request)

        return response

    def timing(self) -> Union[List[int], None]:
        """Return list of integer seconds; if None, retries are disabled."""
        return self.__timing

    def set_timing(self, timing: Union[List[int], None]) -> None:
        """Set list of integer seconds; if None, retries are disabled."""
        timing = decode_object_from_bytes_if_needed(timing)
        if timing is not None:
            if not isinstance(timing, list):
                raise McUserAgentException("Timing must be a list of integer seconds.")

            if len(timing) == 0:
                timing = None

        self.__timing = timing

        http_prefixes = ['http://', 'https://']

        if timing is None:
            # Disable retries
            for http_prefix in http_prefixes:
                self.__session.mount(prefix=http_prefix, adapter=HTTPAdapter())

        else:
            # Enable retries

            # Doesn't really implement "timing" as LWP::UserAgent::Determined did, simply assumes that
            # "[1, 2, 4, 8, ...]" timing value means that we want a back-off factor of 2-1 = 1 second.
            if len(timing) == 1:
                backoff_factor = timing[0]
            else:
                backoff_factor = timing[1] - timing[0]

            retries = Retry(
                total=len(timing),
                backoff_factor=backoff_factor,
                status_forcelist=self.__DETERMINED_HTTP_CODES,
            )
            for http_prefix in http_prefixes:
                self.__session.mount(prefix=http_prefix, adapter=HTTPAdapter(max_retries=retries))

    def timeout(self) -> int:
        """Return timeout."""
        return self.__timeout

    def set_timeout(self, timeout: int) -> None:
        """Set timeout."""
        if isinstance(timeout, bytes):
            timeout = decode_object_from_bytes_if_needed(timeout)
        timeout = int(timeout)
        if timeout <= 0:
            raise McUserAgentException("Timeout is zero or negative.")
        self.__timeout = timeout

    def max_redirect(self) -> int:
        """Return max. number of redirects."""
        return self.__session.max_redirects

    def set_max_redirect(self, max_redirect: int) -> None:
        """Set max. number of redirects."""
        if isinstance(max_redirect, bytes):
            max_redirect = decode_object_from_bytes_if_needed(max_redirect)
        max_redirect = int(max_redirect)
        if max_redirect < 0:
            raise McUserAgentException("Max. redirect count is negative.")
        self.__session.max_redirects = max_redirect

    def max_size(self) -> int:
        """Return max. download size."""
        return self.__max_size

    def set_max_size(self, max_size: int) -> None:
        """Set max. download size."""
        if isinstance(max_size, bytes):
            max_size = decode_object_from_bytes_if_needed(max_size)
        max_size = int(max_size)
        if max_size <= 0:
            raise McUserAgentException("Max. size is zero or negative.")
        self.__max_size = max_size
