"""

Media Cloud does not need any special language support to collect data for a given language. For example, we have no
language support for Albanian, but the system is still capable of crawling and collecting Albanian language content.

The language support described in this file is mostly used for two purposes. Most importantly, the sentence parsing is
used to break each story into the sentences which are stores in the story_sentences table. That table is used as the
source of content for the source exports to Solr and is also used in various places in the code as a representation of
the text of each story.

Secondarily, the tokenizing, stemming, and stop word removal are used for the word counting, which provides the data for
the various word counting API end points (including `wc/list`, `topics/<id>/wc/list`, and
`stories_public/get_word_matrix`). Contents in a language not supported by Media Cloud will still be processed by those
end points, but the results will not be stemmed or get their stop words removed.


## Adding support for a new language

1. Create a subclass of AbstractLanguage.
2. Implement the required methods to do the language-specific actions for the language you're about to add (e.g.
   stemming, stop word map retrieval, etc.)
3. Add the language that you've just added to the "enabled languages" set in LanguageFactory class.

"""

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

    @staticmethod
    @abc.abstractmethod
    def sample_sentence() -> str:
        """Return sample sentence to be used for language identification testing.

        Sample sentences sources:

        * pangrams, e.g. http://clagnut.com/blog/2380/.
        * Wikipedia
        * cld2-cffi's unit test: https://github.com/GregBowyer/cld2-cffi/blob/master/tests/test_cld.py
        """
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

    # FIXME remove once stopword comparison is over
    @abc.abstractmethod
    def stop_words_old_map(self) -> Dict[str, bool]:
        """Return map of old stopwords."""
        raise NotImplementedError("Abstract method.")

    @abc.abstractmethod
    def stem_words(self, words: List[str]) -> List[str]:
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


class PyStemmerMixIn(AbstractLanguage, metaclass=abc.ABCMeta):
    """Language which is supported by "PyStemmer" Python module."""

    def __init__(self):
        """Constructor."""
        super().__init__()

        # PyStemmer instance (lazy initialized)
        self.__pystemmer = None

    def stem_words(self, words: List[str]) -> List[str]:
        """Stem list of words with PyStemmer."""
        language_code = self.language_code()
        words = decode_object_from_bytes_if_needed(words)

        # Normalize apostrophe so that "it’s" and "it's" get treated identically (it's being done in
        # _tokenize_with_spaces() too but let's not assume that all tokens that are to be stemmed go through sentence
        # tokenization first)
        words = [word.replace("’", "'") for word in words]

        if language_code is None:
            raise McLanguageException("Language code is None.")

        if words is None:
            raise McLanguageException("Words to stem is None.")

        # (Re-)initialize stemmer if needed
        if self.__pystemmer is None:

            try:
                self.__pystemmer = PyStemmer(language_code)
            except Exception as ex:
                raise McLanguageException(
                    "Unable to initialize PyStemmer for language '%s': %s" % (language_code, str(ex),)
                )

        stems = self.__pystemmer.stemWords(words)

        if len(words) != len(stems):
            log.warning("Stem count is not the same as word count; words: %s; stems: %s" % (str(words), str(stems),))

        # Perl's Snowball implementation used to return lowercase stems
        stems = [stem.lower() for stem in stems]

        return stems


class StopWordsFromFileMixIn(AbstractLanguage, metaclass=abc.ABCMeta):
    """Language for which the stop words are being stored in "<language_code>/<language_code>_stop_words.txt" file."""

    def __init__(self):
        """Constructor."""

        # Stop words map (lazy initialized)
        self.__stop_words_map = None

        # FIXME remove once stopword comparison is over
        self.__stop_words_old_map = None

    def stop_words_map(self) -> Dict[str, bool]:
        """Return stop word map read from a file."""
        if self.__stop_words_map is None:

            stop_words_path = os.path.join(
                os.path.dirname(os.path.abspath(__file__)),
                self.language_code(),
                '%s_stop_words.txt' % self.language_code(),
            )
            if stop_words_path is None:
                raise McLanguageException("Stop words file path is None.")

            if not os.path.isfile(stop_words_path):
                raise McLanguageException("Stop words file does not exist at path '%s'." % stop_words_path)

            stop_words = dict()
            with open(stop_words_path, 'r', encoding='utf-8') as f:
                for stop_word in f.readlines():
                    # Remove comments
                    stop_word = re.sub(r'\s*?#.*?$', '', stop_word)

                    stop_word = stop_word.strip()

                    if len(stop_word) > 0:
                        stop_words[stop_word] = True

            self.__stop_words_map = stop_words

        return self.__stop_words_map

    # FIXME remove once stopword comparison is over
    def stop_words_old_map(self) -> Dict[str, bool]:
        if self.__stop_words_old_map is None:

            stop_words_path = os.path.join(
                os.path.dirname(os.path.abspath(__file__)),
                self.language_code(),
                '%s_stop_words_old.txt' % self.language_code(),
            )
            if stop_words_path is None:
                raise McLanguageException("Stop words file path is None.")

            if not os.path.isfile(stop_words_path):
                raise McLanguageException("Stop words file does not exist at path '%s'." % stop_words_path)

            stop_words = dict()
            with open(stop_words_path, 'r', encoding='utf-8') as f:
                for stop_word in f.readlines():
                    # Remove comments
                    stop_word = re.sub(r'\s*?#.*?$', '', stop_word)

                    stop_word = stop_word.strip()

                    if len(stop_word) > 0:
                        stop_words[stop_word] = True

            self.__stop_words_old_map = stop_words

        return self.__stop_words_old_map
