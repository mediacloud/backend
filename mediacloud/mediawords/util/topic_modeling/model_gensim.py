import path_helper
import gensim

from topic_model import BaseTopicModel
from mediawords.util.topic_modeling.token_pool import TokenPool
from mediawords.db import connect_to_db


class ModelGensim(BaseTopicModel):
    """Generate topics of each story based on the LDA model"""

    def __init__(self):
        self._story_number = 0
        self._stories_ids = []
        self._stories_tokens = []
        self._dictionary = None
        self._corpus = []

    def add_stories(self, stories):
        """
        Adding new stories into the model
        :param stories: a dictionary of new stories
        """
        for story in stories.items():
            story_id = story[0]
            story_tokens = story[1]
            self._stories_ids.append(story_id)
            self._stories_tokens.append(story_tokens)

        self._story_number = len(self._stories_ids)

    def summarize_topic(self, topic_number=1, word_number=4, passes=100):
        """
        summarize the topic of each story based on the frequency of occurrence of each word
        :return: a dictionary of story id
        and corresponding list of TOPIC_NUMBER topics (each topic contains WORD_NUMBER words)
        """

        story_topic = {}

        for i in range(len(self._stories_ids)):
            # turn our token documents into a id <-> term dictionary
            self._dictionary = gensim.corpora.Dictionary(self._stories_tokens[i])

            # convert token documents into a document-term matrix
            self._corpus = [self._dictionary.doc2bow(text) for text in self._stories_tokens[i]]

            # generate LDA model
            lda_model = gensim.models.ldamodel.LdaModel(
                corpus=self._corpus, num_topics=topic_number,
                id2word=self._dictionary, passes=passes)

            story_topic[self._stories_ids[i]] \
                = lda_model.print_topics(num_topics=topic_number, num_words=word_number)

        return story_topic


# A sample output
model = ModelGensim()

pool = TokenPool(connect_to_db())
model.add_stories(pool.output_tokens(1, 0))
model.add_stories(pool.output_tokens(5, 1))
print(model.summarize_topic())
