from typing import Union, Dict

from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.web.ua.request import Request


class McUserAgentResponseException(Exception):
    """User agent's Response exception."""
    pass


class Response(object):
    """HTTP response object."""
    # FIXME redo properties to proper Pythonic way (with decorators).

    __slots__ = [
        '__code',
        '__message',
        '__headers',
        '__data',

        '__previous_response',
        '__request',

        '__error_is_client_side',
    ]

    def __init__(self, code: int, message: str, headers: dict, data: str):
        """Constructor; expects headers and data encoded in UTF-8."""
        message = decode_object_from_bytes_if_needed(message)
        headers = decode_object_from_bytes_if_needed(headers)
        data = decode_object_from_bytes_if_needed(data)

        self.__code = None
        self.__message = None
        self.__headers = {}
        self.__data = None

        self.__previous_response = None
        self.__request = None

        self.__error_is_client_side = False

        self.__set_code(code)
        self.__set_message(message)
        self.__set_headers(headers)
        self.__set_content(data)

    def __repr__(self):
        return 'Response(%(code)d, %(message)s, %(headers)s, %(data)s)' % {
            'code': self.__code,
            'message': self.__message,
            'headers': str(self.__headers),
            'data': self.__data,
        }

    __str__ = __repr__

    def code(self) -> int:
        """Return HTTP status code, e.g. 200."""
        return self.__code

    def __set_code(self, code: int) -> None:
        """Set HTTP status code, e.g. 200."""
        if isinstance(code, bytes):
            code = decode_object_from_bytes_if_needed(code)
        if code is None:
            raise McUserAgentResponseException("HTTP status code is None.")

        code = int(code)

        if code < 1:
            raise McUserAgentResponseException("HTTP status code is invalid: %s" % str(code))
        self.__code = int(code)

    def message(self) -> str:
        """Return HTTP status message, e.g. "OK"."""
        return self.__message

    def __set_message(self, message: str) -> None:
        """Set HTTP status message, e.g. "OK"."""
        message = decode_object_from_bytes_if_needed(message)
        if message is None:
            raise McUserAgentResponseException("HTTP status message is None.")
        if len(message) == 0:
            raise McUserAgentResponseException("HTTP status message is empty.")
        self.__message = message

    def headers(self) -> Dict[str, str]:
        """Return all HTTP headers."""
        return self.__headers

    def header(self, name: str) -> Union[str, None]:
        """Return HTTP header, e.g. "text/html; charset=UTF-8' for "Content-Type" parameter."""
        name = decode_object_from_bytes_if_needed(name)
        if name is None:
            raise McUserAgentResponseException("Header's name is None.")
        if len(name) == 0:
            raise McUserAgentResponseException("Header's name is empty.")
        name = name.lower()  # All locally stored headers will be lowercase
        if name in self.__headers:
            return self.__headers[name]
        else:
            return None

    def __set_header(self, name: str, value: str) -> None:
        """Set HTTP header, e.g. "Content-Type: text/html; charset=UTF-8."""
        name = decode_object_from_bytes_if_needed(name)
        value = decode_object_from_bytes_if_needed(value)
        if name is None:
            raise McUserAgentResponseException("Header's name is None.")
        if len(name) == 0:
            raise McUserAgentResponseException("Header's name is empty.")
        if value is None:
            raise McUserAgentResponseException("Header's value is None.")
        if len(value) == 0:
            raise McUserAgentResponseException("Header's value is empty.")
        name = name.lower()  # All locally stored headers will be lowercase
        self.__headers[name] = value

    def __set_headers(self, headers: Dict[str, str]) -> None:
        """Fill HTTP headers dictionary with headers."""
        headers = decode_object_from_bytes_if_needed(headers)
        if headers is None:
            raise McUserAgentResponseException("Headers is None.")

        # Convert requests's CaseInsensitiveDict to a native dictionary
        for name, value in headers.items():
            name = name.strip()
            value = value.strip()
            self.__set_header(name=name, value=value)

    def decoded_content(self) -> str:
        """Return content in UTF-8 encoding."""
        return self.__data

    def decoded_utf8_content(self) -> str:
        """Return content in UTF-8 content while assuming that the raw data is in UTF-8."""
        # FIXME how do we do this?
        return self.decoded_content()

    def __set_content(self, content: str) -> None:
        """Set content in UTF-8 encoding."""
        content = decode_object_from_bytes_if_needed(content)
        if content is None:
            raise McUserAgentResponseException("Content is None.")
        self.__data = content

    def status_line(self) -> str:
        """Return HTTP status line, e.g. "200 OK"."""
        return "%d %s" % (self.code(), self.message(),)

    def is_success(self) -> bool:
        """Return True if request was successful."""
        code = self.code()
        if code is not None:
            return 200 <= code < 300
        else:
            return False

    def content_type(self) -> str:
        """Return "Content-Type" header."""
        return self.header('Content-Type')

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

    def as_string(self) -> str:
        """Return string representation of the response."""
        return str(self)
