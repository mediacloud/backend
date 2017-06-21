import base64
from http import HTTPStatus
from http.server import HTTPServer, BaseHTTPRequestHandler
import multiprocessing
import os
import time
from typing import Union
from urllib.parse import urlparse, parse_qs

from mediawords.util.log import create_logger
from mediawords.util.network import tcp_port_is_open
from mediawords.util.perl import decode_object_from_bytes_if_needed


class McHashServerException(Exception):
    """HashServer exception."""
    pass


l = create_logger(__name__)


class HashServer(object):
    """Simple HTTP server that just serves a set of pages defined by a simple dictionary.

    It is intended to make it easy to startup a simple server seeded with programmer defined content."""

    # argument for die called by handle_response when a request with the path /die is received
    _DIE_REQUEST_MESSAGE = 'received /die request'

    # Default HTTP status code for redirects ("301 Moved Permanently")
    _DEFAULT_REDIRECT_STATUS_CODE = HTTPStatus.MOVED_PERMANENTLY

    __host = '127.0.0.1'
    __port = 0
    __pages = {}

    __http_server = None
    __http_server_thread = None

    # noinspection PyPep8Naming
    class _HTTPHandler(BaseHTTPRequestHandler):

        _pages = {}

        def _set_pages(self, pages: dict):
            self._pages = pages

        def __write_response_string(self, response_string: str) -> None:
            self.wfile.write(response_string.encode('utf-8'))

        def __request_passed_authentication(self, page: dict) -> bool:
            if 'auth' not in page:
                return True

            auth_header = self.headers.get('Authorization', None)
            if auth_header is None:
                return False

            if not auth_header.startswith('Basic '):
                l.warning('Invalid authentication header: %s' % auth_header)
                return False

            auth_header = auth_header.strip()
            auth_header_name, auth_header_value_base64 = auth_header.split(' ')
            if len(auth_header_value_base64) == 0:
                l.warning('Invalid authentication header: %s' % auth_header)
                return False

            auth_header_value = base64.b64decode(auth_header_value_base64).decode('utf-8')
            if auth_header_value != page['auth']:
                l.warning("Invalid authentication; expected: %s, actual: %s" % (page['auth'], auth_header_value))
                return False

            return True

        def send_response(self, code: Union[int, HTTPStatus], message=None):
            if message is None:
                if isinstance(code, HTTPStatus):
                    message = code.phrase
                    code = code.value
            BaseHTTPRequestHandler.send_response(self, code=code, message=message)

        def do_GET(self):
            """Respond to a GET request."""

            path = urlparse(self.path).path

            if path not in self._pages:
                self.send_response(401)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.__write_response_string("Not found :(")
                return

            page = self._pages[path]

            if isinstance(page, str):
                page = {'content': page}

            # HTTP auth
            if not self.__request_passed_authentication(page=page):
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Basic realm="HashServer"')
                self.end_headers()
                return

            if 'redirect' in page:
                redirect_url = page['redirect']
                http_status_code = page.get('http_status_code', HashServer._DEFAULT_REDIRECT_STATUS_CODE)
                self.send_response(http_status_code)
                self.send_header("Content-Type", "text/html; charset=UTF-8")
                self.send_header('Location', redirect_url)
                self.end_headers()
                self.__write_response_string("Redirecting.")
                return

            elif 'callback' in page:
                callback_function = page['callback']

                cookies = {}
                for header_name in self.headers:
                    header_value = self.headers[header_name]
                    if header_name.lower() == 'cookie':
                        cookie_name, cookie_value = header_value.split('=', 1)
                        cookies[cookie_name] = cookie_value

                params = parse_qs(urlparse(self.path).query, keep_blank_values=True)
                for param_name in params:
                    if isinstance(params[param_name], list) and len(params[param_name]) == 1:
                        # If parameter is present only once, return it as a string
                        params[param_name] = params[param_name][0]

                response = callback_function(params, cookies)

                response = decode_object_from_bytes_if_needed(response)

                l.debug("Raw callback response: %s" % str(response))

                if "\r\n\r\n" not in response:
                    raise McHashServerException("Response must include both HTTP headers and data, separated by CRLF.")

                response_headers, response_content = response.split("\r\n\r\n", 1)
                for response_header in response_headers.split("\r\n"):

                    if response_header.startswith('HTTP/'):
                        protocol, http_status_code, http_status_message = response_header.split(' ', maxsplit=2)
                        self.send_response(code=int(http_status_code), message=http_status_message)

                    else:
                        header_name, header_value = response_header.split(':', 1)
                        header_value = header_value.strip()
                        self.send_header(header_name, header_value)

                self.end_headers()
                self.__write_response_string(response_content)

                return

            elif 'content' in page:
                content = page['content']

                headers = page.get('header', 'Content-Type: text/html; charset=UTF-8')
                if not isinstance(headers, list):
                    headers = [headers]
                http_status_code = page.get('http_status_code', HTTPStatus.OK)

                self.send_response(http_status_code)

                for header in headers:
                    header_name, header_value = header.split(':', 1)
                    header_value = header_value.strip()
                    self.send_header(header_name, header_value)

                self.end_headers()
                self.__write_response_string(content)

                return

            else:
                raise McHashServerException('Invalid page: %s' % str(page))

    def __init__(self, port: int, pages: dict):
        """HTTP server's constructor.

        Sample pages dictionary:

            def __sample_callback(params: dict, cookies: dict) -> str:
                response = ""
                response += "HTTP/1.0 200 OK\r\n"
                response += "Content-Type: text/plain\r\n"
                response += "\r\n"
                response += "This is callback."
                return response

            pages = {

                # Simple static pages (served as text/plain)
                '/': 'home',
                '/foo': 'foo',

                # Static page with additional HTTP header entries
                '/bar': {
                    'content': '<html>bar</html>',
                    'header': 'Content-Type: text/html',
                },
                '/bar2': {
                    'content': '<html>bar</html>',
                    'header': [
                        'Content-Type: text/html',
                        'X-Media-Cloud: yes',
                    ]
                },

                # Redirects
                '/foo-bar': {
                    'redirect': '/bar',
                },
                '/localhost': {
                    'redirect': "http://localhost:$_port/",
                },
                '/127-foo': {
                    'redirect': "http://127.0.0.1:$_port/foo",
                    'http_status_code': 303,
                },

                # Callback page
                '/callback': {
                    'callback': __sample_callback,
                },

                # HTTP authentication
                '/auth': {
                    'auth': 'user:password',
                    'content': '...',
                },
            }
        """

        pages = decode_object_from_bytes_if_needed(pages)

        if not port:
            raise McHashServerException("Port is not set.")
        if len(pages) == 0:
            l.warning("Pages dictionary is empty.")

        self.__port = port
        self.__pages = pages

    def __del__(self):
        self.stop()

    def __start_web_server(self):

        def __make_http_handler_with_pages(pages: dict):
            class _HTTPHandlerWithPages(self._HTTPHandler):
                def __init__(self, *args, **kwargs):
                    self._set_pages(pages=pages)
                    super(_HTTPHandlerWithPages, self).__init__(*args, **kwargs)

            return _HTTPHandlerWithPages

        l.info('Starting test web server %s:%d on PID %d' % (self.__host, self.__port, os.getpid()))
        l.debug('Pages: %s' % str(self.__pages))
        server_address = (self.__host, self.__port,)

        handler_class = __make_http_handler_with_pages(pages=self.__pages)

        # Does not use ThreadingMixIn to be able to call Perl callbacks
        self.__http_server = HTTPServer(server_address, handler_class)

        self.__http_server.serve_forever()

    def start(self):
        """Start the webserver."""

        if tcp_port_is_open(port=self.__port):
            raise McHashServerException("Port %d is already open." % self.__port)

        # "threading.Thread()" doesn't work with Perl callers
        self.__http_server_thread = multiprocessing.Process(target=self.__start_web_server)
        self.__http_server_thread.daemon = True
        self.__http_server_thread.start()
        time.sleep(1)

        if not tcp_port_is_open(port=self.__port):
            raise McHashServerException("Port %d is not open." % self.__port)

    def stop(self):
        """Stop the webserver."""

        if not tcp_port_is_open(port=self.__port):
            l.warning("Port %d is not open." % self.__port)
            return

        l.info('Stopping test web server %s:%d on PID %d' % (self.__host, self.__port, os.getpid()))

        # self.__http_server is initialized in a different process, so we're not touching it

        if self.__http_server_thread is None:
            l.warning("HTTP server process is None.")
        else:
            self.__http_server_thread.join(timeout=1)
            self.__http_server_thread.terminate()
            self.__http_server_thread = None
            time.sleep(1)

        if tcp_port_is_open(port=self.__port):
            raise McHashServerException("Port %d is still open." % self.__port)

    def page_url(self, path: str) -> str:
        """Return the URL for the given page on the test server or raise of the path does not exist."""

        path = decode_object_from_bytes_if_needed(path)

        if path is None:
            raise McHashServerException("'path' is None.")

        if not path.startswith('/'):
            path = '/' + path

        path = urlparse(path).path

        if path not in self.__pages:
            raise McHashServerException('No page for path "%s".' % path)

        return 'http://localhost:%d%s' % (self.__port, path)
