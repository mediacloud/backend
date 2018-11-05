import codecs
import email

import chardet
from http import HTTPStatus
from typing import Union, Dict, Optional

import requests

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.web.user_agent.request.request import Request

log = create_logger(__name__)


class McUserAgentResponseException(Exception):
    """User agent's Response exception."""
    pass


class Response(object):
    """HTTP response object."""
    # FIXME redo properties to proper Pythonic way (with decorators).

    __slots__ = [
        '__requests_response',
        '__error_is_client_side',

        # Raw data that was read from the response
        '__response_data',

        '__previous_response',
        '__request',
    ]

    def __init__(self,
                 requests_response: requests.Response,
                 max_size: Optional[int],
                 error_is_client_side: bool = False):
        """Constructor."""

        try:
            # Read the raw data right away without waiting for a call to raw_data() to make sure that the server doesn't
            # time out while returning stuff
            self.__response_data = self.__read_response_data(requests_response=requests_response, max_size=max_size)

            # Release the response to return connection back to the pool
            # (http://docs.python-requests.org/en/master/user/advanced/#body-content-workflow)
            requests_response.close()

        except Exception as ex:
            log.warning("Error reading data for URL %s" % requests_response.url)

            error_response = requests.Response()
            error_response.status_code = HTTPStatus.REQUEST_TIMEOUT.value
            error_response.reason = HTTPStatus.REQUEST_TIMEOUT.phrase
            error_response.request = requests_response.request
            error_response.history = []

            requests_response = error_response

            # We treat timeouts as client-side errors too because we can retry on them
            error_is_client_side = True

            self.__response_data = str(ex).encode('utf-8')

        self.__requests_response = requests_response
        self.__error_is_client_side = error_is_client_side

        self.__previous_response = None
        self.__request = None

    def code(self) -> int:
        """Return HTTP status code, e.g. 200."""
        return self.__requests_response.status_code

    def message(self) -> str:
        """Return HTTP status message, e.g. "OK" or an empty string."""
        return self.__requests_response.reason

    def headers(self) -> Dict[str, str]:
        """Return all HTTP headers."""
        # FIXME rewrite to CaseInsensitiveDict
        # FIXME or at least cache somehow
        lowercase_headers = dict()
        for name, value in self.__requests_response.headers.items():
            if name is None:
                raise McUserAgentResponseException("Header's name is None.")
            if len(name) == 0:
                raise McUserAgentResponseException("Header's name is empty.")
            if value is None:
                raise McUserAgentResponseException("Header's value is None.")
            # Header value can be empty string (e.g. "x-check: ") but not None

            name = name.lower()  # All locally stored headers will be lowercase
            value = str(value)  # E.g. Content-Length might get passed as int

            lowercase_headers[name] = value

        return lowercase_headers

    def header(self, name: str) -> Union[str, None]:
        """Return HTTP header, e.g. "text/html; charset=UTF-8' for "Content-Type" parameter."""
        name = decode_object_from_bytes_if_needed(name)
        if name is None:
            raise McUserAgentResponseException("Header's name is None.")
        if len(name) == 0:
            raise McUserAgentResponseException("Header's name is empty.")
        name = name.lower()  # All locally stored headers will be lowercase
        return self.headers().get(name)

    @staticmethod
    def __read_response_data(requests_response: requests.Response, max_size: int) -> bytes:
        """Read data from Response object. Raises on read errors, callers are expected to catch exceptions."""

        response_data = b''

        url = requests_response.url

        # Don't bother testing Content-Length for max_size because it might be missing or lying; instead,
        # read up to max_size bytes

        chunk_size = 1024 * 100
        response_data_size = 0

        for chunk in requests_response.raw.stream(chunk_size, decode_content=True):

            response_data += chunk
            response_data_size += len(chunk)  # byte length, not string length

            # Content-Length might be missing / lying, so we measure size while fetching the data too
            if max_size is not None:
                if response_data_size > max_size:
                    log.warning("Data size exceeds %d for URL %s" % (max_size, url,))
                    break

        return response_data

    def raw_data(self) -> bytes:
        return self.__response_data

    def decoded_content(self) -> str:
        """Return content in UTF-8 encoding."""

        url = self.__requests_response.url

        assert self.__response_data is not None, "We expect response data to be set at this point."

        # requests's "apparent_encoding" is not used because chardet might OOM on big binary data responses
        encoding = self.__requests_response.encoding

        if encoding is not None:

            # If "Content-Type" HTTP header contains a string "text" and doesn't have "charset" property,
            # "requests" falls back to setting the encoding to ISO-8859-1, which is probably not right
            # (encoding might have been defined in the HTML content itself via <meta> tag), so we use the
            # "apparent encoding" instead
            if encoding.lower() == 'iso-8859-1':
                # Will try to auto-detect later
                encoding = None

        # Some pages report some funky encoding; in that case, fallback to UTF-8
        if encoding is not None:
            try:
                codecs.lookup(encoding)
            except LookupError:
                log.warning("Invalid encoding %s for URL %s" % (encoding, url,))

                # Autodetect later
                encoding = None

        if encoding is None:
            # Test the encoding guesser's opinion, just like browsers do
            try:
                # 100 KB should be enough for for chardet to be able to make an informed decision
                encoding = chardet.detect(self.__response_data[:1024 * 100])['encoding']
            except Exception as ex:
                log.warning("Unable to detect encoding for URL %s: %s" % (url, str(ex),))
                encoding = None

            # If encoding is not in HTTP headers nor can be determined from content itself, assume that
            # it's UTF-8
            if encoding is None:
                encoding = 'UTF-8'

        try:
            decoded_content = codecs.decode(self.__response_data, encoding=encoding, errors='replace')
        except Exception as ex:
            log.warning("Unable to decode data for URL {}: {}".format(url, str(ex)))
            decoded_content = ''

        return decoded_content

    def decoded_utf8_content(self) -> str:
        """Return content in UTF-8 content while assuming that the raw data is in UTF-8."""
        # FIXME how do we do this?
        return self.decoded_content()

    def status_line(self) -> str:
        """Return HTTP status line, e.g. "200 OK" or "418"."""
        if self.message() == '':
            return "%d" % self.code()
        else:
            return "%d %s" % (self.code(), self.message(),)

    def is_success(self) -> bool:
        """Return True if request was successful."""
        code = self.code()
        if code is not None:
            return 200 <= code < 300
        else:
            return False

    def content_type(self) -> Union[str, None]:
        """Return "Content-Type" header; strip optional parameters, e.g. "charset"."""
        content_type = self.header('Content-Type')

        if content_type is None:
            return None

        # Parse "type/subtype" out of "type/subtype; param=value; ..."
        header_parser = email.parser.HeaderParser()
        message = header_parser.parsestr("Content-Type: %s" % content_type)
        content_type = message.get_content_type()
        return content_type

    # noinspection PyMethodMayBeStatic
    def error_is_client_side(self) -> bool:
        """Return True if the response's error was generated by LWP itself and not by the server."""
        # FIXME
        if self.is_success():
            raise McUserAgentResponseException("Response was successful, but I have expected an error.")
        return self.__error_is_client_side

    def set_error_is_client_side(self, error_is_client_side: bool) -> None:
        """Set whether error is on the client side."""
        if self.is_success():
            raise McUserAgentResponseException("Response was successful, but I have expected an error.")
        error_is_client_side = bool(error_is_client_side)
        self.__error_is_client_side = error_is_client_side

    def previous(self) -> Union['Response', None]:
        """Return previous Response, the redirect of which has led to this Response."""
        return self.__previous_response

    def set_previous(self, previous: Union['Response', None]) -> None:
        """Set previous Response, the redirect of which has led to this Response."""
        self.__previous_response = previous

    def request(self) -> Request:
        """Return Request that was made to get this Response."""
        return self.__request

    def set_request(self, request: Request) -> None:
        """Set Request that was made to get this Response."""
        if request is None:
            raise McUserAgentResponseException("Request is None.")
        self.__request = request

    def original_request(self) -> Request:
        """Walk back from the given response to get the original request that generated the response."""
        original_response = self
        while original_response.previous():
            original_response = original_response.previous()
        return original_response.request()
