import path_helper
from gensim import corpora
from mediawords.util.topic_modeling.token_pool import TokenPool
import lda
import numpy as np


class ModelLDA:
    """Generate topics of each story based on the LDA model"""

    STORY_NUMBER = 10
    TOTAL_TOPIC_NUMBER = 10
    WORD_NUMBER = 4
    ITERATION_NUM = 1500
    RANDOM_STATE = 1

    def __init__(self):
        """Initialisations"""
        pass

    def summarize(self):
        """
        summarize the topic of each story based on the frequency of occurrence of each word
        :return: a dictionary of story id
        and corresponding list of TOPIC_NUMBER topics (each topic contains WORD_NUMBER words)
        """
        pool = TokenPool()
        token_items = pool.output_tokens(self.STORY_NUMBER).items()

        texts = []
        titles = []

        for stemmed_tokens in token_items:
            titles.append(stemmed_tokens[0])
            texts.append(
                [tokens for sentence_tokens in stemmed_tokens[1] for tokens in sentence_tokens])

        # turn our token documents into a id <-> term dictionary
        dictionary = corpora.Dictionary(texts)

        vocab = list(dictionary.token2id.keys())

        token_count = []

        for text in texts:
            token_count.append([text.count(token) for token in vocab])

        texts_matrix = np.array(token_count)

        lda_model = lda.LDA(n_topics=self.TOTAL_TOPIC_NUMBER,
                            n_iter=self.ITERATION_NUM,
                            random_state=self.RANDOM_STATE)

        lda_model.fit(texts_matrix)
        topic_word = lda_model.topic_word_
        n_top_words = self.WORD_NUMBER

        topic_words_list = []
        for i, topic_dist in enumerate(topic_word):
            topic_words_list.append(np.array(vocab)[np.argsort(topic_dist)][:-(n_top_words+1):-1])

        doc_topic = lda_model.doc_topic_

        story_topic = {}
        for i in range(self.STORY_NUMBER):
            story_topic[titles[i]] = list(topic_words_list[doc_topic[i].argmax()])

        return story_topic


# A sample output
model = ModelLDA()
print(model.summarize())
