import abc
import os
import re
from typing import Dict, List

from nltk import TweetTokenizer
from sentence_splitter import SentenceSplitter
from Stemmer import Stemmer as PyStemmer

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McLanguageException(Exception):
    """Language class exception."""
    pass


class AbstractLanguage(object, metaclass=abc.ABCMeta):
    """Abstract language class. See doc/README.languages for instructions on how to add a new language."""

    @staticmethod
    @abc.abstractmethod
    def language_code() -> str:
        """Return ISO 639-1 language code, e.g. 'en'."""
        raise NotImplemented("Abstract method.")

    # MC_REWRITE_TO_PYTHON: use set after rewrite to Python
    @abc.abstractmethod
    def stop_words_map(self) -> Dict[str, bool]:
        """Return a map of stop words for the language where the keys are all stop words and the values are all True:

            {
                'stop_word_1': True,
                'stop_word_2': True,
                'stop_word_3': True,
                # ...
            }

        If the stop word list is stored in an external file, you can use self._stop_words_map_from_file() helper.
        """
        raise NotImplementedError("Abstract method.")

    @abc.abstractmethod
    def stem(self, words: List[str]) -> List[str]:
        """Return list of stems for a list of words.

        If PyStemmer module supports the language you're about to add, you can use self._stem_with_pystemmer() helper.
        """
        raise NotImplementedError("Abstract method.")

    @abc.abstractmethod
    def split_text_to_sentences(self, text: str) -> List[str]:
        """Return a list of sentences for a story text (tokenize text into sentences)."""
        raise NotImplementedError("Abstract method.")

    @abc.abstractmethod
    def split_sentence_to_words(self, sentence: str) -> List[str]:
        """Return a list of words for a sentence (tokenize sentence into words).

        If the words in a sentence are separated by spaces (as with most of the languages with a Latin-derived
        alphabet), you can use self._split_sentence_to_words_using_spaces() helper.
        """
        raise NotImplementedError("Abstract method.")


class SpaceSeparatedWordsMixIn(AbstractLanguage, metaclass=abc.ABCMeta):
    """Language in which words are separated by spaces."""

    def __init__(self):
        super().__init__()
        self.__tokenizer = TweetTokenizer(preserve_case=False)

    def split_sentence_to_words(self, sentence: str) -> List[str]:
        """Splits a sentence into words using spaces (for Latin languages)."""
        sentence = decode_object_from_bytes_if_needed(sentence)
        if sentence is None:
            log.warning("Sentence is None.")
            return []

        # Normalize apostrophe so that "it’s" and "it's" get treated identically
        sentence = sentence.replace("’", "'")

        tokens = self.__tokenizer.tokenize(text=sentence)

        def is_word(token_: str) -> bool:
            """Returns True if token looks like a word."""
            if re.match(pattern=r'\w', string=token_, flags=re.UNICODE):
                return True
            else:
                return False

        # TweetTokenizer leaves punctuation in-place
        tokens = [token for token in tokens if is_word(token)]

        return tokens
