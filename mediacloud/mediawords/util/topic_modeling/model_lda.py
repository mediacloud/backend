from gensim import corpora
import gensim
from mediawords.util.topic_modeling.token_pool import TokenPool


class ModelLDA:
    def __init__(self):
        """Initialisations"""
        pass

    def summerise(self):
        pool = TokenPool()
        token_items = pool.output_tokens().items()

        # print(len(token_items))

        texts = []

        for stemmed_tokens in token_items:
            texts.append(stemmed_tokens[1])

        # turn our tokenized documents into a id <-> term dictionary
        dictionary = corpora.Dictionary(texts)

        # convert tokenized documents into a document-term matrix
        corpus = [dictionary.doc2bow(text) for text in texts]

        # generate LDA model
        lda_model = gensim.models.ldamodel.LdaModel(corpus=corpus, num_topics=1,
                                                    id2word=dictionary, passes=20)

        print(lda_model.print_topics(num_topics=1, num_words=10))


model = ModelLDA()
model.summerise()
