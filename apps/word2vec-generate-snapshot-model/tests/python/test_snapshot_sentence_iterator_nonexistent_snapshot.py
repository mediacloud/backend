import pytest

from word2vec_generate_snapshot_model import McWord2vecException
from word2vec_generate_snapshot_model.sentence_iterators import SnapshotSentenceIterator

from .setup_test_word2vec import TestWord2vec


class TestSnapshotSentenceIteratorNonexistentSnapshot(TestWord2vec):

    def test_snapshot_sentence_iterator_nonexistent_snapshot(self):
        with pytest.raises(McWord2vecException):
            SnapshotSentenceIterator(
                db=self.db,
                topics_id=123456,
                snapshots_id=123456,
                stories_id_chunk_size=self.TEST_STORIES_ID_CHUNK_SIZE,
            )
