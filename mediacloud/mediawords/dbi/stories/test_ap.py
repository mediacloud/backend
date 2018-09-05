from typing import List

from mediawords.dbi.stories.ap import get_ap_medium_name, is_syndicated
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story, add_content_to_test_story
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase


class TestAP(TestDatabaseWithSchemaTestCase):

    @staticmethod
    def __get_ap_sentences() -> List[str]:
        return [
            'AP sentence < 32.',
            'AP sentence >= 32 #1 (with some more text to pad out the length to 32).',
            'AP sentence >= 32 #2 (with some more text to pad out the length to 32).',
            'AP sentence >= 32 #3 (with some more text to pad out the length to 32).',
            'AP sentence >= 32 #4 (with some more text to pad out the length to 32).',
            'AP sentence >= 32 #5 (with some more text to pad out the length to 32).',
            'AP sentence >= 32 #6 (with some more text to pad out the length to 32).',
            'AP sentence >= 32 #7 (with some more text to pad out the length to 32).',
            'AP sentence >= 32 #8 (with some more text to pad out the length to 32).',
            'AP sentence >= 32 #9 (with some more text to pad out the length to 32).',
            'AP sentence >= 32 #10 (with some more text to pad out the length to 32).',
            'AP sentence >= 32 #11 (with some more text to pad out the length to 32).',
            'AP sentence >= 32 #12 (with some more text to pad out the length to 32).',
            'AP sentence >= 32 #13 (with some more text to pad out the length to 32).',
            'AP sentence >= 32 #14 (with some more text to pad out the length to 32).',
        ]

    def setUp(self):
        """Add AP medium and some content so that we can find dup sentences."""
        super().setUp()

        ap_medium = create_test_medium(db=self.db(), label=get_ap_medium_name())
        feed = create_test_feed(db=self.db(), label='feed', medium=ap_medium)
        story = create_test_story(db=self.db(), label='story', feed=feed)

        story['content'] = "\n".join(self.__get_ap_sentences())

        add_content_to_test_story(db=self.db(), story=story, feed=feed)

    def __is_syndicated(self, content: str) -> bool:

        label = content[:64]

        medium = create_test_medium(db=self.db(), label=label)
        feed = create_test_feed(db=self.db(), label=label, medium=medium)
        story = create_test_story(db=self.db(), label=label, feed=feed)

        story['content'] = content

        story = add_content_to_test_story(db=self.db(), story=story, feed=feed)

        return is_syndicated(db=self.db(), story_title=story['title'], story_text=content)

    def test_ap_calls(self):

        ap_sentences = self.__get_ap_sentences()

        ap_content_single_16_sentence = None
        ap_content_32_sentences = []

        for sentence in ap_sentences:

            if ap_content_single_16_sentence is None and len(sentence) < 32:
                ap_content_single_16_sentence = sentence

            if len(sentence) > 32:
                ap_content_32_sentences.append(sentence)

        assert ap_content_single_16_sentence is not None
        assert len(ap_content_32_sentences) > 0

        ap_content_single_32_sentence = ap_content_32_sentences[0]

        assert self.__is_syndicated(content='foo') is False, "Simple unsyndicated story"
        assert self.__is_syndicated(content='(ap)') is True, "Simple ('ap') pattern"

        assert self.__is_syndicated(content="associated press") is False, "Only 'associated press'"
        assert self.__is_syndicated(content="'associated press'") is True, "Quoted 'associated press'"

        assert self.__is_syndicated(
            content="associated press.\n" + ap_content_single_32_sentence
        ) is True, "Associated press and AP sentence"
        assert self.__is_syndicated(
            content="associated press.\n" + ap_content_single_16_sentence
        ) is False, "Associated press and short AP sentence"

        assert self.__is_syndicated(
            content=ap_content_single_32_sentence
        ) is False, 'Single AP sentence'

        assert self.__is_syndicated(
            content="Boston (AP)\n" + ap_content_single_32_sentence
        ) is True, 'AP sentence and AP location'

        assert self.__is_syndicated(
            content=' '.join(ap_sentences)
        ) is True, 'All AP sentences'

        assert is_syndicated(db=self.db(), story_text='foo') is False, "No DB story: simple story"

        assert is_syndicated(db=self.db(), story_text='(ap)') is True, "No DB story: ('ap') story"

        assert is_syndicated(
            db=self.db(),
            story_text=' '.join(self.__get_ap_sentences()),
        ) is True, "No DB story: AP sentences"
