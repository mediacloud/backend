#!/usr/bin/env python3

"""
NYTLabels annotator HTTP service.
"""

import json
from http import HTTPStatus
from http.server import HTTPServer, BaseHTTPRequestHandler
from sys import argv
from typing import Union, Dict, List

from nytlabels import (
    Descriptors600Model,
    Word2vecModel,
    Descriptors3000Model,
    DescriptorsAllModel,
    DescriptorsWithTaxonomiesModel,
    JustTaxonomiesModel,
    Scaler,
)

# Models
MODEL_600 = None
MODEL_3000 = None
MODEL_ALL = None
MODEL_WITH_TAX = None
MODEL_JUST_TAX = None

# https://globalvoices.org/2019/10/08/we-too-love-money-more-than-freedom-south-park-creators-mock-nba-with-a-sarcastic-apology-to-china/
SELF_TEST_INPUT = """
South Park creators mock the NBA with a sarcastic apology to China
===

The producers of the American animated sitcom South Park issued a sarcastic apology to China after Beijing censors
deleted every trace of the cartoon on all video streaming services and social media platforms within mainland China.

The apology, published on October 7, mocks the American National Basketball Association (NBA) for bringing “the Chinese
censors into our homes and into our hearts”. The humorous statement follows a global online row caused by a tweet posted
by Daryl Morey, the general manager of Houston Rockets, a team playing in the NBA, in which he supports the Hong Kong
protesters for more political freedom and oppose Beijing policies.

What triggered the Chinese censors’ action is the latest episode of the series, called “Band in China”. It depicts one
of the main characters, Randy, on a business trip in China during which he lands in jail where he meets Disney
characters including Winnie the Pooh and Piglet.

The episode, which mocks Hollywood for its self-censorship practices in China, was released on October 2, just one day
after the 70th anniversary of the foundation of the People's Republic of China.

The episode shocked some of the cartoon's fans both inside and outside China for its violent scenes, which is typical of
the series since its debut in 1997.
"""


# noinspection PyPep8Naming
class NYTLabelsRequestHandler(BaseHTTPRequestHandler):

    def __init__(self, request, client_address, server):
        super().__init__(request, client_address, server)

        assert MODEL_600, "MODEL_600 is not loaded."
        assert MODEL_3000, "MODEL_3000 is not loaded."
        assert MODEL_ALL, "MODEL_ALL is not loaded."
        assert MODEL_WITH_TAX, "MODEL_WITH_TAX is not loaded."
        assert MODEL_JUST_TAX, "MODEL_JUST_TAX is not loaded."

    def __respond(self, http_status: int, response: Union[dict, list]):
        self.send_response(http_status)
        self.send_header('Content-Type', 'application/json; charset=UTF-8')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode('utf-8'))

    def __respond_with_error(self, http_status: int, message: str):
        self.__respond(http_status=http_status, response={'error': message})

    def do_GET(self):
        self.__respond_with_error(http_status=HTTPStatus.BAD_REQUEST.value, message='GET requests are not supported.')

    def do_HEAD(self):
        self.__respond_with_error(http_status=HTTPStatus.BAD_REQUEST.value, message='HEAD requests are not supported.')

    @staticmethod
    def _predict(text: str) -> Dict[str, List[Dict[str, str]]]:
        result_600 = MODEL_600.predict(text)
        result_3000 = MODEL_3000.predict(text)
        result_all = MODEL_ALL.predict(text)
        result_with_tax = MODEL_WITH_TAX.predict(text)
        result_just_tax = MODEL_JUST_TAX.predict(text)

        result = {
            'descriptors600': [
                {'label': x.label, 'score': "{0:.5f}".format(x.score)} for x in result_600
            ],
            'descriptors3000': [
                {'label': x.label, 'score': "{0:.5f}".format(x.score)} for x in result_3000
            ],
            'allDescriptors': [
                {'label': x.label, 'score': "{0:.5f}".format(x.score)} for x in result_all
            ],
            'descriptorsAndTaxonomies': [
                {'label': x.label, 'score': "{0:.5f}".format(x.score)} for x in result_with_tax
            ],
            'taxonomies': [
                {'label': x.label, 'score': "{0:.5f}".format(x.score)} for x in result_just_tax
            ],
        }

        return result

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        if not content_length:
            self.__respond_with_error(http_status=HTTPStatus.BAD_REQUEST.value, message="Content-Length is not set.")
            return

        post_body = self.rfile.read(content_length)
        if not post_body:
            self.__respond_with_error(http_status=HTTPStatus.BAD_REQUEST.value, message="Unable to read POST body.")
            return

        try:
            payload = json.loads(post_body)
        except Exception as ex:
            self.__respond_with_error(
                http_status=HTTPStatus.BAD_REQUEST.value,
                message=f"Unable to decode request JSON: {ex}",
            )
            return

        if not isinstance(payload, dict):
            self.__respond_with_error(http_status=HTTPStatus.BAD_REQUEST.value,
                                      message="Payload JSON is not a dictionary.")
            return

        text = payload.get('text', None)
        if text is None:
            self.__respond_with_error(
                http_status=HTTPStatus.BAD_REQUEST.value,
                message="Payload doesn't have 'text' attribute.",
            )
            return

        try:
            result = self._predict(text)
        except Exception as ex:
            self.__respond_with_error(
                http_status=HTTPStatus.INTERNAL_SERVER_ERROR.value,
                message=f"Unable to run models against text: {ex}",
            )
            return

        self.__respond(http_status=HTTPStatus.OK, response=result)


def run(port: int = 8080):
    global MODEL_600
    global MODEL_3000
    global MODEL_ALL
    global MODEL_WITH_TAX
    global MODEL_JUST_TAX

    print("Loading models...")
    word2vec_model = Word2vecModel()
    scaler = Scaler()
    MODEL_600 = Descriptors600Model(word2vec_model=word2vec_model, scaler=scaler)
    MODEL_3000 = Descriptors3000Model(word2vec_model=word2vec_model, scaler=scaler)
    MODEL_ALL = DescriptorsAllModel(word2vec_model=word2vec_model, scaler=scaler)
    MODEL_WITH_TAX = DescriptorsWithTaxonomiesModel(word2vec_model=word2vec_model, scaler=scaler)
    MODEL_JUST_TAX = JustTaxonomiesModel(word2vec_model=word2vec_model, scaler=scaler)
    print("Models loaded.")

    print("Running self-test...\n")
    for model in [MODEL_600, MODEL_3000, MODEL_ALL, MODEL_WITH_TAX, MODEL_JUST_TAX]:
        print(f"Model {model.__class__.__name__}:")
        predictions = model.predict(SELF_TEST_INPUT)
        for prediction in predictions:
            print(f"  * Label: {prediction.label}, score: {prediction.score:.6f}")
        assert len(predictions), f"Some predictions should be returned by {model.__class__.__name__}"
        print()
    print("Done running self-test.")

    server_address = ('', port)
    httpd = HTTPServer(server_address, NYTLabelsRequestHandler)
    print(f'Starting NYTLabels annotator on port {port}...')
    httpd.serve_forever()


if __name__ == "__main__":
    if len(argv) == 2:
        run(port=int(argv[1]))
    else:
        run()
