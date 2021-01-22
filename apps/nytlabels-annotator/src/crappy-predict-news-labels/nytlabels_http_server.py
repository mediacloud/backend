#!/usr/bin/env python3

"""
NYTLabels annotator HTTP service.
"""

import dataclasses
import json
import operator
import os
from http import HTTPStatus
from http.server import HTTPServer, BaseHTTPRequestHandler
from sys import argv
from typing import Union, Dict, List

from self_test_input import SELF_TEST_INPUT

from nytlabels import Text2ScaledVectors, MultiLabelPredict


@dataclasses.dataclass(frozen=True)
class _ModelDescriptor(object):
    basename: str
    json_key: str


class _Predictor(object):
    __slots__ = [
        'text2vectors',
        'models',
    ]

    _MODEL_DESCRIPTORS = [
        _ModelDescriptor(basename='all_descriptors', json_key='allDescriptors'),
        _ModelDescriptor(basename='descriptors_3000', json_key='descriptors3000'),
        _ModelDescriptor(basename='descriptors_600', json_key='descriptors600'),
        _ModelDescriptor(basename='descriptors_with_taxonomies', json_key='descriptorsAndTaxonomies'),
        _ModelDescriptor(basename='just_taxonomies', json_key='taxonomies'),
    ]

    def __init__(self):

        pwd = os.path.dirname(os.path.abspath(__file__))
        models_dir = os.path.join(pwd, 'models')
        if not os.path.isdir(models_dir):
            raise RuntimeError(f"Models path should be directory: {models_dir}")

        print("Loading scaler and word2vec...")
        self.text2vectors = Text2ScaledVectors(
            word2vec_shelve_path=os.path.join(models_dir, 'GoogleNews-vectors-negative300.stripped.shelve'),
            scaler_path=os.path.join(models_dir, 'scaler.onnx'),
        )
        print("Scaler and word2vec loaded.")

        print("Loading models...")
        self.models = dict()

        # Make sure all models have the sample sample length and embedding size as we vector text only once
        sample_length = None
        embedding_size = None

        for model_descriptor in self._MODEL_DESCRIPTORS:
            print(f"    Loading '{model_descriptor.basename}'...")
            model = MultiLabelPredict(
                model_path=os.path.join(models_dir, f"{model_descriptor.basename}.onnx"),
                labels_path=os.path.join(models_dir, f"{model_descriptor.basename}.txt"),
            )

            if sample_length and embedding_size:
                assert sample_length == model.sample_length() and embedding_size == model.embedding_size()
            else:
                sample_length = model.sample_length()
                embedding_size = model.embedding_size()

            self.models[model_descriptor] = model
        print("Models loaded.")

        print("Running self-test...\n")
        vectors = self.text2vectors.transform(
            text=SELF_TEST_INPUT,
            sample_length=sample_length,
            embedding_size=embedding_size,
        )
        for model_descriptor in sorted(self._MODEL_DESCRIPTORS, key=operator.attrgetter('basename')):
            print(f"Model '{model_descriptor.basename}':")
            model = self.models[model_descriptor]
            predictions = model.predict(x_matrix=vectors)
            for prediction in predictions:
                print(f"  * Label: {prediction.label}, score: {prediction.score:.6f}")
            assert len(predictions), f"Some predictions should be returned by {model.__class__.__name__}"
            print()
        print("Done running self-test.")


# noinspection PyPep8Naming
class NYTLabelsRequestHandler(BaseHTTPRequestHandler):
    _PREDICTOR = _Predictor()

    def __respond(self, http_status: int, response: Union[dict, list]):
        self.send_response(http_status)
        self.send_header('Content-Type', 'application/json; charset=UTF-8')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode('utf-8'))

    def __respond_with_error(self, http_status: int, message: str):
        self.__respond(http_status=http_status, response={'error': message})

    def do_GET(self):
        # noinspection PyUnresolvedReferences
        self.__respond_with_error(http_status=HTTPStatus.BAD_REQUEST.value, message='GET requests are not supported.')

    def do_HEAD(self):
        # noinspection PyUnresolvedReferences
        self.__respond_with_error(http_status=HTTPStatus.BAD_REQUEST.value, message='HEAD requests are not supported.')

    def _predict(self, text: str) -> Dict[str, List[Dict[str, str]]]:

        # Sample length / embedding size is the same for all models
        first_model = self._PREDICTOR.models[list(self._PREDICTOR.models.keys())[0]]
        sample_length = first_model.sample_length()
        embedding_size = first_model.embedding_size()

        vectors = self._PREDICTOR.text2vectors.transform(
            text=text,
            sample_length=sample_length,
            embedding_size=embedding_size,
        )

        result = dict()

        for model_descriptor, model in self._PREDICTOR.models.items():
            predictions = model.predict(x_matrix=vectors)
            result[model_descriptor.json_key] = [
                {'label': x.label, 'score': "{0:.5f}".format(x.score)} for x in predictions
            ]

        return result

    def do_POST(self):
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

        try:
            result = self._predict(text)
        except Exception as ex:
            # noinspection PyUnresolvedReferences
            self.__respond_with_error(
                http_status=HTTPStatus.INTERNAL_SERVER_ERROR.value,
                message=f"Unable to run models against text: {ex}",
            )
            return

        self.__respond(http_status=HTTPStatus.OK, response=result)


def run(port: int = 8080):
    server_address = ('', port)
    httpd = HTTPServer(server_address, NYTLabelsRequestHandler)
    print(f'Starting NYTLabels annotator on port {port}...')
    httpd.serve_forever()


if __name__ == "__main__":
    if len(argv) == 2:
        run(port=int(argv[1]))
    else:
        run()
