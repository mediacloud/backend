# import path_helper # uncomment this line if 'No module named XXX' error occurs
import unittest

from mediawords.util.topic_modeling.token_pool import TokenPool
from mediawords.util.topic_modeling.model_gensim import ModelGensim
from mediawords.db import connect_to_db


class TestModelGensim(unittest.TestCase):
    """
    Test the methods in ..model_gensim.py
    """

    def setUp(self):
        """
        Prepare the token pool
        """
        self.LIMIT = 5
        self.OFFSET = 1
        token_pool = TokenPool(connect_to_db())
        self._article_tokens = token_pool.output_tokens(limit=self.LIMIT, offset=self.OFFSET)
        self._lda_model = ModelGensim()
        self._lda_model.add_stories(self._article_tokens)

    def test_one_to_one_relationship(self):
        """
        Test if there is one-to-one relationship for articles and topics
        (i.e. no mysteries topic id or missing article id)
        """
        topic_ids = self._lda_model.summarize_topic().keys()
        article_ids = self._article_tokens.keys()

        for topic_id in topic_ids:
            unittest.TestCase.assertTrue(
                self=self,
                expr=(topic_id in article_ids),
                msg="Mysteries topic id: {}".format(topic_id))

        for article_id in article_ids:
            unittest.TestCase.assertTrue(
                self=self,
                expr=(article_id in topic_ids),
                msg="Missing article id: {}".format(article_id))

        unittest.TestCase.assertEqual(self=self, first=len(topic_ids), second=len(article_ids))


if __name__ == '__main__':
    unittest.main()
