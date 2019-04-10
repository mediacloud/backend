#!/usr/bin/env py.test

import os
import tempfile
from typing import List

import gensim
import pytest
import shutil

from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story, create_test_topic
from mediawords.test.testing_database import TestDatabaseTestCase
from mediawords.util.word2vec import train_word2vec_model
from mediawords.util.word2vec.exceptions import McWord2vecException
from mediawords.util.word2vec.model_stores import SnapshotDatabaseModelStore
from mediawords.util.word2vec.sentence_iterators import SnapshotSentenceIterator


class TestWord2vec(TestDatabaseTestCase):
    TEST_STORY_COUNT = 20
    TEST_SENTENCE_PER_STORY_COUNT = 20

    # Use very small stories_id chunk size to test out whether all stories and their sentences are being read
    TEST_STORIES_ID_CHUNK_SIZE = 3

    __slots__ = [
        'topics_id',
        'snapshots_id',
    ]

    def setUp(self):
        super().setUp()

        medium = create_test_medium(db=self.db(), label='test')
        feed = create_test_feed(db=self.db(), label='feed', medium=medium)

        for story_num in range(self.TEST_STORY_COUNT):
            story = create_test_story(db=self.db(), label='story-%d' % story_num, feed=feed)
            for sentence_number in range(1, self.TEST_SENTENCE_PER_STORY_COUNT + 1):
                self.db().create(table='story_sentences', insert_hash={
                    'stories_id': story['stories_id'],
                    'media_id': medium['media_id'],
                    'publish_date': story['publish_date'],
                    'sentence_number': sentence_number,
                    'sentence': 'story {}, sentence {}'.format(story['stories_id'], sentence_number),
                })

        # Test topic
        topic = create_test_topic(db=self.db(), label='test')
        self.topics_id = topic['topics_id']

        self.db().query("""
            INSERT INTO topic_stories (topics_id, stories_id)
            SELECT %(topics_id)s, stories_id FROM stories
        """, {'topics_id': self.topics_id})

        # Test snapshot
        self.snapshots_id = self.db().query("""
            INSERT INTO snapshots (topics_id, snapshot_date, start_date, end_date)
            VALUES (%(topics_id)s, NOW(), NOW(), NOW())
            RETURNING snapshots_id
        """, {'topics_id': self.topics_id}).flat()[0]

        self.db().query("""
            INSERT INTO snap.stories (snapshots_id, media_id, stories_id, url, guid, title, publish_date, collect_date)
            SELECT %(snapshots_id)s, media_id, stories_id, url, guid, title, publish_date, collect_date FROM stories
        """, {'snapshots_id': self.snapshots_id})

    def test_snapshot_sentence_iterator(self):
        """Ensure that all of the sentences get returned"""

        sentence_iterator = SnapshotSentenceIterator(
            db=self.db(),
            snapshots_id=self.snapshots_id,
            stories_id_chunk_size=self.TEST_STORIES_ID_CHUNK_SIZE,
        )
        returned_sentence_count = 0
        seen_sentences = set()

        for sentence_words in sentence_iterator:
            assert sentence_words, "Sentence words should be set."

            sentence = ' '.join(sentence_words)
            assert sentence not in seen_sentences, "Every sentence should be unique."

            returned_sentence_count += 1
            seen_sentences.add(sentence)

        assert returned_sentence_count == self.TEST_STORY_COUNT * self.TEST_SENTENCE_PER_STORY_COUNT, \
            "All of the sentences should have been returned."

    def test_snapshot_sentence_iterator_nonexistent_snapshot(self):
        with pytest.raises(McWord2vecException):
            SnapshotSentenceIterator(
                db=self.db(),
                snapshots_id=123456,
                stories_id_chunk_size=self.TEST_STORIES_ID_CHUNK_SIZE,
            )

    def test_train_word2vec_model(self):

        sentence_iterator = SnapshotSentenceIterator(
            db=self.db(),
            snapshots_id=self.snapshots_id,
            stories_id_chunk_size=self.TEST_STORIES_ID_CHUNK_SIZE,
        )
        model_store = SnapshotDatabaseModelStore(db=self.db(), snapshots_id=self.snapshots_id)

        models_id = train_word2vec_model(sentence_iterator=sentence_iterator,
                                         model_store=model_store)

        model_data = model_store.read_model(models_id=models_id)
        assert model_data is not None
        assert isinstance(model_data, bytes)

        # Save to file, make sure it loads
        temp_directory = tempfile.mkdtemp()
        temp_model_path = os.path.join(temp_directory, 'word2vec.pickle')
        with open(temp_model_path, mode='wb') as temp_model_file:
            temp_model_file.write(model_data)

        word_vectors = gensim.models.KeyedVectors.load_word2vec_format(temp_model_path, binary=True)

        assert word_vectors is not None
        assert word_vectors['story'] is not None
        assert word_vectors['sentence'] is not None

        assert 'badger' not in word_vectors

        shutil.rmtree(temp_directory)


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
