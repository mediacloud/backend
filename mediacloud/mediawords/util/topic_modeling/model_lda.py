import lda
import numpy as np
import logging

# from mediawords.db import connect_to_db
from mediawords.util.topic_modeling.optimal_finder import OptimalFinder
from mediawords.util.topic_modeling.sample_handler import SampleHandler
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
        logging.getLogger("lda").setLevel(logging.WARN)

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

        self._vocab = list(dictionary.token2id.keys())

        token_count = []
        for story_tokens in self._stories_tokens:
            token_count.append([story_tokens.count(token) for token in self._vocab])

        self._token_matrix = np.array(token_count)

    def summarize_topic(self, total_topic_num: int = 0,
                        topic_word_num: int = 4,
                        iteration_num: int = 1000) -> Dict[int, List[str]]:
        """
        summarize the topic of each story based on the frequency of occurrence of each word
        :return: a dictionary of story id
        :rtype: list
        and corresponding list of TOPIC_NUMBER topics (each topic contains WORD_NUMBER words)
        """
        # logging.warning(msg="total_topic_num={}".format(total_topic_num))
        total_topic_num = total_topic_num if total_topic_num else self._stories_number
        logging.warning(msg="total_topic_num={}".format(total_topic_num))

        # turn our token documents into a id <-> term dictionary
        self._model = lda.LDA(n_topics=total_topic_num,
                              n_iter=iteration_num,
                              random_state=self._random_state)

        self._model.fit(self._token_matrix)
        topic_word = self._model.topic_word_
        n_top_words = topic_word_num

        topic_words_list = []
        for i, topic_dist in enumerate(topic_word):
            topic_words_list.append(
                np.array(self._vocab)[np.argsort(topic_dist)][:-(n_top_words + 1):-1])

        doc_topic = self._model.doc_topic_

        story_topic = {}

        for i in range(self._stories_number):
            story_topic[self._stories_ids[i]] = list(topic_words_list[doc_topic[i].argmax()])

        return story_topic

    def evaluate(self, topic_num: int=None) -> List:
        """
        Show the log likelihood for the current model
        :return: the log likelihood value
        """
        if not topic_num:
            topic_num = self._stories_number

        if not self._model:
            logging.warning(msg="Model does not exist, "
                                "train a new one with topic_num = {}".format(topic_num))
            self._train(topic_num=topic_num)

        if self._model.n_topics != topic_num:
            logging.warning(msg="model.n_topics({}) != desired topic_num ({})"
                            .format(self._model.n_topics, topic_num))
            self._train(topic_num=topic_num)

        return [self._model.n_topics, self._model.loglikelihood()]

    def _train(self, topic_num: int, word_num: int = 4, unit_iteration_num: int = 10000) -> float:
        """
        train the model iteratively until the result is stable
        :param topic_num: total number of topics
        :param word_num: number of words for each topic
        :param unit_iteration_num: number of iteration for each time
        :return: the final log likelihood value
        """
        self.summarize_topic(
                total_topic_num=topic_num,
                topic_word_num=word_num,
                iteration_num=unit_iteration_num)

        return self._model.loglikelihood()

        # prev_likelihood = None
        # self._model = None
        #
        # while True:
        #     logging.warning(msg="topic_num={}, prev_likelihood={}"
        #                     .format(topic_num, prev_likelihood))
        #     self.summarize_topic(
        #         total_topic_num=topic_num,
        #         topic_word_num=word_num,
        #         iteration_num=unit_iteration_num)
        #     if (type(prev_likelihood) == float) \
        #             and (prev_likelihood == self._model.loglikelihood()):
        #         return prev_likelihood
        #
        #     prev_likelihood = self._model.loglikelihood()

    def tune_with_iteration(self, topic_word_num: int = 4,
                            topic_num_range: List[int] = None,
                            expansion_factor: int = 2,
                            score_dict: Dict[float, int] = None) -> int:
        """Tune the model on total number of topics
        until the optimal parameters are found"""

        if not topic_num_range:
            topic_num_range = [1, len(self._stories_ids) * expansion_factor]

        if topic_num_range[0] == topic_num_range[1]:
            if topic_num_range[0] == (len(self._stories_ids) * expansion_factor):
                expansion_factor += 1
                return self.tune_with_iteration(
                    topic_word_num=topic_word_num,
                    topic_num_range=sorted([topic_num_range[0],
                                            len(self._stories_ids) * expansion_factor]),
                    expansion_factor=expansion_factor,
                    score_dict=score_dict)

            return topic_num_range[0]

        if not score_dict:
            score_dict = {}

        for topic_num in iter(topic_num_range):
            if topic_num not in score_dict.values():
                likelihood = self._train(topic_num=topic_num, word_num=topic_word_num)
                score_dict[likelihood] = topic_num

        sorted_scores = sorted(score_dict.keys())[::-1]
        sorted_nums = [score_dict.get(score) for score in sorted_scores]
        new_topic_num_boundary = int((sorted_nums[0] + sorted_nums[1]) / 2)

        return self.tune_with_iteration(
            topic_word_num=topic_word_num,
            topic_num_range=sorted([new_topic_num_boundary, sorted_nums[0]]),
            expansion_factor=expansion_factor,
            score_dict=score_dict)

    def tune_with_polynomial(self, topic_word_num: int = 4,
                             topic_num_samples: List[int] = None) -> int:
        """Tune the model on total number of topics
        until the optimal parameters are found"""

        if not topic_num_samples:
            # TODO: Find better initial sample values here
            topic_num_samples = [1,
                                 # int(self._stories_number/4),
                                 int(self._stories_number/2),
                                 self._stories_number,
                                 # int(self._stories_number * 1.5),
                                 self._stories_number * 2]

        score_dict = {}

        for topic_num in iter(topic_num_samples):
            if topic_num not in score_dict.values():
                likelihood = self._train(topic_num=topic_num, word_num=topic_word_num)
                score_dict[likelihood] = topic_num

        optimal_topic_nums = OptimalFinder().find_extreme(
            x=list(score_dict.values()),
            y=list(score_dict.keys()))

        int_topic_nums = [1 if round(num) == 0 else round(num) for num in optimal_topic_nums]

        for num in int_topic_nums:
            if num in score_dict.values():
                continue

            likelihood = self._train(topic_num=num, word_num=topic_word_num)
            score_dict[likelihood] = num

        optimal_topic_num = score_dict.get(max(score_dict.keys()))

        return optimal_topic_num

# A sample output
if __name__ == '__main__':
    model = ModelLDA()

    # pool = TokenPool(connect_to_db())
    pool = TokenPool(SampleHandler())

    all_tokens = pool.output_tokens()
    # print(tokens)
    model.add_stories(all_tokens)
    topic_number = model.tune_with_polynomial()
    print(topic_number)

    evaluation = model.evaluate(topic_num=topic_number)
    print(evaluation)

    for x in range(topic_number-2, topic_number+2):
        evaluation = model.evaluate(topic_num=x)
        print(evaluation)

    evaluation = model.evaluate()
    print(evaluation)

    # evaluation = model.evaluate(topic_num=6)
    # logging.warning(msg="Number of Topics = {}; Likelihood = {}"
    #                     .format(evaluation[0], evaluation[1]))
    # evaluation = model.evaluate(topic_num=1)
    # logging.warning(msg="Number of Topics = {}; Likelihood = {}"
    #                     .format(evaluation[0], evaluation[1]))
    # evaluation = model.evaluate(topic_num=0)
    # logging.warning(msg="Number of Topics = {}; Likelihood = {}"
    #                     .format(evaluation[0], evaluation[1]))

    # print(model.summarize_topic(total_topic_num=topic_number))
