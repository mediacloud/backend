#!/usr/bin/env python3

"""

Single-threaded HTTP server that extracts article's HTML from a full page HTML.

Accepts POST requests to "/extract" endpoint with body JSON:

    {
        "html": "<html><title>Title</title><body><p>Paragraph.</p></html>"
    }

On success, returns HTTP 200 and extracted HTML:

    {
        "extracted_html": "Title\n\n<body id=\"readabilityBody\"><p>Paragraph.</p></body>",
        "extractor_version": "readability-lxml-0.6.1"
    }

On errors, returns HTTP 4xx / 5xx and error message:

    {
        "error": "You're using it wrong."
    }

"""

import argparse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

from mediawords.util.parse_json import encode_json, decode_json
from mediawords.util.log import create_logger
from extract_article_from_page import extract_article_from_page, extractor_name

log = create_logger(__name__)

_MAX_HTML_LENGTH = 4 * 1024 * 1024
"""Extractor will refuse to extract HTML pages bigger than this."""

_MAX_REQUEST_LENGTH = _MAX_HTML_LENGTH + (10 * 1024)
"""HTTP server will refuse to serve requests larger than this."""


class ServerHandler(BaseHTTPRequestHandler):
    _API_ENDPOINT_PATH = "/extract"

    def __json_response(self, status: int, response: dict) -> bytes:
        json_response = encode_json(response)
        encoded_json_response = json_response.encode("UTF-8", errors="replace")

        self.send_response(status)
        self.send_header("Content-Type", "application/json; encoding=UTF-8")
        self.send_header("Content-Length", len(encoded_json_response))
        self.end_headers()

        return encoded_json_response

    def __error_response(self, status: int, message: str) -> bytes:
        log.error(message)
        return self.__json_response(status=status, response={"error": message})

    def __success_response(self, status: int, response: dict) -> bytes:
        response = self.__json_response(status=status, response=response)
        log.info(f"Returning response ({len(response)} bytes)")
        return response

    def __post(self) -> bytes:
        uri = urlparse(self.path)
        if uri.path != self._API_ENDPOINT_PATH:
            return self.__error_response(
                status=HTTPStatus.NOT_FOUND.value,
                message=f"Only {self._API_ENDPOINT_PATH} is implemented.",
            )

        content_length = int(self.headers.get('Content-Length', 0))

        log.info(f"Received extraction request ({content_length} bytes)...")

        if not content_length:
            return self.__error_response(
                status=HTTPStatus.LENGTH_REQUIRED.value,
                message="Content-Length header is not set.",
            )

        if content_length > _MAX_REQUEST_LENGTH:
            return self.__error_response(
                status=HTTPStatus.REQUEST_ENTITY_TOO_LARGE.value,
                message=f"Request is larger than {_MAX_REQUEST_LENGTH} bytes."
            )

        encoded_body = self.rfile.read(content_length)

        try:
            json_body = encoded_body.decode('utf-8', errors='replace')
        except Exception as ex:
            return self.__error_response(
                status=HTTPStatus.BAD_REQUEST.value,
                message=f"Unable to decode request body: {ex}",
            )

        try:
            body = decode_json(json_body)
        except Exception as ex:
            return self.__error_response(
                status=HTTPStatus.BAD_REQUEST.value,
                message=f"Unable to decode request JSON: {ex}",
            )

        if "html" not in body:
            return self.__error_response(
                status=HTTPStatus.BAD_REQUEST.value,
                message="Request JSON doesn't have 'html' key.",
            )

        html = body["html"]

        try:
            extracted_html = extract_article_from_page(html)
        except Exception as ex:
            return self.__error_response(
                status=HTTPStatus.BAD_REQUEST.value,
                message=f"Unable to extract article HTML from page HTML: {ex}"
            )

        response = {
            'extracted_html': extracted_html,
            'extractor_version': extractor_name(),
        }

        return self.__success_response(
            status=HTTPStatus.OK.value,
            response=response,
        )

    # noinspection PyPep8Naming
    def do_POST(self) -> None:
        self.wfile.write(self.__post())

    # noinspection PyPep8Naming
    def do_GET(self):
        return self.__error_response(
            status=HTTPStatus.METHOD_NOT_ALLOWED.value,
            message="Try POST instead!",
        )


def start_http_server(port: int) -> None:
    """Start HTTP server."""

    log.info(f"Listening on port {port}...")

    server = HTTPServer(('', port), ServerHandler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

    log.info("Shutting down...")
    server.server_close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Start page HTML -> article HTML extraction HTTP server.")
    parser.add_argument("-p", "--port", type=int, default=80, help="Port to listen to")
    args = parser.parse_args()

    start_http_server(port=args.port)
