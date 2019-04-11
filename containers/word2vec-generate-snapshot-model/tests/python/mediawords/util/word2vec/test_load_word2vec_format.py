#!/usr/bin/env py.test

import os
from typing import List

import gensim


def _word2vec_test_data_dir() -> str:
    """Return path to word2vec testing data directory."""
    return '/mediacloud/test-data/word2vec/'


def sample_word2vec_model_path() -> str:
    """Return path to where the sample word2vec model is to be stored."""
    return os.path.join(_word2vec_test_data_dir(), 'sample_model.bin')


def sample_word2vec_gensim_version_path() -> str:
    """Return path to where the sample word2vec model's gensim version is to be stored."""
    return os.path.join(_word2vec_test_data_dir(), 'gensim_version.txt')


def sample_word2vec_model_dictionary() -> List[List[str]]:
    """Return sample dictionary for word2vec sample model generation."""
    return [
        ['human', 'interface', 'computer'],
        ['survey', 'user', 'computer', 'system', 'response', 'time'],
        ['eps', 'user', 'interface', 'system'],
        ['system', 'human', 'system', 'eps'],
        ['user', 'response', 'time'],
        ['trees'],
        ['graph', 'trees'],
        ['graph', 'minors', 'trees'],
        ['graph', 'minors', 'survey'],
    ]


def test_load_word2vec_format():
    """Test loading a C-compatible word2vec model pre-generated with (potentially) older gensim version.

    Use tools/word2vec/generate_sample_word2vec_model.py to regenerate the sample word2vec model.
    """

    model_path = sample_word2vec_model_path()
    dictionary = sample_word2vec_model_dictionary()
    sample_word = dictionary[0][0]

    word_vectors = gensim.models.KeyedVectors.load_word2vec_format(model_path, binary=True)

    assert word_vectors is not None
    assert sample_word in word_vectors
    assert 'not_in_model' not in word_vectors
