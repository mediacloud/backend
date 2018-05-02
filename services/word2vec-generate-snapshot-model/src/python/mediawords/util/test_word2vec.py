import os
import tempfile

import pytest
import shutil
from gensim.models import KeyedVectors

from mediawords.test.db import create_test_medium, create_test_feed, create_test_story, create_test_topic
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
from mediawords.util.word2vec import train_word2vec_model, load_word2vec_model
from mediawords.util.word2vec.exceptions import McWord2vecException
from mediawords.util.word2vec.model_stores import SnapshotDatabaseModelStore
from mediawords.util.word2vec.sentence_iterators import SnapshotSentenceIterator


class TestWord2vec(TestDatabaseWithSchemaTestCase):
    __slots__ = [
        'topics_id',
        'snapshots_id',
    ]

    def setUp(self):
        super().setUp()

        medium = create_test_medium(db=self.db(), label='test')
        feed = create_test_feed(db=self.db(), label='feed', medium=medium)

        # Test stories
        for story_num in range(10):
            story = create_test_story(db=self.db(), label='story-%d' % story_num, feed=feed)
            for sentence_number in range(1, 10):
                self.db().create(table='story_sentences', insert_hash={
                    'stories_id': story['stories_id'],
                    'media_id': medium['media_id'],
                    'publish_date': story['publish_date'],
                    'sentence_number': sentence_number,
                    'sentence': 'One, two, three, four, five, six, seven, eight, nine, ten.',
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
        # Nonexistent snapshot
        with pytest.raises(McWord2vecException):
            SnapshotSentenceIterator(db=self.db(), snapshots_id=123456)

    def test_train_word2vec_model(self):

        sentence_iterator = SnapshotSentenceIterator(db=self.db(), snapshots_id=self.snapshots_id)
        model_store = SnapshotDatabaseModelStore(db=self.db(), snapshots_id=self.snapshots_id)

        models_id = train_word2vec_model(sentence_iterator=sentence_iterator,
                                         model_store=model_store)

        model_data = load_word2vec_model(model_store=model_store, models_id=models_id)
        assert model_data is not None
        assert isinstance(model_data, bytes)

        # Save to file, make sure it loads
        temp_directory = tempfile.mkdtemp()
        temp_model_path = os.path.join(temp_directory, 'word2vec.pickle')
        with open(temp_model_path, mode='wb') as temp_model_file:
            temp_model_file.write(model_data)

        word_vectors = KeyedVectors.load(temp_model_path)

        assert word_vectors is not None
        assert word_vectors['one'] is not None
        assert word_vectors['two'] is not None

        assert 'badger' not in word_vectors

        shutil.rmtree(temp_directory)
