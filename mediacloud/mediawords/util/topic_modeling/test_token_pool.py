import unittest
import os

from mediawords.util.paths import mc_root_path
from mediawords.util.topic_modeling.token_pool import TokenPool


class TestTokenPool(unittest.TestCase):
    """
    Test the methods in ..token_pool.py
    """
    _SAMPLE_STORIES \
        = os.path.join(mc_root_path(),
                       "mediacloud/mediawords/util/topic_modeling/sample_stories.txt")

    def setUp(self):
        """
        Prepare the token pool
        """
        self._LIMIT = 1
        self._OFFSET = 1
        sample_file = open(self._SAMPLE_STORIES)
        token_pool = TokenPool(sample_file)
        self._article_tokens = token_pool.output_tokens(limit=self._LIMIT, offset=self._OFFSET)
        sample_file.close()
        self._STOP_WORDS \
            = os.path.join(mc_root_path(), "lib/MediaWords/Languages/resources/en_stopwords.txt")

    def test_lower_case(self):
        """
        Test if all tokens are in lower cases
        """
        for sentence_tokens in list(self._article_tokens.values()):
            for tokens in sentence_tokens:
                for token in tokens:
                    unittest.TestCase.assertTrue(
                        self=self,
                        expr=any(char.isdigit() for char in token) or token.islower(),
                        msg=token)

    def test_no_stop_words(self):
        """
        Test if there is no stop words in the tokens
        """
        with open(self._STOP_WORDS) as stop_words_file:
            stop_words = stop_words_file.readlines()
        stop_words_file.close()

        for sentence_tokens in list(self._article_tokens.values()):
            for tokens in sentence_tokens:
                for token in tokens:
                    unittest.TestCase.assertTrue(
                        self=self,
                        expr=token not in stop_words,
                        msg=token)

    def test_correct_limit(self):
        """
        Test if the correct number of stories are tokenized
        """
        unittest.TestCase.assertEqual(
            self=self, first=self._LIMIT, second=len(self._article_tokens))


if __name__ == '__main__':
    unittest.main()
