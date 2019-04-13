from mediawords.util.word2vec.sentence_iterators import SnapshotSentenceIterator

from mediawords.util.word2vec.setup_test_word2vec import TestWord2vec


class TestSnapshotSentenceIterator(TestWord2vec):

    def test_snapshot_sentence_iterator(self):
        """Ensure that all of the sentences get returned"""

        sentence_iterator = SnapshotSentenceIterator(
            db=self.db,
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
