import dataclasses
import multiprocessing
import os
import shelve
from typing import List, Optional

from nltk.data import load as load_nltk_data
from nltk.tokenize.destructive import NLTKWordTokenizer
import numpy as np
import onnxruntime


class _ShelveWord2vecModel(object):
    """Google News word2vec model stored with "shelve" module."""

    __slots__ = [
        '_word2vec',
    ]

    def __init__(self, word2vec_shelve_path: str) -> None:
        self._word2vec = shelve.open(word2vec_shelve_path, flag='r', writeback=False)

    def __contains__(self, key: str) -> bool:
        return key in self._word2vec

    def __getitem__(self, item: str) -> np.ndarray:
        vectors = np.frombuffer(self._word2vec[item], dtype=np.float32)
        return vectors


class Text2ScaledVectors(object):
    __slots__ = [
        '_word2vec',
        '_scaler',
        '_sentence_tokenizer',
        '_word_tokenizer',
    ]

    _PUNCTUATION = '.,:;!?()/\"-<>[]{}|\\@#`$%^&*'

    def __init__(self, word2vec_shelve_path: str, scaler_path: str):

        self._sentence_tokenizer = load_nltk_data("tokenizers/punkt/english.pickle")
        self._word_tokenizer = NLTKWordTokenizer()

        if not os.path.isfile(word2vec_shelve_path):
            raise RuntimeError(f"word2vec shelved file was not found in {word2vec_shelve_path}")
        if not os.path.isfile(scaler_path):
            raise RuntimeError(f"Scaler was not found in {scaler_path}")

        self._word2vec = _ShelveWord2vecModel(word2vec_shelve_path=word2vec_shelve_path)
        self._scaler = onnxruntime.InferenceSession(scaler_path)

    def _word_tokenize(self, text: str) -> List[str]:
        sentences = self._sentence_tokenizer.tokenize(text)
        return [
            token for sent in sentences for token in self._word_tokenizer.tokenize(sent)
        ]

    def transform(self, text: str, sample_length: int, embedding_size: int) -> np.ndarray:

        assert embedding_size == self._scaler.get_inputs()[0].shape[1]

        words = [w.lower() for w in self._word_tokenize(text) if w not in self._PUNCTUATION][:sample_length]
        x_matrix = np.zeros((1, sample_length, embedding_size))

        for i, w in enumerate(words):
            if w in self._word2vec:
                word_vector = self._word2vec[w].reshape(1, -1)
                scaled_vector = self._scaler.run(None, {self._scaler.get_inputs()[0].name: word_vector})[0][0]
                x_matrix[0][i] = scaled_vector

        return x_matrix


@dataclasses.dataclass
class Prediction(object):
    """Single prediction."""
    label: str
    score: float


class MultiLabelPredict(object):
    __slots__ = [
        '_model',
        '_labels',
        '_sample_length',
        '_embedding_size',
    ]

    def __init__(self, model_path: str, labels_path: str, num_threads: Optional[int] = None):
        if not os.path.isfile(model_path):
            raise RuntimeError(f"Model was not found in {model_path}")
        if not os.path.isfile(labels_path):
            raise RuntimeError(f"Model labels were not found in {labels_path}")

        if num_threads is None:
            num_threads = multiprocessing.cpu_count()

        options = onnxruntime.SessionOptions()
        options.intra_op_num_threads = num_threads
        options.execution_mode = onnxruntime.ExecutionMode.ORT_PARALLEL
        options.graph_optimization_level = onnxruntime.GraphOptimizationLevel.ORT_ENABLE_ALL

        self._model = onnxruntime.InferenceSession(path_or_bytes=model_path)
        self._labels = open(labels_path, 'r').read().splitlines()

        _, self._sample_length, self._embedding_size = self._model.get_inputs()[0].shape

    def sample_length(self) -> int:
        return self._sample_length

    def embedding_size(self) -> int:
        return self._embedding_size

    def predict(self, x_matrix: np.ndarray, max_predictions: int = 30) -> List[Prediction]:

        x = {node.name: x_matrix.astype(np.float32) for node in self._model.get_inputs()}

        y_predicted = self._model.run(None, x)[0]

        zipped = zip(self._labels, y_predicted[0])

        raw_predictions = sorted(zipped, key=lambda elem: elem[1], reverse=True)

        predictions = [Prediction(label=x[0], score=x[1]) for x in raw_predictions[:max_predictions]]

        return predictions
