# noinspection PyProtectedMember
from extract_and_vector.story_vectors import _delete_story_sentences
from .setup_test_story_vectors import TestStoryVectors


class TestDeleteStorySentences(TestStoryVectors):

    def test_delete_story_sentences(self):
        test_sentence_count = 7

        sentence_number = 0
        for _ in range(test_sentence_count):
            self.db.insert(
                table='story_sentences',
                insert_hash={
                    'stories_id': self.test_story['stories_id'],
                    'media_id': self.test_medium['media_id'],
                    'sentence_number': sentence_number,
                    'sentence': 'Foo.',
                    'publish_date': self.test_story['publish_date'],
                    'language': 'en',
                })
            sentence_number += 1

        assert len(self.db.select(
            table='story_sentences',
            what_to_select='*',
            condition_hash={},
        ).hashes()) == test_sentence_count

        _delete_story_sentences(db=self.db, story=self.test_story)

        assert len(self.db.select(
            table='story_sentences',
            what_to_select='*',
            condition_hash={},
        ).hashes()) == 0
