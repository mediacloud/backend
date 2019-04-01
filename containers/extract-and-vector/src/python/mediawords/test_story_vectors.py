import re

from mediawords.db import connect_to_db
# noinspection PyProtectedMember
from mediawords.story_vectors import (
    medium_is_locked,
    _clean_sentences,
    _get_sentences_from_story_text,
    _delete_story_sentences,
    _get_unique_sentences_in_story,
    _get_db_escaped_story_sentence_dicts,
    _insert_story_sentences,
)
from mediawords.test.db.create import (
    create_test_medium,
    create_test_feed,
    create_test_story,
    create_download_for_story,
)
from mediawords.test.test_database import TestDatabaseTestCase


class TestStoryVectors(TestDatabaseTestCase):

    def setUp(self) -> None:
        super().setUp()

        self.test_medium = create_test_medium(self.db(), 'downloads test')
        self.test_feed = create_test_feed(self.db(), 'downloads test', self.test_medium)
        self.test_story = create_test_story(self.db(), label='downloads est', feed=self.test_feed)
        self.test_download = create_download_for_story(self.db(), feed=self.test_feed, story=self.test_story)

    def test_medium_is_locked(self):
        media_id = self.test_medium['media_id']

        db_locked_session = connect_to_db()

        assert medium_is_locked(db=self.db(), media_id=media_id) is False

        db_locked_session.query("SELECT pg_advisory_lock(%(media_id)s)", {'media_id': media_id})
        assert medium_is_locked(db=self.db(), media_id=media_id) is True

        db_locked_session.query("SELECT pg_advisory_unlock(%(media_id)s)", {'media_id': media_id})
        assert medium_is_locked(db=self.db(), media_id=media_id) is False

        db_locked_session.disconnect()

    def test_delete_story_sentences(self):
        test_sentence_count = 7

        sentence_number = 0
        for _ in range(test_sentence_count):
            self.db().insert(
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

        assert len(self.db().select(
            table='story_sentences',
            what_to_select='*',
            condition_hash={},
        ).hashes()) == test_sentence_count

        _delete_story_sentences(db=self.db(), story=self.test_story)

        assert len(self.db().select(
            table='story_sentences',
            what_to_select='*',
            condition_hash={},
        ).hashes()) == 0

    def test_get_db_escaped_story_sentence_dicts(self):
        escaped_sentences = _get_db_escaped_story_sentence_dicts(
            db=self.db(),
            story=self.test_story,
            sentences=[

                # Single quotes
                "It's toasted!",

                # Non-English language
                'Įlinkdama fechtuotojo špaga sublykčiojusi pragręžė apvalų arbūzą.',

            ]
        )
        assert len(escaped_sentences) == 2

        # We expect strings to be returned instead of integers because this will be join()ed together into a SQL query
        assert escaped_sentences[0]['media_id'] == str(self.test_medium['media_id'])
        assert escaped_sentences[0]['stories_id'] == str(self.test_story['stories_id'])
        assert re.match(
            pattern=r"^'\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d'::timestamp$",
            string=escaped_sentences[0]['publish_date'],
        )
        assert escaped_sentences[0]['sentence'] == "'It''s toasted!'"
        assert escaped_sentences[0]['sentence_number'] == '0'
        assert escaped_sentences[0]['language'] == "'en'"

        assert escaped_sentences[1]['sentence_number'] == '1'
        assert escaped_sentences[1]['language'] == "'lt'"

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
            db=self.db(),
            story=self.test_story,
            sentences=sentences,
        )

        assert len(inserted_sentences) == 2  # Minus the duplicate sentence
        assert inserted_sentences[0] == sentences[0]
        assert inserted_sentences[1] == sentences[2]

        db_sentences = self.db().query("""
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

        test_story_2 = create_test_story(self.db(), label='test story 1', feed=self.test_feed)

        # Try inserting same sentences again, see if is_dup gets set
        inserted_sentences = _insert_story_sentences(
            db=self.db(),
            story=test_story_2,
            sentences=sentences,
        )
        assert len(inserted_sentences) == 0

        db_sentences = self.db().query("""
            SELECT *
            FROM story_sentences
            ORDER BY sentence_number
        """).hashes()
        assert len(db_sentences) == 2
        assert db_sentences[0]['is_dup'] is True
        assert db_sentences[1]['is_dup'] is True

        # Make sure no_dedup_sentences works
        inserted_sentences = _insert_story_sentences(
            db=self.db(),
            story=test_story_2,
            sentences=sentences,
            no_dedup_sentences=True,
        )
        assert len(inserted_sentences) == len(sentences)

        db_sentences = self.db().query("""
            SELECT *
            FROM story_sentences
            ORDER BY stories_id, sentence_number
        """).hashes()

        # Two sentences with no_dedup_sentences=False, plus three sentences with no_dedup_sentences=True
        assert len(db_sentences) == 5


def test_clean_sentences():
    good_sentences = [
        # Normal ones (should go through)
        "The quick brown fox jumps over the lazy dog.",
        "Įlinkdama fechtuotojo špaga sublykčiojusi pragręžė apvalų arbūzą.",
        "いろはにほへと ちりぬるを わかよたれそ つねならむ うゐのおくやま けふこえて あさきゆめみし ゑひもせす",
        "視野無限廣，窗外有藍天",

        # Very short but not ASCII
        "視",
    ]

    bad_sentences = [
        # Too short
        "this",
        "this.",

        # Too weird
        "[{[{[{[{[{",
    ]

    cleaned_sentences = _clean_sentences(sentences=good_sentences + bad_sentences)

    assert cleaned_sentences == good_sentences


def test_get_sentences_from_story_text():
    story_text = """
        The banded stilt (Cladorhynchus leucocephalus) is a nomadic wader of the stilt and avocet family,
        Recurvirostridae, native to Australia. It gets its name from the red-brown breast band found on breeding adults,
        though this is mottled or entirely absent in non-breeding adults and juveniles.
    """

    sentences = _get_sentences_from_story_text(story_text=story_text, story_lang='en')
    assert len(sentences) == 2


def test_get_unique_sentences_in_story():
    assert _get_unique_sentences_in_story(['c', 'c', 'b', 'a', 'a']) == ['c', 'b', 'a']
