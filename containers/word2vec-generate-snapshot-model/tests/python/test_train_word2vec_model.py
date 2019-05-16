import os
import shutil
import tempfile

import gensim

from word2vec_generate_snapshot_model import train_word2vec_model
from word2vec_generate_snapshot_model.model_stores import SnapshotDatabaseModelStore
from word2vec_generate_snapshot_model.sentence_iterators import SnapshotSentenceIterator
from .setup_test_word2vec import TestWord2vec


class TestTrainWord2vecModel(TestWord2vec):

    def test_train_word2vec_model(self):
        sentence_iterator = SnapshotSentenceIterator(
            db=self.db,
            snapshots_id=self.snapshots_id,
            stories_id_chunk_size=self.TEST_STORIES_ID_CHUNK_SIZE,
        )
        model_store = SnapshotDatabaseModelStore(db=self.db, snapshots_id=self.snapshots_id)

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
