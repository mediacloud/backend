import numpy as np
import logging
from sklearn import decomposition

# from mediawords.db import connect_to_db
from mediawords.util.topic_modeling.sample_handler import SampleHandler
from mediawords.util.topic_modeling.token_pool import TokenPool
from mediawords.util.topic_modeling.topic_model import BaseTopicModel
from gensim import corpora
from typing import Dict, List


class ModelNMF(BaseTopicModel):
    """Generate topics of each story based on the NMF model
    ModelNMG applies non-negative matrix factorization.
    Whereas LDA is a probabilistic model capable of expressing uncertainty about the
    placement of topics across texts and the assignment of words to topics,
    NMF is a deterministic algorithm which arrives at a single representation of the corpus.
    Because of this, the topic it came up with might be slightly different from LDA."""

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

        # turn our token documents into a id <-> term dictionary
        dictionary = corpora.Dictionary(new_stories_tokens)

        self._vocab = list(dictionary.token2id.keys())

        token_count = []
        for story_tokens in self._stories_tokens:
            token_count.append([story_tokens.count(token) for token in self._vocab])

        self._token_matrix = np.array(token_count)

    def summarize_topic(self, total_topic_num: int = 0, each_topic_num: int = 1,
                        topic_word_num: int = 4, iteration_num: int = 1000) -> Dict[int, list]:
        """
        summarize the topic of each story based on the frequency of occurrence of each word
        :return: a dictionary of story id
        and corresponding list of TOPIC_NUMBER topics (each topic contains WORD_NUMBER words)
        """
        total_topic_num = total_topic_num if total_topic_num else self._stories_number

        self._model = decomposition.NMF(
            n_components=total_topic_num,
            max_iter=iteration_num,
            random_state=self._random_state)

        document_topic = self._model.fit_transform(self._token_matrix)

        components = self._model.components_

        topic_words_list = []
        for topic in components:
            word_idx = np.argsort(topic)[::-1][0:topic_word_num]
            topic_words_list.append([self._vocab[i] for i in word_idx])

        document_topic /= np.sum(document_topic, axis=1, keepdims=True)

        story_topic = {}

        for i in range(self._stories_number):
            top_topic_ids = np.argsort(document_topic[i, :])[::-1][0:each_topic_num]
            story_topic[self._stories_ids[i]] = [topic_words_list[i] for i in top_topic_ids]

        return story_topic

    def evaluate(self):
        pass


# A sample output
if __name__ == '__main__':
    model = ModelNMF()

    # pool = TokenPool(connect_to_db())
    # model.add_stories(pool.output_tokens(1, 0))
    # model.add_stories(pool.output_tokens(5, 2))

    pool = TokenPool(SampleHandler())
    model.add_stories(pool.output_tokens())

    print(model.summarize_topic())
