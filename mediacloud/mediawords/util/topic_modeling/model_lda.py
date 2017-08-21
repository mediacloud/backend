import lda
import numpy as np
import logging
import path_helper
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
        self._max_iteration = 10000
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
                        iteration_num: int = None) -> Dict[int, List[str]]:
        """
        summarize the topic of each story based on the frequency of occurrence of each word
        :return: a dictionary of story id
        :rtype: list
        and corresponding list of TOPIC_NUMBER topics (each topic contains WORD_NUMBER words)
        """

        iteration_num = iteration_num if iteration_num else self._max_iteration

        # logging.warning(msg="total_topic_num={}".format(total_topic_num))
        total_topic_num = total_topic_num if total_topic_num else self._stories_number
        logging.warning(msg="total_topic_num={}".format(total_topic_num))

        # turn our token documents into a id <-> term dictionary
        self._model = lda.LDA(n_topics=total_topic_num,
                              n_iter=iteration_num,
                              random_state=self._random_state)

        self._model.fit_transform(self._token_matrix)
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

    def _train(self, topic_num: int, word_num: int = 4, num_iteration: int = None) -> float:
        """
        Avoid unnecessary trainings
        :param topic_num: total number of topics
        :param word_num: number of words for each topic
        :param num_iteration: number of iteration for each time
        :return: the final log likelihood value
        """
        num_iteration = num_iteration if num_iteration \
            else self._max_iteration

        if (not self._model) or (self._model.n_topics != topic_num):
            self.summarize_topic(
                    total_topic_num=topic_num,
                    topic_word_num=word_num,
                    iteration_num=num_iteration)

        return self._model.loglikelihood()

    def tune_with_polynomial(self, topic_word_num: int = 4,
                             score_dict: Dict[float, int] = None) -> int:
        """Tune the model on total number of topics
        until the optimal parameters are found"""

        logging.warning("pre  preparation score_dict:{}".format(score_dict))

        score_dict = self._prepare_sample_points(
            topic_word_num=topic_word_num, score_dict=score_dict)

        logging.warning("post preparation score_dict:{}".format(score_dict))

        max_topic_num = self._locate_max_point(score_dict=score_dict)
        optimal_topic_num = score_dict.get(max(score_dict.keys()))

        if max_topic_num != optimal_topic_num:

            candidates = self._find_candidates(
                optimal=optimal_topic_num,
                maximum=max_topic_num,
                checked=list(score_dict.values()))

            if not candidates:
                return optimal_topic_num

            for candidate in candidates:
                likelihood = self._train(topic_num=candidate, word_num=topic_word_num)
                score_dict[likelihood] = candidate

            return self.tune_with_polynomial(
                topic_word_num=topic_word_num, score_dict=score_dict)

        return optimal_topic_num

    def _prepare_sample_points(self, topic_word_num: int = 4,
                               score_dict: Dict[float, int]=None) -> Dict[float, int]:
        """
        Prepare and store topic_num and corresponding likelihood value in a dictionary
        so that they can be used to build polynomial model
        :param topic_word_num: number of words for each topic
        :param score_dict: A dictionary of likelihood scores : topic_num
        :return: updated score_dict
        """
        topic_num_samples = score_dict.values() if score_dict \
            else [1, int(self._stories_number * 0.5), self._stories_number]

        score_dict = score_dict if score_dict else {}

        logging.warning(topic_num_samples)

        for topic_num in iter(topic_num_samples):
            if topic_num not in score_dict.values():
                likelihood = self._train(topic_num=topic_num, word_num=topic_word_num)
                logging.warning(msg="Num = {}, lh={}".format(topic_num, likelihood))
                score_dict[likelihood] = topic_num

        return score_dict

    @staticmethod
    def _locate_max_point(score_dict: Dict[float, int]=None):
        """
        Use optimalFinder to identify the max point(s)
        and convert it to integer (as it is used as topic_num)
        :param score_dict: score_dict: A dictionary of likelihood scores : topic_num
        :return: topic_num that is predicted to have the max likelihood
        """
        max_point = OptimalFinder().find_extreme(
            x=list(score_dict.values()),
            y=list(score_dict.keys()))[0]
        logging.warning(msg="topic_num before rounding={}".format(max_point))

        int_max_point = 1 if int(round(max_point)) == 0 else int(round(max_point))
        return int_max_point

    def _find_candidates(self, optimal: int, maximum: int, checked: List[int]) -> List[int]:
        """
        Based on the optimal topic_num, maximum point on polynomial diagram,
        generate a new list of candidates as sample points to refine the diagram
        :param optimal: optimal topic_num in the current score_dict
        :param maximum: maximum point in the polynomial diagram
        :param checked: topic_num that has been checked, hence do not need to re-compute
        :return: qualified new candidates to check
        """

        candidates = [optimal, maximum, int((optimal+maximum) * 0.5)]
        qualified = []

        for candidate in candidates:
            # candidate for topic_num should be at least 1
            if candidate < 1:
                continue
            # avoid the long tail for accuracy
            if candidate > self._stories_number:
                continue
            # no need to check candidate again
            if candidate in checked:
                continue
            qualified.append(candidate)

        return qualified


# A sample output
if __name__ == '__main__':
    model = ModelLDA()

    # pool = TokenPool(connect_to_db())
    pool = TokenPool(SampleHandler())

    model.add_stories(pool.output_tokens())

    topic_number = model.tune_with_polynomial()
    print(topic_number)

    evaluation = model.evaluate(topic_num=topic_number)
    print(evaluation)
