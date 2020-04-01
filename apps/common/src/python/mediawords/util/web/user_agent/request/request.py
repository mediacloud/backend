from email.parser import HeaderParser as EmailHeaderParser

import requests
from urllib.parse import urlencode
from typing import Union, Dict, Optional, Any

from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.url import fix_common_url_mistakes, is_http_url


class McUserAgentRequestException(Exception):
    """User agent's Request exception."""
    pass


class Request(object):
    """HTTP request object."""
    # FIXME redo properties to proper Pythonic way (with decorators).

    __slots__ = [
        '__method',
        '__url',
        '__auth_username',
        '__auth_password',
        '__headers',
        '__data',
    ]

    def __init__(self,
                 method: str,
                 url: str,
                 auth_username: Optional[str] = None,
                 auth_password: Optional[str] = None,
                 headers: Optional[Dict[str, str]] = None,
                 content: Optional[Union[str, bytes, Dict[str, str], Dict[bytes, bytes]]] = None):
        """Constructor."""
        self.__method = None
        self.__url = None
        self.__headers = {}
        self.__data = None
        self.__auth_username = None
        self.__auth_password = None

        self.set_method(method)
        self.set_url(url)

        if auth_username:
            self.set_auth_username(auth_username)
        if auth_password:
            self.set_auth_password(auth_password)
        if headers:
            for key, value in headers.items():
                self.set_header(name=key, value=value)
        if content:
            self.set_content(content)
    @staticmethod
    def from_requests_prepared_request(requests_prepared_request: requests.PreparedRequest):
        """Create request from requests's PreparedRequest object."""
        request = Request(
            method=requests_prepared_request.method,
            url=requests_prepared_request.url,
        )
        for name, value in requests_prepared_request.headers.items():
            request.set_header(name=name, value=value)

        if requests_prepared_request.body is not None:
            request.set_content(requests_prepared_request.body)

        # Authentication credentials (if any) are probably going to be contained in the URL itself

        return request

    def method(self) -> str:
        """Return HTTP method, e.g. GET."""
        return self.__method

    def set_method(self, method: str) -> None:
        """Set HTTP method, e.g. GET."""
        method = decode_object_from_bytes_if_needed(method)
        if method is None:
            raise McUserAgentRequestException("Method is None.")
        if len(method) == 0:
            raise McUserAgentRequestException("Method is empty.")
        self.__method = method.upper()

    def url(self) -> str:
        """Return URL, e.g. https://www.mediacloud.org/page.html"""
        return self.__url

    def set_url(self, url: str) -> None:
        """Set URL, e.g. https://www.mediacloud.org/page.html"""
        url = decode_object_from_bytes_if_needed(url)
        if url is None:
            raise McUserAgentRequestException("URL is None.")
        if len(url) == 0:
            raise McUserAgentRequestException("URL is empty.")

        # Might be coming from "requests" which managed to fetch a bogus URL but we deem it to be invalid
        url = fix_common_url_mistakes(url)

        if not is_http_url(url):
            raise McUserAgentRequestException("URL is not HTTP(s): %s" % str(url))

        self.__url = url

    def headers(self) -> Dict[str, str]:
        """Return all HTTP headers."""
        return self.__headers

    def header(self, name: str) -> Union[str, None]:
        """Return HTTP header, e.g. "utf-8' for "Accept-Encoding" parameter."""
        name = decode_object_from_bytes_if_needed(name)
        if name is None:
            raise McUserAgentRequestException("Header's name is None.")
        if len(name) == 0:
            raise McUserAgentRequestException("Header's name is empty.")
        name = name.lower()  # All locally stored headers will be lowercase
        if name in self.__headers:
            return self.__headers[name]
        else:
            return None

    def set_header(self, name: str, value: str) -> None:
        """Set HTTP header, e.g. "Accept-Encoding: utf-8."""
        name = decode_object_from_bytes_if_needed(name)
        value = decode_object_from_bytes_if_needed(value)
        if name is None:
            raise McUserAgentRequestException("Header's name is None.")
        if len(name) == 0:
            raise McUserAgentRequestException("Header's name is empty.")
        if value is None:
            raise McUserAgentRequestException("Header's value is None.")
        # Header value can be empty string (e.g. "x-check: ") but not None
        name = name.lower()  # All locally stored headers will be lowercase
        value = str(value)  # E.g. Content-Length might get passed as int
        self.__headers[name] = value

    def content_type(self) -> Union[str, None]:
        """Return "Content-Type" header; strip optional parameters, e.g. "charset"."""
        content_type = self.header('Content-Type')

        if content_type is None:
            return None

        # Parse "type/subtype" out of "type/subtype; param=value; ..."
        header_parser = EmailHeaderParser()
        message = header_parser.parsestr("Content-Type: %s" % content_type)
        content_type = message.get_content_type()
        return content_type

    def set_content_type(self, content_type: str) -> None:
        """Set "Content-Type" header."""
        content_type = decode_object_from_bytes_if_needed(content_type)
        if content_type is None:
            raise McUserAgentRequestException("Content type is None.")
        if len(content_type) == 0:
            raise McUserAgentRequestException("Content type is empty.")
        self.set_header('Content-Type', content_type)

    def content(self) -> Union[bytes, None]:
        """Get raw data sent as part of the POST request."""
        return self.__data

    def set_content(self, content: Union[str, bytes, Dict[str, str], Dict[bytes, bytes]]) -> None:
        """Set raw data sent as part of the POST request, in either a UTF-8 string, raw bytes, dictionary of UTF-8
        strings, or dictionary of bytes."""

        if isinstance(content, dict):
            # urlencode into string; urlencode() seems to work fine with both string and bytes dictionaries
            content = urlencode(content, doseq=True)

        if isinstance(content, str):
            content = content.encode('utf-8', errors='replace')

        if not isinstance(content, bytes):
            raise McUserAgentRequestException("Content must be 'bytes' at this point: %s" % str(content))

        self.__data = content

    def set_authorization_basic(self, username: str, password: str) -> None:
        """Set HTTP basic authorization credentials."""
        username = decode_object_from_bytes_if_needed(username)
        password = decode_object_from_bytes_if_needed(password)
        self.set_auth_username(username)
        self.set_auth_password(password)

    def set_auth_username(self, username: str) -> None:
        """Set HTTP authentication username."""
        username = decode_object_from_bytes_if_needed(username)
        if username is None:
            raise McUserAgentRequestException("Username is None.")
        if len(username) == 0:
            raise McUserAgentRequestException("Username is empty.")
        self.__auth_username = username

    def auth_username(self) -> Union[str, None]:
        """Return HTTP authentication username."""
        return self.__auth_username

    def set_auth_password(self, password: str) -> None:
        """Return HTTP authentication password."""
        password = decode_object_from_bytes_if_needed(password)
        if password is None:
            raise McUserAgentRequestException("Password is None.")
        if len(password) == 0:
            raise McUserAgentRequestException("Password is empty.")
        self.__auth_password = password

    def auth_password(self):
        """Return HTTP authentication password."""
        return self.__auth_password
