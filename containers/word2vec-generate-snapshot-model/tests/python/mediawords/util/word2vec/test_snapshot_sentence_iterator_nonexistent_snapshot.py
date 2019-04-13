import pytest

from mediawords.util.word2vec import McWord2vecException
from mediawords.util.word2vec.sentence_iterators import SnapshotSentenceIterator

from mediawords.util.word2vec.setup_test_word2vec import TestWord2vec


class TestSnapshotSentenceIteratorNonexistentSnapshot(TestWord2vec):

    def test_snapshot_sentence_iterator_nonexistent_snapshot(self):
        with pytest.raises(McWord2vecException):
            SnapshotSentenceIterator(
                db=self.db,
                snapshots_id=123456,
                stories_id_chunk_size=self.TEST_STORIES_ID_CHUNK_SIZE,
            )
