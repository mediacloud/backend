from typing import List

from mediawords.languages import (
    McLanguageException,
    SpaceSeparatedWordsMixIn,
    SentenceSplitterMixIn,
    StopWordsFromFileMixIn,
)
from mediawords.languages.lt.lithuanian_stemmer import LithuanianStemmer
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class LithuanianLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, StopWordsFromFileMixIn):
    """Lithuanian language support module."""

    __slots__ = [
        # Lithuanian stemmer instance
        '__lt_stemmer',
    ]

    def __init__(self):
        """Constructor."""
        super().__init__()

        self.__lt_stemmer = LithuanianStemmer()

    @staticmethod
    def language_code() -> str:
        return "lt"

    @staticmethod
    def sample_sentence() -> str:
        return "Įlinkdama fechtuotojo špaga sublykčiojusi pragręžė apvalų arbūzą."

    def stem_words(self, words: List[str]) -> List[str]:
        words = decode_object_from_bytes_if_needed(words)
        if words is None:
            raise McLanguageException("Words to stem is None.")

        stems = self.__lt_stemmer.stemWords(words)

        if len(words) != len(stems):
            log.warning("Stem count is not the same as word count; words: %s; stems: %s" % (str(words), str(stems),))

        # Perl's Snowball implementation used to return lowercase stems
        stems = [stem.lower() for stem in stems]

        return stems
