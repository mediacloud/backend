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


class SentenceSplitterMixIn(AbstractLanguage, metaclass=abc.ABCMeta):
    """Language which is supported by "sentence_splitter" Python module."""

    # Max. text length to try to split into sentences
    __MAX_TEXT_LENGTH = 1024 * 1024

    def __init__(self):
        """Constructor."""
        super().__init__()

        # SentenceSplitter instance (lazy initialized)
        self.__sentence_splitter = None

    def split_text_to_sentences(self, text: str) -> List[str]:
        """Splits text into sentences with "sentence_splitter" module.

        Language code will be read from language_code() method."""
        text = decode_object_from_bytes_if_needed(text)

        language_code = self.language_code()

        if self.__sentence_splitter is None:
            try:
                self.__sentence_splitter = SentenceSplitter(language=language_code)
            except Exception as ex:
                raise McLanguageException(
                    "Unable to initialize sentence splitter for language '%s': %s" % (language_code, str(ex),)
                )

        if text is None:
            log.warning("Text is None.")
            return []

        # Sentence tokenizer can hang for a very long on very long text, and anything greater than 1 MB is more likely
        # to be an artifact than actual text
        if len(text) > self.__MAX_TEXT_LENGTH:
            text = text[:self.__MAX_TEXT_LENGTH]

        # Only "\n\n" (not a single "\n") denotes the end of sentence, so remove single line breaks
        text = re.sub('([^\n])\n([^\n])', r"\1 \2", text, flags=re.DOTALL)

        # Remove asterisks from lists
        text = re.sub(r" {2}\*", " ", text, flags=re.DOTALL)

        text = re.sub(r"\n\s\*\n", "\n\n", text, flags=re.DOTALL)
        text = re.sub(r"\n\n\n\*", "\n\n", text, flags=re.DOTALL)
        text = re.sub(r"\n\n", "\n", text, flags=re.DOTALL)

        # Replace tabs with spaces
        text = re.sub(r"\t", " ", text, flags=re.DOTALL)

        # Replace non-breaking spaces with normal spaces
        text = re.sub(r"\xa0", " ", text, flags=re.DOTALL)

        # Replace multiple spaces with a single space
        text = re.sub(" +", " ", text, flags=re.DOTALL)

        # The above regexp and HTML stripping often leave a space before the period at the end of a sentence
        text = re.sub(r" +\.", ".", text, flags=re.DOTALL)

        # We see lots of cases of missing spaces after sentence ending periods (has a hardcoded lower limit of
        # characters because otherwise it breaks Portuguese "a.C.." abbreviations and such)
        text = re.sub(r"([a-z]{2,})\.([A-Z][a-z]+)", r"\1. \2", text, flags=re.DOTALL)

        # Replace Unicode's "…" with "..."
        text = text.replace("…", "...")

        # Trim whitespace from start / end of the whole string
        text = text.strip()

        # FIXME: fix "bla bla... yada yada"? is it two sentences?
        # FIXME: fix "text . . some more text."?

        if len(text) == 0:
            log.debug("Text is empty after processing it.")
            return []

        # Split to sentences
        sentences = self.__sentence_splitter.split(text=text)

        non_empty_sentences = []
        # Trim whitespace from start / end of each of the sentences
        for sentence in sentences:
            sentence = sentence.strip()

            if len(sentence) > 0:
                non_empty_sentences.append(sentence)

        return non_empty_sentences
