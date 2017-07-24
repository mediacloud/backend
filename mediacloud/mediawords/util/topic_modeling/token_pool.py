import os

from mediawords.db import connect_to_db, handler
from mediawords.util.paths import mc_root_path
from nltk.stem import WordNetLemmatizer
from nltk import word_tokenize
from typing import Dict, List
import warnings


class TokenPool:
    """ Fetch the sentences and break it down to words."""
    _LANGUAGE = 'english'
    _STORY_SENTENCE_TABLE = 'story_sentences'
    _STORY_TABLE = 'stories'
    _MAIN_QUERY \
        = """SELECT story_sentences.stories_id, story_sentences.sentence FROM story_sentences
         INNER JOIN stories ON stories.stories_id = story_sentences.stories_id
         WHERE stories.language = 'en'
         AND story_sentences.stories_id IN
         (SELECT stories_id FROM story_sentences
         ORDER BY story_sentences.stories_id)
         ORDER BY story_sentences.sentence_number"""

    # = """SELECT story_sentences.stories_id, story_sentences.sentence FROM stories
    #  INNER JOIN story_sentences ON stories.stories_id = story_sentences.stories_id
    #  WHERE stories.language = 'en'
    #  ORDER BY stories.stories_id,
    #  story_sentences.sentence_number"""

    _STOP_WORDS \
        = os.path.join(mc_root_path(), "lib/MediaWords/Languages/resources/en_stopwords.txt")
    _MIN_TOKEN_LEN = 1

    def __init__(self, db: handler.DatabaseHandler) -> None:
        """Initialisations"""
        self._stopwords = self._fetch_stopwords()
        self._db = db

    def _fetch_sentence_dictionaries(self, limit: int, offset: int) -> list:
        """
        Fetch the sentence from DB
        :param limit: the number of stories to be output, 0 means no limit
        :return: the sentences in json format
        """

        query_cmd \
            = self._MAIN_QUERY[:-51] \
            + ' LIMIT {} OFFSET {}'.format(limit, offset) \
            + self._MAIN_QUERY[-51:] \
            if limit else self._MAIN_QUERY

        # query_cmd = self._MAIN_QUERY

        sentence_dictionaries = self._db.query(query_cmd).hashes()
        self._db.disconnect()

        return sentence_dictionaries

    def _bind_stories(self, sentences: list) -> Dict[int, list]:
        """
        Break the sentence down into tokens and group them by story ID
        :param sentences: a json containing sentences and their story id
        :return: a dictionary of stories and words in them
        """
        stories = {}

        for sentence in sentences:
            processed_sentence = self._process_sentences(sentence=sentence)

            if not processed_sentence:
                continue

            if sentence['stories_id'] not in stories.keys():
                stories[sentence['stories_id']] = []

            stories[sentence['stories_id']].append(processed_sentence)

        return stories

    def _process_sentences(self, sentence: dict) -> list:
        """
        Eliminate symbols and stopwords
        :param sentence: a raw sentence from story
        :return: a cleaned up sentence
        """
        sentence_tokens = self._tokenize_sentence(story_sentence=sentence['sentence'])

        # First elimination: save time in lemmatization
        useful_tokens = self._eliminate_stopwords(sentence_tokens=sentence_tokens)

        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            lemmatized_tokens \
                = [WordNetLemmatizer().lemmatize(word=token.lower()) for token in useful_tokens]

        del useful_tokens

        # Second elimination:
        # remove the words that are exact match of stop words after lemmatization
        useful_tokens = self._eliminate_stopwords(sentence_tokens=lemmatized_tokens)

        return useful_tokens

    def _tokenize_sentence(self, story_sentence: str) -> list:
        """
        Remove symbols in the given list of words in story
        :param story_sentence: a sentence in an story
        :return: a list of non-symbol tokens
        """
        sliced_sentence = word_tokenize(text=story_sentence, language=self._LANGUAGE)

        return sliced_sentence

    def _fetch_stopwords(self) -> list:
        """
        Fetch the stopwords from file en_stopwords.txt
        :return: all stopwords in the file
        """
        stop_words_file = open(self._STOP_WORDS)
        predefined_stopwords = [element[:-1] for element in stop_words_file.readlines()]
        stop_words_file.close()

        return predefined_stopwords

    def _eliminate_stopwords(self, sentence_tokens: list) -> list:
        """
        Remove stopwords in the given list of words in story
        :param sentence_tokens: a list containing all tokens in a sentence
        :return: a list of all the useful words
        """
        useful_sentence_tokens \
            = [token for token in sentence_tokens
               if ((len(token) > self._MIN_TOKEN_LEN) and (token.lower() not in self._stopwords))]

        return useful_sentence_tokens

    def output_tokens(self, limit: int = 0, offset: int = 0) -> Dict[int, List[List[str]]]:
        """
        Go though each step to output the tokens of stories
        :return: a dictionary with key as the id of each story and value as the useful tokens
        """
        sentence_dictionaries = self._fetch_sentence_dictionaries(limit=limit, offset=offset)
        processed_stories = self._bind_stories(sentences=sentence_dictionaries)

        return processed_stories


# A sample output
if __name__ == '__main__':
    db_connection = connect_to_db()
    pool = TokenPool(db_connection)
    print(pool.output_tokens(1))
    db_connection.disconnect()
