import base64
from furl import furl, unquote
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
import multiprocessing
import os
import signal
import socket
from socketserver import ForkingMixIn
import time
from typing import Union, Dict

from mediawords.util.log import create_logger
from mediawords.util.network import tcp_port_is_open, wait_for_tcp_port_to_open, wait_for_tcp_port_to_close
from mediawords.util.perl import decode_object_from_bytes_if_needed

# if no port is specified, start searching for an open port sequentially at this port
START_RANDOM_PORT = 7777


class McHashServerException(Exception):
    """HashServer exception."""
    pass


log = create_logger(__name__)


class HashServer(object):
    """Simple HTTP server that just serves a set of pages defined by a simple dictionary.

    It is intended to make it easy to startup a simple server seeded with programmer defined content.

    Sample pages dictionary:

        def __sample_callback(request: HashServer.Request) -> Union[str, bytes]:
            response = ""
            response += "HTTP/1.0 200 OK\r\n"
            response += "Content-Type: text/plain\r\n"
            response += "\r\n"
            response += "This is callback."
            return response

        pages = {

            # Simple static pages (served as text/plain)
            '/': 'home',    # str
            '/foo': b'foo', # bytes

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

    class Request(object):
        """Request sent to callback."""

        def __init__(self, port: int, method: str, path: str, headers: Dict[str, str], content: str):
            self._method = method
            self._path = path
            self._port = port

            self._headers = dict()
            for name, value in headers.items():
                name = name.lower()
                self._headers[name] = value

            self._content = content

        def method(self) -> str:
            """Return method (GET, POST, ...) of a request."""
            return self._method

        def url(self) -> str:
            """Return full URL of the request."""
            return 'http://%(hostname)s:%(port)d%(path)s' % {
                'hostname': _fqdn(),
                'port': self._port,
                'path': self._path,
            }

        def headers(self) -> Dict[str, str]:
            """Return all headers."""
            return self._headers

        def header(self, name: str) -> Union[str, None]:
            """Return header of a request."""

            name = decode_object_from_bytes_if_needed(name)

            name = name.lower()

            if name in self._headers:
                return self._headers[name]
            else:
                return None

        def content_type(self) -> str:
            """Return Content-Type of a request."""
            return self.header('Content-Type')

        def content(self) -> Union[str, None]:
            """Return POST content of a request."""
            return self._content

        def cookies(self) -> Dict[str, str]:
            """Return cookie dictionary of a request."""
            cookies = {}
            for header_name in self._headers:
                header_value = self._headers[header_name]
                if header_name.lower() == 'cookie':
                    cookie_name, cookie_value = header_value.split('=', 1)
                    cookies[cookie_name] = cookie_value
            return cookies

        def query_params(self) -> Dict[str, str]:
            """Return URL query parameters of a request."""
            uri = furl(self._path)

            # A bit naive because query params might repeat themselves, but it should do for the testing server that
            # this is supposed to be
            query_params = dict(uri.query.asdict()['params'])

            return query_params

    class __ForkingHTTPServer(ForkingMixIn, HTTPServer):

        # Set to underlying TCPServer
        allow_reuse_address = True

        # Some tests (e.g. feed scrape test) request many pages at pretty much the same time, so with the default queue
        # size some of those requests might time out
        request_queue_size = 64

        def serve_forever(self, _=0.5):
            while True:
                self.handle_request()

    # noinspection PyPep8Naming
    class _HTTPHandler(BaseHTTPRequestHandler):
        # Allow HTTP/1.1 connections and so don't wait up on "Expect:" headers
        protocol_version = "HTTP/1.1"

        def _set_port(self, port: int):
            self._port = port

        def _set_pages(self, pages: dict):
            self._pages = pages

        def _set_active_pids(self, active_pids: Dict[int, bool]):
            self._active_pids = active_pids

        def _set_active_pids_lock(self, active_pids_lock: multiprocessing.Lock):
            self._active_pids_lock = active_pids_lock

        def __write_response_string(self, response_string: Union[str, bytes]) -> None:
            if isinstance(response_string, str):
                # If response is string, assume that it's UTF-8; otherwise, write plain bytes to support various
                # encodings
                response_string = response_string.encode('utf-8')
            self.wfile.write(response_string)

        def __request_passed_authentication(self, page: dict) -> bool:
            if b'auth' in page:
                page['auth'] = page[b'auth']

            if 'auth' not in page:
                return True

            page['auth'] = decode_object_from_bytes_if_needed(page['auth'])

            auth_header = self.headers.get('Authorization', None)
            if auth_header is None:
                return False

            if not auth_header.startswith('Basic '):
                log.warning('Invalid authentication header: %s' % auth_header)
                return False

            auth_header = auth_header.strip()
            auth_header_name, auth_header_value_base64 = auth_header.split(' ')
            if len(auth_header_value_base64) == 0:
                log.warning('Invalid authentication header: %s' % auth_header)
                return False

            auth_header_value = base64.b64decode(auth_header_value_base64).decode('utf-8')
            if auth_header_value != page['auth']:
                log.warning("Invalid authentication; expected: %s, actual: %s" % (page['auth'], auth_header_value))
                return False

            return True

        def send_response(self, code: Union[int, HTTPStatus], message=None):
            """Fill in HTTP status message if not set."""
            if message is None:
                if isinstance(code, HTTPStatus):
                    message = code.phrase
                    code = code.value
            BaseHTTPRequestHandler.send_response(self, code=code, message=message)

        def do_POST(self):
            """Respond to a POST request."""
            # Pretend it's a GET (most test pages return static content anyway)
            self.__handle_request_pid_lock_wrapper()

        def do_GET(self):
            """Respond to a GET request."""
            self.__handle_request_pid_lock_wrapper()

        def __handle_request_pid_lock_wrapper(self):
            """Handle request while taking note of the PID of the fork on which the request is running."""
            try:
                self._active_pids_lock.acquire()
                self._active_pids[os.getpid()] = True
            except Exception as ex:
                log.error("Unable to set PID to True: %s" % str(ex))
                raise ex
            finally:
                self._active_pids_lock.release()

            try:
                self.__handle_request()
            except Exception as ex:
                log.info("Request failed: %s" % str(ex))
                raise ex
            finally:

                try:
                    self._active_pids_lock.acquire()
                    self._active_pids[os.getpid()] = False
                except Exception as ex:
                    log.error("Unable to set PID to False: %s" % str(ex))
                    raise ex
                finally:
                    self._active_pids_lock.release()

        @staticmethod
        def __normalize_path(path: str) -> str:
            """Normalize URL path, e.g. convert "//xx/../page to "/page."""
            if path is None:
                raise McHashServerException("Path is None.")
            if len(path) == 0:
                raise McHashServerException("Path is empty.")

            # Strip query string
            path = str(furl('http://somehostname/' + path).path)
            path = os.path.normpath(path)
            path = os.path.realpath(path)

            if len(path) == 0:
                raise McHashServerException("Path is empty after normalization; original path: %s" % path)

            return path

        def __handle_request(self):
            """Handle GET or POST request."""

            path = self.__normalize_path(self.path)

            # Try "/path" and "/path/"
            paths_to_try = [path]
            if path.endswith('/'):
                paths_to_try.append(path[:-1])
            else:
                paths_to_try.append(path + '/')

            # Try URLdecoded versions too
            unquoted_paths = []
            for path_to_try in paths_to_try:
                unquoted_paths.append(unquote(path_to_try))
            paths_to_try = paths_to_try + unquoted_paths

            page = None
            for path_to_try in paths_to_try:
                if path_to_try in self._pages:
                    page = self._pages[path_to_try]
                    path = path_to_try
                    break

            if page is None:
                self.send_response(HTTPStatus.NOT_FOUND)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.__write_response_string("Not found :(")
                return

            page = self._pages[path]

            if isinstance(page, str) or isinstance(page, bytes):
                page = {'content': page}

            # HTTP auth
            if not self.__request_passed_authentication(page=page):
                self.send_response(HTTPStatus.UNAUTHORIZED)
                self.send_header("WWW-Authenticate", 'Basic realm="HashServer"')
                self.end_headers()
                return

            # MC_REWRITE_TO_PYTHON: Decode strings from Perl's bytes
            if b'redirect' in page:
                # noinspection PyTypeChecker
                page['redirect'] = decode_object_from_bytes_if_needed(page[b'redirect'])
            if b'http_status_code' in page:
                # noinspection PyTypeChecker
                page['http_status_code'] = page[b'http_status_code']
            if b'callback' in page:
                # noinspection PyTypeChecker
                page['callback'] = page[b'callback']
            if b'content' in page:
                # noinspection PyTypeChecker
                page['content'] = page[b'content']
            if b'header' in page:
                # noinspection PyTypeChecker
                page['header'] = decode_object_from_bytes_if_needed(page[b'header'])

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

                post_data = None
                if self.command.lower() == 'post':
                    post_data = self.rfile.read(int(self.headers['Content-Length'])).decode('utf-8')

                request = HashServer.Request(
                    port=self._port,
                    method=self.command,
                    path=self.path,
                    headers=dict(self.headers.items()),
                    content=post_data,
                )

                response = callback_function(request)

                if isinstance(response, str):
                    response = str.encode(response)

                # log.debug("Raw callback response: %s" % str(response))

                if b"\r\n\r\n" not in response:
                    raise McHashServerException("Response must include both HTTP headers and data, separated by CRLF.")

                response_headers, response_content = response.split(b"\r\n\r\n", 1)
                for response_header in response_headers.split(b"\r\n"):

                    if response_header.startswith(b'HTTP/'):
                        first_response_line = response_header.split(b' ', maxsplit=2)
                        if not 2 <= len(first_response_line) <= 3:
                            raise McHashServerException("Unexpected response line: %s" % response_header)

                        # protocol = first_response_line[0]
                        http_status_code = first_response_line[1]
                        if len(first_response_line) == 3:
                            http_status_message = first_response_line[2]
                        else:
                            # Some responses might not have status message, e.g. respond with just "HTTP 200"
                            http_status_message = b''
                        self.send_response(
                            code=int(http_status_code.decode('utf-8')),
                            message=http_status_message.decode('utf-8')
                        )

                    else:
                        header_name, header_value = response_header.split(b':', 1)
                        header_value = header_value.strip()
                        self.send_header(header_name.decode('utf-8'), header_value.decode('utf-8'))

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
                log.info("Invalid page for path %s" % self.path)
                raise McHashServerException('Invalid page: %s' % str(page))

    # Default HTTP status code for redirects ("301 Moved Permanently")
    _DEFAULT_REDIRECT_STATUS_CODE = HTTPStatus.MOVED_PERMANENTLY

    __slots__ = [
        '__host',
        '__port',
        '__pages',

        '__http_server_thread',

        '__http_server_active_pids',
        '__http_server_active_pids_lock',
    ]

    def __init__(self, port: int, pages: dict):
        """HTTP server's constructor.

        Arguments:
        port - port to start server on (0 to choose random open port)
        pages - dict describing pages to serve, as described in docstring above

        """

        # Listen publicly because other containers might want to connect to
        # this host, e.g. in tm_mine_topic.t's case
        self.__host = '0.0.0.0'

        self.__http_server_thread = None

        if len(pages) == 0:
            log.warning("Pages dictionary is empty.")

        if port == 0:
            port = START_RANDOM_PORT
            while tcp_port_is_open(port):
                port += 1

        self.__port = port

        # MC_REWRITE_TO_PYTHON: Decode page keys from bytes
        pages = {decode_object_from_bytes_if_needed(k): v for k, v in pages.items()}

        self.__pages = pages

        self.__http_server_active_pids = multiprocessing.Manager().dict()
        self.__http_server_active_pids_lock = multiprocessing.Lock()

    def __del__(self):
        self.stop()

    @staticmethod
    def __make_http_handler(port: int,
                            pages: dict,
                            active_pids: Dict[int, bool],
                            active_pids_lock: multiprocessing.Lock):
        class _HTTPHandlerWithPages(HashServer._HTTPHandler):
            def __init__(self, *args, **kwargs):
                self._set_port(port=port)
                self._set_pages(pages=pages)
                self._set_active_pids(active_pids=active_pids)
                self._set_active_pids_lock(active_pids_lock=active_pids_lock)
                super(_HTTPHandlerWithPages, self).__init__(*args, **kwargs)

        return _HTTPHandlerWithPages

    @staticmethod
    def __start_http_server(host: str,
                            port: int,
                            pages: dict,
                            active_pids: Dict[int, bool],
                            active_pids_lock: multiprocessing.Lock,
                            delay: int):
        """(Run in a fork) Start listening to the port. """
        time.sleep(delay)
        server_address = (host, port,)

        # Add server fork PID to the list of active PIDs to be killed later
        active_pids[os.getpid()] = True

        handler_class = HashServer.__make_http_handler(
            port=port,
            pages=pages,
            active_pids=active_pids,
            active_pids_lock=active_pids_lock,
        )

        http_server = HashServer.__ForkingHTTPServer(server_address, handler_class)

        http_server.serve_forever()

    def start(self, delay: int = 0):
        """Start the webserver.

        Arguments:
        delay - number of seconds to delay before starting server
        """

        if tcp_port_is_open(port=self.__port):
            raise McHashServerException("Port %d is already open." % self.__port)

        log.debug('Starting test web server %s:%d' % (self.__host, self.__port,))
        log.debug('Pages: %s' % str(self.__pages))

        # "threading.Thread()" doesn't work with Perl callers
        self.__http_server_thread = multiprocessing.Process(
            target=self.__start_http_server,
            args=(
                self.__host,
                self.__port,
                self.__pages,
                self.__http_server_active_pids,
                self.__http_server_active_pids_lock,
                delay
            )
        )
        self.__http_server_thread.daemon = True
        self.__http_server_thread.start()

        if delay == 0:
            if not wait_for_tcp_port_to_open(port=self.__port, retries=20, delay=0.1):
                raise McHashServerException("Port %d is not open." % self.__port)

    def stop(self):
        """Stop the webserver."""

        if not tcp_port_is_open(port=self.__port):
            log.warning("Port %d is not open." % self.__port)
            return

        if self.__http_server_thread is None:
            log.warning("HTTP server process is None.")
            return

        log.debug('Stopping test web server %s:%d' % (self.__host, self.__port,))

        # HTTP server itself is running in a fork, and it creates forks for every request which, at the point of killing
        # the server, might be in various states. So, we just SIGKILL all those PIDs in the most gruesome way.
        self.__http_server_active_pids_lock.acquire()
        for pid, value in self.__http_server_active_pids.items():
            if value is True:
                log.debug("Killing PID %d" % pid)
                try:
                    os.kill(pid, signal.SIGKILL)
                    self.__http_server_active_pids[pid] = False
                except OSError as ex:
                    log.error("Unable to kill PID %d: %s" % (pid, str(ex),))
        self.__http_server_active_pids_lock.release()

        self.__http_server_thread.join()
        self.__http_server_thread.terminate()
        self.__http_server_thread = None

        if not wait_for_tcp_port_to_close(port=self.__port, retries=100, delay=0.1):
            raise McHashServerException("Port %d is still open." % self.__port)

    def port(self) -> int:
        """Return the hash server port."""
        return self.__port

    def page_url(self, path: str) -> str:
        """Return the URL for the given page on the test server or raise of the path does not exist."""

        path = decode_object_from_bytes_if_needed(path)

        if path is None:
            raise McHashServerException("'path' is None.")

        if not path.startswith('/'):
            path = '/' + path

        path = str(furl(path).path)

        if path not in self.__pages:
            raise McHashServerException('No page for path "%s" among pages %s.' % (path, str(self.__pages)))

        return 'http://%s:%d%s' % (_fqdn(), self.__port, path)


class McFQDNException(Exception):
    pass


def _fqdn() -> str:
    """Return Fully Qualified Domain Name (hostname -f), e.g. mcquery2.mediacloud.org."""
    # socket.getfqdn() returns goofy results
    hostname = socket.getaddrinfo(socket.gethostname(), 0, flags=socket.AI_CANONNAME)[0][3]
    if hostname is None or len(hostname) == 0:
        raise McFQDNException("Unable to determine FQDN.")
    hostname = hostname.lower()
    if hostname == 'localhost':
        log.warning("FQDN is 'localhost', are you sure that /etc/hosts is set up properly?")

    # Solr (ZooKeeper?) somehow manages to translate underscore to something else, so something like:
    #
    #     foo_bar_baz
    #
    # becomes:
    #
    #     foo/bar_baz:8983/solr
    #
    # Can't explain that.
    if '_' in hostname:
        raise McFQDNException("FQDN contains underscore ('_') which might mess up Solr shard naming")

    try:
        socket.gethostbyname(hostname)
    except socket.error:
        raise McFQDNException("Hostname '%s' does not resolve." % hostname)

    return hostname
