import re

from mediawords.story_vectors.setup_test_story_vectors import TestStoryVectors
# noinspection PyProtectedMember
from mediawords.story_vectors import _get_db_escaped_story_sentence_dicts


class TestDbEscapedStorySentenceDicts(TestStoryVectors):

    def test_get_db_escaped_story_sentence_dicts(self):
        escaped_sentences = _get_db_escaped_story_sentence_dicts(
            db=self.db,
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
