import path_helper
from gensim import corpora
import gensim
from mediawords.util.topic_modeling.token_pool import TokenPool


class ModelLDA:
    """Generate topics of each story based on the LDA model"""
    STORY_NUMBER = 5
    TOPIC_NUMBER = 1
    WORD_NUMBER = 4

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

        story_topic = {}

        for stemmed_tokens in token_items:
            texts = stemmed_tokens[1]

            # turn our token documents into a id <-> term dictionary
            dictionary = corpora.Dictionary(texts)

            # convert token documents into a document-term matrix
            corpus = [dictionary.doc2bow(text) for text in texts]

            # generate LDA model
            lda_model = gensim.models.ldamodel.LdaModel(corpus=corpus, num_topics=self.TOPIC_NUMBER,
                                                        id2word=dictionary, passes=100)

            story_topic[stemmed_tokens[0]] \
                = lda_model.print_topics(num_topics=self.TOPIC_NUMBER, num_words=self.WORD_NUMBER)

        return story_topic


# A sample output
model = ModelLDA()
print(model.summarize())
