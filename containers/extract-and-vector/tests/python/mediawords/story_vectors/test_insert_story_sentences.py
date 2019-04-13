# noinspection PyProtectedMember
from mediawords.story_vectors import _insert_story_sentences
from mediawords.test.db.create import create_test_story
from mediawords.story_vectors.setup_test_story_vectors import TestStoryVectors


class TestInsertStorySentences(TestStoryVectors):

    def test_insert_story_sentences(self):
        sentences = [
            # Single quotes
            "It's toasted!",

            # Duplicate sentence within story
            "It's toasted!",

            # Non-English language
            'Įlinkdama fechtuotojo špaga sublykčiojusi pragręžė apvalų arbūzą.',
        ]

        inserted_sentences = _insert_story_sentences(
            db=self.db,
            story=self.test_story,
            sentences=sentences,
        )

        assert len(inserted_sentences) == 2  # Minus the duplicate sentence
        assert inserted_sentences[0] == sentences[0]
        assert inserted_sentences[1] == sentences[2]

        db_sentences = self.db.query("""
            SELECT *
            FROM story_sentences
            ORDER BY sentence_number
        """).hashes()
        assert len(db_sentences) == 2

        assert db_sentences[0]['media_id'] == self.test_medium['media_id']
        assert db_sentences[0]['stories_id'] == self.test_story['stories_id']
        assert db_sentences[0]['sentence_number'] == 0
        assert db_sentences[0]['sentence'] == sentences[0]
        assert db_sentences[0]['publish_date'] == self.test_story['publish_date']
        assert db_sentences[0]['language'] == 'en'
        assert db_sentences[0]['is_dup'] is None

        assert db_sentences[1]['media_id'] == self.test_medium['media_id']
        assert db_sentences[1]['stories_id'] == self.test_story['stories_id']
        assert db_sentences[1]['sentence_number'] == 1
        assert db_sentences[1]['sentence'] == sentences[2]
        assert db_sentences[1]['publish_date'] == self.test_story['publish_date']
        assert db_sentences[1]['language'] == 'lt'
        assert db_sentences[1]['is_dup'] is None

        test_story_2 = create_test_story(self.db, label='test story 1', feed=self.test_feed)

        # Try inserting same sentences again, see if is_dup gets set
        inserted_sentences = _insert_story_sentences(
            db=self.db,
            story=test_story_2,
            sentences=sentences,
        )
        assert len(inserted_sentences) == 0

        db_sentences = self.db.query("""
            SELECT *
            FROM story_sentences
            ORDER BY sentence_number
        """).hashes()
        assert len(db_sentences) == 2
        assert db_sentences[0]['is_dup'] is True
        assert db_sentences[1]['is_dup'] is True

        # Make sure no_dedup_sentences works
        inserted_sentences = _insert_story_sentences(
            db=self.db,
            story=test_story_2,
            sentences=sentences,
            no_dedup_sentences=True,
        )
        assert len(inserted_sentences) == len(sentences)

        db_sentences = self.db.query("""
            SELECT *
            FROM story_sentences
            ORDER BY stories_id, sentence_number
        """).hashes()

        # Two sentences with no_dedup_sentences=False, plus three sentences with no_dedup_sentences=True
        assert len(db_sentences) == 5
