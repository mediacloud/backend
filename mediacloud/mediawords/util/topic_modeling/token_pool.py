import sys
from os.path import dirname, abspath
sys.path.append(dirname(dirname(dirname(dirname(abspath(__file__))))))

from mediawords.db import connect_to_db
import json
import re


class TokenPool:
    """ Fetch the sentences and break it down to words.
    """
    DB_QUERY = """SELECT stories_id, sentence FROM story_sentences"""
    STOP_WORDS = "lib/MediaWords/Languages/resources/en_stopwords.txt"
    DELIMITERS = "[^\w]"

    def __init__(self):
        """Initialisations"""
        pass

    def fetch_sentences(self):
        """
        Fetch the sentence from DB
        :return: the sentences in json format
        """
        db_connection = connect_to_db()
        sentences_hash = db_connection.query(self.DB_QUERY).hashes()
        sentences_json = json.loads(s=json.dumps(obj=sentences_hash))
        db_connection.disconnect()

        return sentences_json

    def tokenize_sentence(self, sentences):
        """
        Break the sentence down into tokens and group them by article ID
        :param sentences: a json containing sentences and their article id
        :return: a dictionary of articles and words in them
        """
        articles = {}

        for sentence in sentences:
            if sentence['stories_id'] not in articles.keys():
                articles[sentence['stories_id']] = []
            articles[sentence['stories_id']]\
                .append(self.eliminate_symbols(article_sentence=sentence['sentence']))

        return articles

    def eliminate_symbols(self, article_sentence):
        """
        Remove symbols in the given list of words in article
        :param article_sentence: a sentence in an article
        :return: a list of non-symbol tokens
        """
        return re.split(pattern=self.DELIMITERS, string=article_sentence)

    def fetch_stopwords(self):
        """
        Fetch the stopwords from file en_stopwords.txt
        :return: all stopwords in the file
        """
        stopwords = [element[:-1] for element in open(self.STOP_WORDS).readlines()]
        return stopwords

    def eliminate_stopwords(self, article_words):
        """
        Remove stopwords in the given list of words in article
        :param article_words: a list containing all words in an article
        :return: a list of all the meaningful words
        """
        stopwords_file = self.fetch_stopwords()
        # stopwords_package = get_stop_words('en')

        stemmed_tokens_via_file = [word for word in article_words
                                   if ((len(word) > 1) and (word.lower() not in stopwords_file))]

        # stemmed_tokens_via_package = [word for word in article_words
        #                               if ((len(word) > 1)
        #                                   and (word.lower() not in stopwords_package))]

        # print(set(stemmed_tokens_via_file) - set(stemmed_tokens_via_package))
        # print(set(stemmed_tokens_via_package) - set(stemmed_tokens_via_file))

        return stemmed_tokens_via_file

    def output_tokens(self):
        """
        Go though each step to output the tokens of articles
        :return: a dictionary with key as the id of each article and value as the useful tokens
        """
        sentences = self.fetch_sentences()
        all_tokens = self.tokenize_sentence(sentences=sentences)
        stemmed_tokens = {}

        print(all_tokens)

        # counter = 0
        # for article_id, article_tokens in all_tokens.items():
        #
        #     stemmed_tokens[article_id] = self.eliminate_stopwords(article_words=article_tokens)
        #     counter += 1
        #     if counter > 4:
        #         break

        return stemmed_tokens


# A sample output
pool = TokenPool()
print(pool.output_tokens())
