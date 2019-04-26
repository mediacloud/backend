import multiprocessing
import io
import re
import time
from collections import OrderedDict
from http import HTTPStatus
from typing import Dict, List, Union
from urllib.parse import quote

import requests
from furl import furl
from requests.adapters import HTTPAdapter
from requests.auth import HTTPBasicAuth
from urllib3 import Retry, HTTPResponse

from mediawords.util.config.common import CommonConfig, UserAgentConfig, AuthenticatedDomain
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sql import sql_now
from mediawords.util.url import (
    fix_common_url_mistakes,
    is_http_url,
    get_url_distinctive_domain,
    get_url_host,
    get_base_url,
    urls_are_equal,
)
from mediawords.util.web.user_agent.request.request import Request
from mediawords.util.web.user_agent.response.response import Response

log = create_logger(__name__)

# On which HTTP codes should requests be retried (if retrying is enabled)
DETERMINED_HTTP_CODES = {
    HTTPStatus.REQUEST_TIMEOUT.value,
    HTTPStatus.INTERNAL_SERVER_ERROR.value,
    HTTPStatus.BAD_GATEWAY.value,
    HTTPStatus.SERVICE_UNAVAILABLE.value,
    HTTPStatus.GATEWAY_TIMEOUT.value,
    HTTPStatus.TOO_MANY_REQUESTS.value,
}


class McUserAgentException(Exception):
    """UserAgent exception."""
    pass


class McAuthenticatedDomainsException(McUserAgentException):
    """authenticated_domains exception."""
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


# In the module namespace because pickle is unable to serialize classes located in functions
class _ParallelGetScheduledURL(object):
    """URL scheduled to download in parallel_get()."""
    __slots__ = [
        'url',
        'time',
    ]

    def __init__(self, url: str, time_: float):
        self.url = url
        self.time = time_


# In the module namespace because pickle is unable to serialize classes located in functions
class _ParallelGetResponse(object):
    # Separate response object to keep the original requested URL intact (might be different in original_response())

    __slots__ = [
        'scheduled_url',
        'response',
    ]

    def __init__(self, scheduled_url: _ParallelGetScheduledURL, response: Response):
        self.scheduled_url = scheduled_url
        self.response = response


# In the module namespace because pickle is unable to serialize functions located in other functions
def _parallel_get_web_store(
        scheduled_urls: List[_ParallelGetScheduledURL],
        start_time: float,
        timeout: Union[int, None]
) -> List[_ParallelGetResponse]:
    """Download a list of URLs, return responses."""

    responses = []

    for scheduled_url in scheduled_urls:

        time_increment = time.time() - start_time
        if time_increment < scheduled_url.time:
            sleep_time = scheduled_url.time - time_increment
            time.sleep(sleep_time)

        ua = UserAgent()
        ua.set_timeout(timeout)

        response = ua.get_follow_http_html_redirects(url=scheduled_url.url)
        responses.append(_ParallelGetResponse(scheduled_url=scheduled_url, response=response))

    return responses


class UserAgent(object):
    """Class for downloading stuff from the web."""

    # Some feeds (especially the ones with full text content) could grow big
    __DEFAULT_MAX_SIZE = 10 * 1024 * 1024

    __DEFAULT_MAX_REDIRECT = 15
    __DEFAULT_TIMEOUT = 20

    # HTTP "From:" header
    __OWNER = 'mediawords@cyber.law.harvard.edu'

    # HTTP "User-Agent:" header
    __USER_AGENT = 'mediawords bot (http://cyber.law.harvard.edu)'

    __slots__ = [

        # User agent configuratio
        '_user_agent_config',

        # "requests" session
        '__session',

        # Timeout
        '__timeout',

        # Max. data size
        '__max_size',

        # Delays between retries
        '__timing',

    ]

    def __init__(self, user_agent_config: UserAgentConfig = None):
        """Constructor."""

        self._user_agent_config = user_agent_config
        if not self._user_agent_config:
            self._user_agent_config = CommonConfig.user_agent()

            # "requests" session to carry the cookie pool around
        self.__session = requests.Session()

        self.__session.headers.update({
            'From': self.__OWNER,
            'User-Agent': self.__USER_AGENT,
            'Accept-Charset': 'utf-8',

            # MC_REWRITE_TO_PYTHON:
            #
            # Disable keep-alive (and fancy requests' connection pooling) because rudimentary HTTP server used for Perl
            # unit tests doesn't support it (but then maybe we don't want keep-alive anyway)
            'Connection': 'close',
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

    def __get_domain_http_auth_lookup(self) -> Dict[str, AuthenticatedDomain]:
        """Read the mediawords.authenticated_domains list from mediawords.yml and generate a lookup hash with
        the host domain as the key and the user:password credentials as the value."""
        domain_http_auth_lookup = {}

        domains = self._user_agent_config.authenticated_domains()
        for domain in domains:
            domain_http_auth_lookup[domain.domain.lower()] = domain

        return domain_http_auth_lookup

    def __url_with_http_auth(self, url: str) -> str:
        """If there are HTTP auth credentials for the requested site, add them to the URL."""
        url = decode_object_from_bytes_if_needed(url)

        auth_lookup = self.__get_domain_http_auth_lookup()

        domain = get_url_distinctive_domain(url=url).lower()

        if domain in auth_lookup:
            auth = auth_lookup[domain]
            uri = furl(url)

            # https://stackoverflow.com/a/21629125/200603
            uri.username = auth.username
            uri.password = auth.password

            url = uri.url

        return url

    def get(self, url: str) -> Response:
        """GET an URL."""
        log.debug("mediawords.util.web.user_agent.get: %s" % url)
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

    def __get_follow_http_html_redirects_follow_redirects(self,
                                                          response_: Response,
                                                          meta_redirects_left: int) -> Union[Response, None]:

        from mediawords.util.web.user_agent.html_redirects import (
            target_request_from_meta_refresh_url,
            target_request_from_archive_org_url,
            target_request_from_archive_is_url,
            target_request_from_linkis_com_url,
            target_request_from_alarabiya_url,
        )

        if response_ is None:
            raise McGetFollowHTTPHTMLRedirectsException("Response is None.")

        if response_.is_success():

            base_url = get_base_url(response_.request().url())

            html_redirect_functions = [
                target_request_from_meta_refresh_url,
                target_request_from_archive_org_url,
                target_request_from_archive_is_url,
                target_request_from_linkis_com_url,
                target_request_from_alarabiya_url,
            ]
            for html_redirect_function in html_redirect_functions:
                request_after_meta_redirect = html_redirect_function(
                    content=response_.decoded_content(),
                    archive_site_url=base_url,
                )
                if request_after_meta_redirect is not None:
                    log.warning(
                        "meta redirect from %s: %s" % (html_redirect_function, request_after_meta_redirect.url()))
                    if not urls_are_equal(url1=response_.request().url(), url2=request_after_meta_redirect.url()):

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
                            'previous_url': response_.request().url(),
                        })
                        redirect_response.set_previous(response_)

                        meta_redirects_left = meta_redirects_left - 1

                        return self.__get_follow_http_html_redirects(
                            response_=orig_redirect_response,
                            meta_redirects_left=meta_redirects_left,
                        )

            # No <meta /> refresh, the current URL is the final one
            return response_

        else:
            log.debug("Request to %s was unsuccessful: %s" % (response_.request().url(), response_.status_line(),))

            # Return the original URL and give up
            return None

    def __get_follow_http_html_redirects_redirects_exhausted(self, response_: Response) -> Union[Response, None]:

        if response_ is None:
            raise McGetFollowHTTPHTMLRedirectsException("Response is None.")

        # If one of the URLs that we've been redirected to contains another encoded URL, assume
        # that we're hitting a paywall and the URLencoded URL is the right one
        urls_redirected_to = []

        for x in range(self.max_redirect() + 1):
            previous = response_.previous()
            if previous is None:
                break

            url_redirected_to = previous.request().url()
            encoded_url_redirected_to = quote(url_redirected_to)

            for redir_url in urls_redirected_to:
                if re.search(pattern=re.escape(encoded_url_redirected_to),
                             string=redir_url,
                             flags=re.IGNORECASE | re.UNICODE):
                    log.debug("""
                        Encoded URL %(encoded_url_redirected_to)s is a substring of another URL %(matched_url)s, so
                        I'll assume that %(url_redirected_to)s is the correct one.
                    """ % {
                        'encoded_url_redirected_to': encoded_url_redirected_to,
                        'matched_url': redir_url,
                        'url_redirected_to': url_redirected_to,
                    })
                    return previous

            urls_redirected_to.append(url_redirected_to)

        # Return the original URL (unless we find a URL being a substring of another URL, see below)
        return None

    def __get_follow_http_html_redirects(self, response_: Response, meta_redirects_left: int) -> Union[Response, None]:

        if response_ is None:
            raise McGetFollowHTTPHTMLRedirectsException("Response is None.")

        if meta_redirects_left > 0:
            return self.__get_follow_http_html_redirects_follow_redirects(
                response_=response_,
                meta_redirects_left=meta_redirects_left,
            )

        else:
            return self.__get_follow_http_html_redirects_redirects_exhausted(response_=response_)

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

        response_after_redirects = self.__get_follow_http_html_redirects(
            response_=response,
            meta_redirects_left=self.max_redirect()
        )
        if response_after_redirects is None:
            # One of the redirects failed -- return original response
            return response

        else:
            return response_after_redirects

    @staticmethod
    def __get_url_domain(url_: str) -> str:

        if not is_http_url(url_):
            return url_

        host = get_url_host(url_)

        name_parts = host.split('.')

        n = len(name_parts) - 1

        # for country domains, use last three parts of name
        if re.search(pattern=r"\...$", string=host):
            domain = '.'.join([name_parts[n - 2], name_parts[n - 1], name_parts[0]])

        elif re.search(pattern=r"(localhost|blogspot\.com|wordpress\.com)", string=host):
            domain = url_

        else:
            domain = '.'.join([name_parts[n - 1], name_parts[n]])

        return domain.lower()

    @staticmethod
    def __get_scheduled_urls(urls_: List[str], per_domain_timeout_: int) -> List[_ParallelGetScheduledURL]:
        """Schedule the URLs by adding a { time => $time } field to each URL to make sure we obey the
        'per_domain_timeout'. Sort requests by ascending time."""
        domain_urls = {}

        for url_ in urls_:
            domain = UserAgent.__get_url_domain(url_=url_)
            if domain not in domain_urls:
                domain_urls[domain] = []
            domain_urls[domain].append(url_)

        scheduled_urls = []

        for domain, urls_in_domain in domain_urls.items():
            time_ = 0
            for domain_url in urls_in_domain:
                domain_url = _ParallelGetScheduledURL(url=domain_url, time_=time_)
                scheduled_urls.append(domain_url)

                if time_ % 5 == 0:  # FIXME why 5?
                    time_ = time_ + per_domain_timeout_

        scheduled_urls = sorted(scheduled_urls, key=lambda x: x.time)

        return scheduled_urls

    def parallel_get(self, urls: List[str]) -> List[Response]:
        """GET multiple URLs in parallel."""

        # FIXME doesn't respect timing() and other object properties

        urls = decode_object_from_bytes_if_needed(urls)

        # Original implementation didn't raise on undefined / empty list of URLs
        if urls is None:
            return []
        if len(urls) == 0:
            return []

        # Remove duplicates from list while maintaining order because:
        # 1) We don't want to fetch the same URL twice
        # 2) URLs are being used as unique dictionary IDs later on
        urls_before_removing_duplicates = urls.copy()
        urls = list(OrderedDict.fromkeys(urls))
        if len(urls) != len(urls_before_removing_duplicates):
            log.warning("Some of the URLs are duplicate; URLs: %s" % str(urls_before_removing_duplicates))

        # Raise on one or more invalid URLs because we consider it a caller's problem; if URL at least looks valid,
        # get() in a fork should be able to come up with a reasonable Response object for it
        for url in urls:
            if not is_http_url(url):
                raise McParallelGetException("URL %s is not a valid URL; URLs: %s" % (url, str(urls),))

        num_parallel = self._user_agent_config.parallel_get_num_parallel()
        timeout = self._user_agent_config.parallel_get_timeout()
        per_domain_timeout = self._user_agent_config.parallel_get_per_domain_timeout()

        url_stack = UserAgent.__get_scheduled_urls(urls_=urls, per_domain_timeout_=per_domain_timeout)

        start_time = time.time()

        url_blocks = {}
        while len(url_stack) > 0:
            block_i = len(url_stack) % num_parallel

            if block_i not in url_blocks:
                url_blocks[block_i] = []

            url_blocks[block_i].append(url_stack.pop())

        pool = multiprocessing.Pool(processes=num_parallel)

        all_results = []
        for i, url_block in url_blocks.items():
            result = pool.apply_async(_parallel_get_web_store, args=(url_block, start_time, timeout,))
            all_results.append(result)

        all_responses = []
        for result in all_results:
            responses = result.get()
            all_responses = all_responses + responses

        # No timeouts here because we trust the workers to timeout by themselves (by UserAgent)
        pool.close()
        pool.join()
        pool.terminate()

        # Sort URLs in parameter order
        # (if URLs weren't split into blocks, we could probably use map_async)
        response_url_map = {}
        for response in all_responses:
            url = response.scheduled_url.url
            response_url_map[url] = response.response

        sorted_responses = []
        for url in urls:
            if url not in response_url_map:
                raise McParallelGetException("URL %s is not in the response URL map %s." % (url, response_url_map,))

            sorted_responses.append(response_url_map[url])

        if len(urls) != len(sorted_responses):
            raise McParallelGetException(
                "Response count doesn't match URL count; responses: %s; URLs: %s" % (sorted_responses, urls,)
            )

        return sorted_responses

    def get_string(self, url: str) -> Union[str, None]:
        """Return URL content as string, None on error."""

        response = self.get(url=url)
        if response.is_success():
            return response.decoded_content()
        else:
            return None

    def __blacklist_request_if_needed(self, request: Request) -> Request:
        """If request's URL is blacklisted, update the request to point to a blacklisted URL."""
        # FIXME there should be a better way to block those unwanted requests

        if request is None:
            raise McRequestException("Request is None.")

        url = request.url()
        if url is None:
            raise McRequestException("URL is None.")
        if len(url) == 0:
            raise McRequestException("URL is empty.")

        blacklist_url_pattern = self._user_agent_config.blacklist_url_pattern()
        if blacklist_url_pattern:
            if re.search(pattern=blacklist_url_pattern, string=url, flags=re.IGNORECASE | re.UNICODE) is not None:
                request.set_url("http://0.0.0.1/%s" % url)

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

        log.debug("HTTP request: %s %s\n" % (sql_now(), url,))

    def __prepare_request(self, request: Request) -> requests.PreparedRequest:
        """Create PreparedRequest from UserAgent's Request. Raises if one or more parameters are invalid."""
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
        if ((auth_username is None and auth_password is not None) or (
                auth_username is not None and auth_password is None)):
            raise McRequestException("Either both or none of HTTP authentication credentials must be not None.")

        auth = None
        if auth_username is not None and auth_password is not None:
            if ((len(auth_username) == 0 and len(auth_password) > 0) or (
                    len(auth_username) > 0 and len(auth_password) == 0)):
                raise McRequestException("Either both or none of HTTP authentication credentials must be not Empty.")

            auth = HTTPBasicAuth(auth_username, auth_password)

        data = request.content()

        try:
            requests_request = requests.Request(
                method=method,
                url=url,
                data=data,
                headers=headers,
                auth=auth,
            )
            requests_prepared_request = self.__session.prepare_request(requests_request)

        except Exception as ex:
            raise McRequestException("Unable to prepare request %s: %s" % (str(request), str(ex),))

        return requests_prepared_request

    class UserAgentResponse(object):
        """Class carrying requests's Response object and a flag on whether error happened on the client size."""
        __slots__ = [
            'requests_response',
            'error_is_client_side',
        ]

        def __init__(self, requests_response: requests.Response, error_is_client_side: bool):
            self.requests_response = requests_response
            self.error_is_client_side = error_is_client_side

    def __execute_request(self, requests_prepared_request: requests.PreparedRequest) -> UserAgentResponse:
        """Execute PreparedRequest. Returns UserAgentResponse independently on whether request succeeds or fails."""

        def urllib3_http_response_from_exception(exception: Exception) -> HTTPResponse:
            """On exceptions, we want to create our own HTTPResponse with exception's message to set it to response.raw
            to be read later."""
            return HTTPResponse(
                body=io.BytesIO(str(exception).encode('utf-8', errors='replace')),

                # https://github.com/requests/requests/issues/2635#issuecomment-112270117
                preload_content=False,
            )

        try:
            requests_response = self.__session.send(
                request=requests_prepared_request,
                timeout=self.timeout(),

                # To be able to enforce max_size
                stream=True,
            )

        except requests.TooManyRedirects as ex:

            # On too many redirects, return the last fetched page (just like LWP::UserAgent does)
            log.warning("Exceeded max. redirects for URL %s" % requests_prepared_request.url)
            response = UserAgent.UserAgentResponse(requests_response=ex.response,
                                                   error_is_client_side=False)

        except requests.Timeout as ex:

            log.warning("Timeout for URL %s" % requests_prepared_request.url)

            requests_response = requests.Response()
            requests_response.status_code = HTTPStatus.REQUEST_TIMEOUT.value
            requests_response.reason = HTTPStatus.REQUEST_TIMEOUT.phrase
            requests_response.request = requests_prepared_request

            requests_response.history = []

            requests_response.raw = urllib3_http_response_from_exception(ex)

            # We treat timeouts as client-side errors too because we can retry on them
            response = UserAgent.UserAgentResponse(requests_response=requests_response,
                                                   error_is_client_side=True)

        except Exception as ex:

            # Client-side error
            log.warning(
                "Client-side error while processing request %s: %s" % (str(requests_prepared_request), str(ex),)
            )

            requests_response = requests.Response()
            requests_response.status_code = HTTPStatus.BAD_REQUEST.value
            requests_response.reason = "Client-side error"
            requests_response.request = requests_prepared_request

            # Previous request / response chain is not built for client-side errored requests
            requests_response.history = []

            requests_response.headers = {
                # LWP::UserAgent compatibility
                'Client-Warning': 'Client-side error',
            }

            requests_response.raw = urllib3_http_response_from_exception(ex)

            response = UserAgent.UserAgentResponse(requests_response=requests_response,
                                                   error_is_client_side=True)

        else:

            response = UserAgent.UserAgentResponse(requests_response=requests_response,
                                                   error_is_client_side=False)

        return response

    def request(self, request: Request) -> Response:
        """Execute a request, return a response.

        All other helpers are supposed to use request() internally as it implements max. size, callbacks, blacklisted
        URLs etc."""

        if request is None:
            raise McRequestException("Request is None.")

        request = self.__blacklist_request_if_needed(request=request)

        self.__log_request(request=request)

        try:
            requests_prepared_request = self.__prepare_request(request)
        except Exception as ex:
            raise McRequestException("Unable to prepare request %s: %s" % (str(request), str(ex),))

        try:
            user_agent_response = self.__execute_request(requests_prepared_request)
        except Exception as ex:
            raise McRequestException("Unable to execute request %s: %s" % (str(requests_prepared_request), str(ex),))

        if user_agent_response.requests_response is None:
            raise McRequestException("Response from 'requests' is None.")

        response = Response(
            requests_response=user_agent_response.requests_response,
            max_size=self.max_size(),
            error_is_client_side=user_agent_response.error_is_client_side,
        )

        # Build the previous request / response chain from the redirects
        current_response = response
        for previous_rq_response in reversed(user_agent_response.requests_response.history):
            previous_rq_request = previous_rq_response.request
            previous_response_request = Request.from_requests_prepared_request(
                requests_prepared_request=previous_rq_request
            )

            # Sometimes reading the (chunked?) previous response's data fails with:
            #
            #      AttributeError: 'NoneType' object has no attribute 'readline'
            #
            # Previous response's data is not that important, so fail rather silently.
            try:
                previous_rq_response.text
            except Exception as ex:
                log.warning("Reading previous response's data failed: %s" % str(ex))
                previous_rq_response.raw_data = io.StringIO('')

            previous_response = Response(requests_response=previous_rq_response, max_size=self.max_size())
            previous_response.set_request(request=previous_response_request)

            current_response.set_previous(previous=previous_response)
            current_response = previous_response

        # Redirects might have happened, so we have to recreate the request object from the latest page that was
        # redirected to
        response_request = Request.from_requests_prepared_request(
            requests_prepared_request=user_agent_response.requests_response.request
        )
        response.set_request(response_request)

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

        if timing is None:
            # Disable retries
            max_retries = requests.adapters.DEFAULT_RETRIES

        else:
            # Enable retries

            # Doesn't really implement "timing" as LWP::UserAgent::Determined did, simply assumes that
            # "[1, 2, 4, 8, ...]" timing value means that we want a back-off factor of 2-1 = 1 second.
            if len(timing) == 1:
                backoff_factor = timing[0]
            else:
                backoff_factor = timing[1] - timing[0]

            max_retries = Retry(
                total=len(timing),
                backoff_factor=backoff_factor,
                status_forcelist=DETERMINED_HTTP_CODES,
            )

        http_prefixes = ['http://', 'https://']

        for http_prefix in http_prefixes:
            self.__session.mount(prefix=http_prefix, adapter=HTTPAdapter(max_retries=max_retries))

    def timeout(self) -> Union[int, None]:
        """Return timeout."""
        return self.__timeout

    def set_timeout(self, timeout: Union[int, None]) -> None:
        """Set timeout."""
        if isinstance(timeout, bytes):
            timeout = decode_object_from_bytes_if_needed(timeout)
        if timeout is not None:
            timeout = int(timeout)
            if timeout <= 0:
                raise McUserAgentException("Timeout is zero or negative.")
        self.__timeout = timeout

    def max_redirect(self) -> Union[int, None]:
        """Return max. number of redirects."""
        return self.__session.max_redirects

    def set_max_redirect(self, max_redirect: Union[int, None]) -> None:
        """Set max. number of redirects."""
        if isinstance(max_redirect, bytes):
            max_redirect = decode_object_from_bytes_if_needed(max_redirect)
        if max_redirect is not None:
            max_redirect = int(max_redirect)
            if max_redirect < 0:
                raise McUserAgentException("Max. redirect count is negative.")

        # Session objects support None values
        self.__session.max_redirects = max_redirect

    def max_size(self) -> Union[int, None]:
        """Return max. download size; if None, download size will not be limited."""
        return self.__max_size

    def set_max_size(self, max_size: Union[int, None]) -> None:
        """Set max. download size; if None, download size will not be limited."""
        if isinstance(max_size, bytes):
            max_size = decode_object_from_bytes_if_needed(max_size)
        if max_size is not None:
            max_size = int(max_size)
            if max_size <= 0:
                raise McUserAgentException("Max. size is zero or negative.")
        self.__max_size = max_size
