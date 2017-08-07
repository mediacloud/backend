import lda
import numpy as np
import logging

# from mediawords.db import connect_to_db
from sample_handler import SampleHandler
from mediawords.util.topic_modeling.token_pool import TokenPool
from mediawords.util.topic_modeling.topic_model import BaseTopicModel
from gensim import corpora
from typing import Dict, List


class ModelLDA(BaseTopicModel):
    """Generate topics of each story based on the LDA model
    ModelLDA operates on all stories.
    It groups the words that often occur together among all stories into a topic
    and assign that each story with the topic that has the closest match. This means:
    1. We can only select the total number of topics among all stories
    2. The number of topics for each story is not fixed. Theoretically speaking,
    some stories' topic words might not be the best match of the content of that story.
    (i.e. some times we might find two stories have exactly the same topic)
    3. Since the topics are compared among all stories,
    the difference between the topics are more significant than ModelGensim"""

    def __init__(self) -> None:
        """Initialisations"""
        super().__init__()
        self._stories_ids = []
        self._stories_tokens = []
        self._vocab = []
        self._token_matrix = np.empty
        self._stories_number = 0
        self._random_state = 1
        logging.getLogger("lda").setLevel(logging.WARNING)

    def add_stories(self, stories: Dict[int, List[List[str]]]) -> None:
        """
        Adding new stories into the model
        :param stories: a dictionary of new stories
        """
        new_stories_tokens = []

        for story in stories.items():
            story_id = story[0]
            story_tokens = story[1]
            self._stories_ids.append(story_id)
            new_stories_tokens.append(
                [tokens for sentence_tokens in story_tokens for tokens in sentence_tokens])

        self._stories_tokens += new_stories_tokens
        self._stories_number = len(self._stories_ids)
        self._recompute_matrix(new_stories_tokens=new_stories_tokens)

    def _recompute_matrix(self, new_stories_tokens: list) -> None:
        """
        Recompute the token matrix based on new tokens in new stories
        :param new_stories_tokens: a list of new tokens
        """
        dictionary = corpora.Dictionary(new_stories_tokens)

        self.vocab = list(dictionary.token2id.keys())

        token_count = []
        for story_tokens in self._stories_tokens:
            token_count.append([story_tokens.count(token) for token in self.vocab])

        self.token_matrix = np.array(token_count)

    def summarize_topic(self, total_topic_num: int = 0,
                        topic_word_num: int = 4, iteration_num: int = 1000) -> Dict[int, List[str]]:
        """
        summarize the topic of each story based on the frequency of occurrence of each word
        :return: a dictionary of story id
        :rtype: list
        and corresponding list of TOPIC_NUMBER topics (each topic contains WORD_NUMBER words)
        """
        total_topic_num = total_topic_num if total_topic_num else self._stories_number

        # turn our token documents into a id <-> term dictionary
        lda_model = lda.LDA(n_topics=total_topic_num,
                            n_iter=iteration_num,
                            random_state=self._random_state)

        lda_model.fit(self.token_matrix)
        topic_word = lda_model.topic_word_
        n_top_words = topic_word_num

        topic_words_list = []
        for i, topic_dist in enumerate(topic_word):
            topic_words_list.append(
                np.array(self.vocab)[np.argsort(topic_dist)][:-(n_top_words + 1):-1])

        doc_topic = lda_model.doc_topic_

        story_topic = {}

        for i in range(self._stories_number):
            story_topic[self._stories_ids[i]] = list(topic_words_list[doc_topic[i].argmax()])

        return story_topic


# A sample output
if __name__ == '__main__':
    model = ModelLDA()
    # pool = TokenPool(connect_to_db())
    # model.add_stories(pool.output_tokens(1, 0))
    # model.add_stories(pool.output_tokens(5, 2))
    pool = TokenPool(SampleHandler())
    model.add_stories(pool.output_tokens())
    print(model.summarize_topic())
