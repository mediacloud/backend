#!/usr/bin/env python

"""
Mock NYTLabels annotator to temporarily replace resource-heavy service.

Works with both Python 2 and 3.
"""

from __future__ import print_function
import json

try:
    # Python 2
    from BaseHTTPServer import HTTPServer, BaseHTTPRequestHandler
except ImportError:
    # Python 3
    from http.server import HTTPServer, BaseHTTPRequestHandler

from sys import argv

SAMPLE_RESPONSE = {
    "allDescriptors": [
        {
            "label": "hurricanes and tropical storms",
            "score": "0.89891",
        },
        {
            "label": "energy and power",
            "score": "0.50804"
        }
    ],
    "descriptors3000": [
        {
            "label": "hurricanes and tropical storms",
            "score": "0.82505"
        },
        {
            "label": "hurricane katrina",
            "score": "0.17088"
        }
    ],
    "descriptors600": [
        {
            "label": " hurricanes and tropical storms",
            "score": "0.92481"
        },
        {
            "label": "electric light and power",
            "score": "0.10210",
        }
    ],

    "descriptorsAndTaxonomies": [
        {
            "label": "top/news",
            "score": "0.82466"
        },
        {
            "label": "hurricanes and tropical storms",
            "score": "0.81941"
        }
    ],
    "taxonomies": [
        {
            "label": "Top/Features/Travel/Guides/Destinations/Caribbean and Bermuda",
            "score": "0.83390"
        },
        {
            "label": "Top/News",
            "score": "0.77210"
        }
    ]
}


# noinspection PyPep8Naming
class MockRequestHandler(BaseHTTPRequestHandler):

    def __respond(self, http_status, response):
        self.send_response(http_status)
        self.send_header('Content-Type', 'application/json; charset=UTF-8')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode('utf-8'))

    def __respond_with_error(self, message):
        self.__respond(http_status=500, response={'error': message})

    def do_GET(self):
        self.__respond_with_error(message='GET requests are not supported.')

    def do_HEAD(self):
        self.__respond_with_error(message='HEAD requests are not supported.')

    def do_POST(self):
        self.__respond(http_status=200, response=SAMPLE_RESPONSE)


def run(port=8080):
    server_address = ('', port)
    httpd = HTTPServer(server_address, MockRequestHandler)
    print('Starting mock CLIFF annotator on port %d...' % port)
    httpd.serve_forever()


if __name__ == "__main__":
    if len(argv) == 2:
        run(port=int(argv[1]))
    else:
        run()
