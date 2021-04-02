#!/usr/bin/env python3

"""
NYTLabels annotator HTTP service.
"""

import argparse
import json
import os
import pprint
from http import HTTPStatus
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Union, Dict, List, Optional, Type

from self_test_input import SELF_TEST_INPUT

from nytlabels import Text2ScaledVectors, MultiLabelPredict

# For each key there must exist a model ONNX file and a list of labels with a given basename
ALL_MODELS = [
    'allDescriptors',
    'descriptors3000',
    'descriptors600',
    'descriptorsAndTaxonomies',
    'taxonomies',
]


class _Predictor(object):
    __slots__ = [
        '__text2vectors',
        '__models',
    ]

    def __init__(self, num_threads: Optional[int]):

        pwd = os.path.dirname(os.path.abspath(__file__))
        models_dir = os.path.join(pwd, 'models')
        if not os.path.isdir(models_dir):
            raise RuntimeError(f"Models path should be directory: {models_dir}")

        print("Loading scaler and word2vec...")
        self.__text2vectors = Text2ScaledVectors(
            word2vec_shelve_path=os.path.join(models_dir, 'GoogleNews-vectors-negative300.stripped.shelve'),
            scaler_path=os.path.join(models_dir, 'scaler.onnx'),
        )
        print("Scaler and word2vec loaded.")

        print("Loading models...")
        self.__models = dict()

        # Make sure all models have the sample sample length and embedding size as we vector text only once
        sample_length = None
        embedding_size = None

        for model_name in ALL_MODELS:
            print(f"    Loading '{model_name}'...")
            model = MultiLabelPredict(
                model_path=os.path.join(models_dir, f"{model_name}.onnx"),
                labels_path=os.path.join(models_dir, f"{model_name}.txt"),
                num_threads=num_threads,
            )

            if sample_length and embedding_size:
                assert sample_length == model.sample_length() and embedding_size == model.embedding_size()
            else:
                sample_length = model.sample_length()
                embedding_size = model.embedding_size()

            self.__models[model_name] = model
        print("Models loaded.")

        print("Running self-test...\n")
        test_result = self.predict(text=SELF_TEST_INPUT, enabled_model_names=ALL_MODELS)
        pp = pprint.PrettyPrinter(indent=4, width=1024)
        pp.pprint(test_result)
        print("Done running self-test.")

    def predict(self, text: str, enabled_model_names: List[str]) -> Dict[str, List[Dict[str, str]]]:

        # Sample length / embedding size is the same for all models
        first_model = self.__models[list(self.__models.keys())[0]]
        sample_length = first_model.sample_length()
        embedding_size = first_model.embedding_size()

        vectors = self.__text2vectors.transform(
            text=text,
            sample_length=sample_length,
            embedding_size=embedding_size,
        )

        result = dict()

        for model_name in enabled_model_names:
            model = self.__models[model_name]
            predictions = model.predict(x_matrix=vectors)
            result[model_name] = [
                {'label': x.label, 'score': "{0:.5f}".format(x.score)} for x in predictions
            ]

        return result


# noinspection PyPep8Naming
class NYTLabelsRequestHandler(BaseHTTPRequestHandler):
    # Allow HTTP/1.1 connections and so don't wait up on "Expect:" headers
    protocol_version = "HTTP/1.1"

    _PREDICTOR = None

    @classmethod
    def initialize_predictor(cls, num_threads: Optional[int]) -> None:
        assert not cls._PREDICTOR, "Predictor is already initialized."
        cls._PREDICTOR = _Predictor(num_threads=num_threads)

    def __init__(self, *args, **kwargs):
        assert self._PREDICTOR, "You need to initialize the predictor before setting this class as a request handler."
        super(NYTLabelsRequestHandler, self).__init__(*args, **kwargs)

    def __respond(self, http_status: int, response: Union[dict, list]):
        raw_response = json.dumps(response).encode('utf-8')
        self.send_response(http_status)
        self.send_header('Content-Type', 'application/json; charset=UTF-8')
        self.send_header('Content-Length', str(len(raw_response)))
        self.end_headers()
        self.wfile.write(raw_response)

    def __respond_with_error(self, http_status: int, message: str):
        self.__respond(http_status=http_status, response={'error': message})

    # If the request handler's protocol_version is set to "HTTP/1.0" (the default) and the client tries connecting via
    # HTTP/1.1 and sends an "Expect: 100-continue" header, the client will then wait for a bit (curl waits for a second)
    # for "100 Continue" which the server will never send (due to it being configured to support HTTP/1.0 only),
    # therefore the whole request will take a one whole second more.
    #
    # Please note that when enabling HTTP/1.1, one has to send Content-Length in their responses.
    def __check_expect_header(self):
        expect = self.headers.get('Expect', "")
        if expect.lower() == "100-continue":
            if not (self.protocol_version >= "HTTP/1.1" and self.request_version >= "HTTP/1.1"):
                print((
                    "WARNING: due to server / client misconfiguration, client sent Expect: header "
                    "and is waiting for a response, possibly delaying the whole request."""
                ))

    def do_GET(self):
        # noinspection PyUnresolvedReferences
        self.__respond_with_error(http_status=HTTPStatus.BAD_REQUEST.value, message='GET requests are not supported.')

    def do_HEAD(self):
        # noinspection PyUnresolvedReferences
        self.__respond_with_error(http_status=HTTPStatus.BAD_REQUEST.value, message='HEAD requests are not supported.')

    def do_POST(self):

        self.__check_expect_header()

        content_length = int(self.headers.get('Content-Length', 0))
        if not content_length:
            # noinspection PyUnresolvedReferences
            self.__respond_with_error(http_status=HTTPStatus.BAD_REQUEST.value, message="Content-Length is not set.")
            return

        post_body = self.rfile.read(content_length)
        if not post_body:
            # noinspection PyUnresolvedReferences
            self.__respond_with_error(http_status=HTTPStatus.BAD_REQUEST.value, message="Unable to read POST body.")
            return

        try:
            payload = json.loads(post_body)
        except Exception as ex:
            # noinspection PyUnresolvedReferences
            self.__respond_with_error(
                http_status=HTTPStatus.BAD_REQUEST.value,
                message=f"Unable to decode request JSON: {ex}",
            )
            return

        if not isinstance(payload, dict):
            # noinspection PyUnresolvedReferences
            self.__respond_with_error(http_status=HTTPStatus.BAD_REQUEST.value,
                                      message="Payload JSON is not a dictionary.")
            return

        text = payload.get('text', None)
        if text is None:
            # noinspection PyUnresolvedReferences
            self.__respond_with_error(
                http_status=HTTPStatus.BAD_REQUEST.value,
                message="Payload doesn't have 'text' attribute.",
            )
            return

        models = payload.get('models', None)
        if models is None:
            enabled_model_names = ALL_MODELS
        else:
            enabled_model_names = []
            for model_name in models:
                if model_name not in ALL_MODELS:
                    # noinspection PyUnresolvedReferences
                    self.__respond_with_error(
                        http_status=HTTPStatus.BAD_REQUEST.value,
                        message=f"Model '{model_name}' was not found.",
                    )
                    return
                if model_name in enabled_model_names:
                    # noinspection PyUnresolvedReferences
                    self.__respond_with_error(
                        http_status=HTTPStatus.BAD_REQUEST.value,
                        message=f"Model '{model_name}' is duplicate.",
                    )
                    return

                enabled_model_names.append(model_name)

        if not enabled_model_names:
            # noinspection PyUnresolvedReferences
            self.__respond_with_error(
                http_status=HTTPStatus.BAD_REQUEST.value,
                message="List of enabled models is empty.",
            )
            return

        try:
            result = self._PREDICTOR.predict(text=text, enabled_model_names=enabled_model_names)
        except Exception as ex:
            # noinspection PyUnresolvedReferences
            self.__respond_with_error(
                http_status=HTTPStatus.INTERNAL_SERVER_ERROR.value,
                message=f"Unable to run models against text: {ex}",
            )
            return

        self.__respond(http_status=HTTPStatus.OK, response=result)


def make_nytlabels_request_handler_class(num_threads: Optional[int]) -> Type[NYTLabelsRequestHandler]:
    class CustomNYTLabelsRequestHandler(NYTLabelsRequestHandler):
        pass

    CustomNYTLabelsRequestHandler.initialize_predictor(num_threads=num_threads)

    return CustomNYTLabelsRequestHandler


def main():
    parser = argparse.ArgumentParser(description="Start NYTLabels annotator web service.")
    parser.add_argument("-p", "--port", type=int, required=False, default=8080,
                        help="Port to listen to")
    parser.add_argument("-t", "--num_threads", type=int, required=False,
                        help="Threads that the model runtime should spawn")
    args = parser.parse_args()

    server_address = ('', args.port)
    handler_class = make_nytlabels_request_handler_class(num_threads=args.num_threads)
    httpd = HTTPServer(server_address, handler_class)
    print(f'Starting NYTLabels annotator on port {args.port}...')
    httpd.serve_forever()


if __name__ == "__main__":
    main()
