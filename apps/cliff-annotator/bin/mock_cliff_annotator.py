#!/usr/bin/env python

"""
Mock CLIFF annotator to temporarily replace resource-heavy service.

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
    "milliseconds": 231,
    "results": {
        "organizations": [
            {
                "count": 2,
                "name": "MIT",
            },
            {
                "count": 2,
                "name": "Harvard",
            },
        ],
        "people": [
            {
                "count": 7,
                "name": "Tim Cook",
            },
            {
                "count": 5,
                "name": "Bill Gates",
            },
        ],
        "places": {
            "focus": {
                "cities": [
                    {
                        "countryCode": "US",
                        "countryGeoNameId": "6252001",
                        "featureClass": "P",
                        "featureCode": "PPLA2",
                        "id": 5391959,
                        "lat": 37.77493,
                        "lon": -122.41942,
                        "name": "San Francisco",
                        "population": 805235,
                        "score": 1,
                        "stateCode": "CA",
                        "stateGeoNameId": "5332921",
                    },
                ],
                "countries": [
                    {
                        "countryCode": "US",
                        "countryGeoNameId": "6252001",
                        "featureClass": "A",
                        "featureCode": "PCLI",
                        "id": 6252001,
                        "lat": 39.76,
                        "lon": -98.5,
                        "name": "United States",
                        "population": 310232863,
                        "score": 10,
                        "stateCode": "00",
                        "stateGeoNameId": "",
                    }
                ],
                "states": [
                    {
                        "countryCode": "US",
                        "countryGeoNameId": "6252001",
                        "featureClass": "A",
                        "featureCode": "ADM1",
                        "id": 4273857,
                        "lat": 38.50029,
                        "lon": -98.50063,
                        "name": "Kansas",
                        "population": 2740759,
                        "score": 10,
                        "stateCode": "KS",
                        "stateGeoNameId": "4273857",
                    },
                ],
            },
        },
        "mentions": [
            {
                "confidence": 1,
                "countryCode": "US",
                "countryGeoNameId": "6252001",
                "featureClass": "A",
                "featureCode": "ADM1",
                "id": 4273857,
                "lat": 38.50029,
                "lon": -98.50063,
                "name": "Kansas",
                "population": 2740759,
                "source": {
                    "charIndex": 162,
                    "string": "Kansas",
                },
                "stateCode": "KS",
                "stateGeoNameId": "4273857",
            },
        ],
    },
    "status": "ok",
    "version": "2.4.1",
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
