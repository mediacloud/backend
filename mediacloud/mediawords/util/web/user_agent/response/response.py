import codecs
import email
from typing import Union, Dict

import chardet
from urllib3 import HTTPResponse

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
        '__urllib3_response',
        '__max_raw_data_size',

        '__previous_response',
        '__request',

        '__error_is_client_side',
    ]

    def __init__(self, urllib3_response: HTTPResponse, max_raw_data_size: int = None):
        """Constructor."""

        if not urllib3_response:
            raise McUserAgentResponseException("urllib3 response is unset.")

        if isinstance(max_raw_data_size, str):
            max_raw_data_size = decode_object_from_bytes_if_needed(max_raw_data_size)

        self.__urllib3_response = urllib3_response
        self.__max_raw_data_size = max_raw_data_size

        self.__previous_response = None
        self.__request = None

        self.__error_is_client_side = False

    def code(self) -> int:
        """Return HTTP status code, e.g. 200."""
        return self.__urllib3_response.status

    def message(self) -> str:
        """Return HTTP status message, e.g. "OK" or an empty string."""
        return self.__urllib3_response.reason

    def headers(self) -> Dict[str, str]:
        """Return all HTTP headers."""
        # FIXME make use of HTTPHeaderDict
        local_headers = {}

        for name, value in self.__urllib3_response.headers:
            if len(name) == 0:
                raise McUserAgentResponseException("Header's name is empty.")
            # Header value can be empty string (e.g. "x-check: ") but not None
            if value is None:
                raise McUserAgentResponseException("Header's value is None for header '{}'.".format(name))
            name = name.lower()  # All locally stored headers will be lowercase
            value = str(value)  # E.g. Content-Length might get passed as int
            local_headers[name] = value

        return local_headers

    def header(self, name: str) -> Union[str, None]:
        """Return HTTP header, e.g. "text/html; charset=UTF-8' for "Content-Type" parameter."""
        name = decode_object_from_bytes_if_needed(name)
        if name is None:
            raise McUserAgentResponseException("Header's name is None.")
        if len(name) == 0:
            raise McUserAgentResponseException("Header's name is empty.")
        name = name.lower()  # All locally stored headers will be lowercase
        local_headers = self.headers()
        if name in local_headers:
            return local_headers[name]
        else:
            return None

    def raw_data(self) -> bytes:
        """Return raw byte array of the response."""
        raise NotImplementedError("FIXME not implemented")

    def decoded_content(self) -> str:
        """Return content in UTF-8 encoding."""
        response_data = ""
        read_response_data = True

        url = self.__urllib3_response.geturl()

        if self.__max_raw_data_size is not None:
            content_length = self.header('Content-Length')

            try:
                if content_length is not None:

                    # HTTP spec allows one to combine multiple headers into one so Content-Length might look
                    # like "Content-Length: 123, 456"
                    if ',' in content_length:
                        content_length = content_length.split(',')
                        content_length = list(map(int, content_length))
                        content_length = max(content_length)

                    content_length = int(content_length)

            except Exception as ex:
                log.warning(
                    "Unable to read Content-Length for URL '%(url)s': %(exception)s" % {
                        'url': url,
                        'exception': ex,
                    })
                content_length = None

            if content_length is not None:
                if content_length > self.__max_raw_data_size:
                    log.warning(
                        "Content-Length exceeds %d for URL %s" % (
                            self.__max_raw_data_size, url,
                        )
                    )

                    read_response_data = False

        if read_response_data:

            # requests's "apparent_encoding" is not used because chardet might OOM on big binary data responses
            get_content_charset()
            encoding = requests_response.encoding

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
                    log.warning("Invalid encoding %s for URL %s" % (encoding, requests_response.url,))

                    # Autodetect later
                    encoding = None

            # 100 KB should be enough for for chardet to be able to make an informed decision
            chunk_size = 1024 * 100
            decoder = None
            response_data_size = 0

            raw_stream = self.__urllib3_response.stream(chunk_size, decode_content=True)

            for chunk in raw_stream:

                if encoding is None:
                    # Test the encoding guesser's opinion, just like browsers do
                    try:
                        encoding = chardet.detect(chunk)['encoding']
                    except Exception as ex:
                        log.warning("Unable to detect encoding for URL %s: %s" % (url, ex,))
                        encoding = None

                    # If encoding is not in HTTP headers nor can be determined from content itself, assume that
                    # it's UTF-8
                    if encoding is None:
                        encoding = 'UTF-8'

                if decoder is None:
                    decoder = codecs.getincrementaldecoder(encoding)(errors='replace')

                decoded_chunk = decoder.decode(chunk)

                response_data += decoded_chunk
                response_data_size += len(chunk)  # byte length, not string length

                # Content-Length might be missing / lying, so we measure size while fetching the data too
                if self.__max_raw_data_size is not None:
                    if response_data_size > self.__max_raw_data_size:
                        log.warning("Data size exceeds %d for URL %s" % (self.__max_raw_data_size, url,))

                        break

        return response_data

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
        charset = message.get_
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
