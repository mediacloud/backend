"""
Prediction models.
"""

import abc
import os
from typing import List

import gensim
import onnxruntime
from nltk.tokenize import word_tokenize
import numpy as np

DEFAULT_MAX_PREDICTIONS = 30
"""Max. predictions to come up with."""


class MissingModelsException(Exception):
    """Exception that's thrown when the models are missing."""
    pass


def _default_models_dir() -> str:
    """
    Return default path to directory with models.
    :return: Path to directory with models.
    """
    pwd = os.path.dirname(os.path.abspath(__file__))
    models_dir = os.path.join(pwd, 'models')
    assert os.path.isdir(models_dir), f"Models path should be directory: {models_dir}"
    return models_dir


class Prediction(object):
    """Single prediction."""

    __slots__ = [
        'label',
        'score',
    ]

    def __init__(self, label: str, score: float):
        self.label = label
        self.score = score


class _BaseLoader(object, metaclass=abc.ABCMeta):

    @abc.abstractmethod
    def _initialize_model(self, models_dir: str) -> None:
        """
        Initialize model and get it ready for prediction.
        :param models_dir: Directory to where models are to be found.
        """
        raise NotImplemented("Abstract method.")

    def __init__(self, models_dir: str = None):
        """
        Initialize model.
        :param models_dir: (optional) Directory to where models are to be found.
        """
        if not models_dir:
            models_dir = _default_models_dir()
        if not os.path.isdir(models_dir):
            raise MissingModelsException(f"Models directory does not exist at {models_dir}")

        print(f"Loading model {self.__class__.__name__}...")
        self._initialize_model(models_dir=models_dir)
        print(f"Loaded model {self.__class__.__name__}.")


class _BaseModel(_BaseLoader, metaclass=abc.ABCMeta):
    """Base model class."""

    @abc.abstractmethod
    def predict(self, text: str, max_predictions: int = DEFAULT_MAX_PREDICTIONS) -> List[Prediction]:
        """
        Predict text.
        :param text: Text to run predictions against.
        :param max_predictions: Max. predictions to come up with.
        :return: Predictions.
        """
        raise NotImplemented("Abstract method.")


class Word2vecModel(_BaseModel):
    """Google News word2vec model."""

    __slots__ = [
        '_model',
    ]

    _BASE_NAME = "GoogleNews-vectors-negative300.keyedvectors"

    def _initialize_model(self, models_dir: str) -> None:
        vectors_bin_path = os.path.join(models_dir, self._BASE_NAME)
        vectors_npy_path = os.path.join(models_dir, self._BASE_NAME + '.vectors.npy')

        if not os.path.isfile(vectors_bin_path):
            raise MissingModelsException(f"Vectors file does not exist at {vectors_bin_path}")
        if not os.path.isfile(vectors_npy_path):
            raise MissingModelsException(f"Vectors .npy file does not exist at {vectors_npy_path}")
        gensim.models.keyedvectors.Word2VecKeyedVectors
        self._model = gensim.models.KeyedVectors.load(vectors_bin_path)

    def predict(self, text: str, max_predictions: int = DEFAULT_MAX_PREDICTIONS) -> List[Prediction]:
        raw_predictions = self._model.predict(text)
        predictions = [Prediction(label=x[0], score=x[1]) for x in raw_predictions[:max_predictions]]
        return predictions

    def raw_word2vec_model(self):
        """
        Return raw KeyedVectors model.
        :return: Raw KeyedVectorsModel.
        """
        return self._model


class Scaler(_BaseLoader):
    __slots__ = [
        '_scaler',
    ]

    def _initialize_model(self, models_dir: str) -> None:
        """
        Initialize model and get it ready for prediction.
        :param models_dir: Directory to where models are to be found.
        """
        # Load pre-trained scaler used by all the models
        scaler_path = os.path.join(models_dir, 'scaler.onnx')
        if not os.path.isfile(scaler_path):
            raise MissingModelsException(f"Scaler was not found in {scaler_path}")

        self._scaler = onnxruntime.InferenceSession(scaler_path)

    def raw_scaler(self):
        return self._scaler


class _TopicDetectionBaseModel(_BaseModel, metaclass=abc.ABCMeta):
    """Base topic detection model."""

    __slots__ = [
        '_raw_word2vec_model',
        '_raw_scaler',
        '_model',
        '_labels',
    ]

    _PUNCTUATION = '.,:;!?()/\"-<>[]{}|\\@#`$%^&*'

    @staticmethod
    @abc.abstractmethod
    def _model_basename() -> str:
        """
        Return file basename (without extension) of model to load
        :return: File basename of model to load, e.g. 'descriptors_600'.
        """
        raise NotImplemented("Abstract method")

    def _initialize_model(self, models_dir: str) -> None:

        assert self._raw_word2vec_model, "Raw word2vec model is unset."
        assert self._raw_scaler, "Scaler is unset."

        model_basename = self._model_basename()
        assert model_basename, "Model basename is empty."

        model_path = os.path.join(models_dir, f'{model_basename}.onnx')
        model_labels = os.path.join(models_dir, f'{model_basename}.txt')

        if not os.path.isfile(model_path):
            raise MissingModelsException(f"Model was not found in {model_path}")
        if not os.path.isfile(model_labels):
            raise MissingModelsException(f"Model labels were not found in {model_labels}")

        self._model = onnxruntime.InferenceSession(model_path)
        self._labels = open(model_labels, 'r').read().splitlines()

    def __init__(self, word2vec_model: Word2vecModel, scaler, models_dir: str = None):
        assert word2vec_model, "word2vec model is unset."
        assert scaler, "Scaler is unset."

        self._raw_word2vec_model = word2vec_model.raw_word2vec_model()
        self._raw_scaler = scaler.raw_scaler()

        super().__init__(models_dir=models_dir)

    def predict(self, text: str, max_predictions: int = DEFAULT_MAX_PREDICTIONS) -> List[Prediction]:

        _, sample_length, embedding_size = self._model.get_inputs()[0].shape
        assert embedding_size == self._raw_scaler.get_inputs()[0].shape[1]

        words = [w.lower() for w in word_tokenize(text) if w not in self._PUNCTUATION][:sample_length]
        x_matrix = np.zeros((1, sample_length, embedding_size))

        for i, w in enumerate(words):
            if w in self._raw_word2vec_model:
                word_vector = self._raw_word2vec_model[w].reshape(1, -1)
                scaled_vector = self._raw_scaler.run(None, {self._raw_scaler.get_inputs()[0].name: word_vector})[0][0]
                x_matrix[0][i] = scaled_vector

        x = {node.name: x_matrix.astype(np.float32) for node in self._model.get_inputs()}

        y_predicted = self._model.run(None, x)[0]

        zipped = zip(self._labels, y_predicted[0])

        raw_predictions = sorted(zipped, key=lambda elem: elem[1], reverse=True)

        predictions = [Prediction(label=x[0], score=x[1]) for x in raw_predictions[:max_predictions]]

        return predictions


class Descriptors600Model(_TopicDetectionBaseModel):

    @staticmethod
    def _model_basename() -> str:
        return 'descriptors_600'


class Descriptors3000Model(_TopicDetectionBaseModel):

    @staticmethod
    def _model_basename() -> str:
        return 'descriptors_3000'


class DescriptorsAllModel(_TopicDetectionBaseModel):

    @staticmethod
    def _model_basename() -> str:
        return 'all_descriptors'


class DescriptorsWithTaxonomiesModel(_TopicDetectionBaseModel):

    @staticmethod
    def _model_basename() -> str:
        return 'descriptors_with_taxonomies'


class JustTaxonomiesModel(_TopicDetectionBaseModel):

    @staticmethod
    def _model_basename() -> str:
        return 'just_taxonomies'
