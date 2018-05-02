import hausastemmer
from typing import List

from mediawords.languages import McLanguageException, SpaceSeparatedWordsMixIn, StopWordsFromFileMixIn
from mediawords.languages.en import EnglishLanguage
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.log import create_logger

log = create_logger(__name__)


# No non-breaking prefixes in Hausa, so using English class for text / sentence tokenization
class HausaLanguage(SpaceSeparatedWordsMixIn, StopWordsFromFileMixIn):
    """Hausa language support module."""

    @staticmethod
    def language_code() -> str:
        return "ha"

    @staticmethod
    def sample_sentence() -> str:
        return "a cikin a kan sakamako daga sakwannin a kan sakamako daga sakwannin daga ranar zuwa a kan sakamako"

    def stem_words(self, words: List[str]) -> List[str]:
        words = decode_object_from_bytes_if_needed(words)
        if words is None:
            raise McLanguageException("Words to stem is None.")

        stems = []

        for word in words:
            if word is None or len(word) == 0:
                log.debug("Word is empty or None.")
                stem = word
            else:
                stem = hausastemmer.stem(word)

                if stem is None or len(stem) == 0:
                    log.debug("Unable to stem word '%s'" % word)
                    stem = word

            stems.append(stem)

        if len(words) != len(stems):
            log.warning("Stem count is not the same as word count; words: %s; stems: %s" % (str(words), str(stems),))

        return stems

    def split_text_to_sentences(self, text: str) -> List[str]:
        text = decode_object_from_bytes_if_needed(text)

        # No non-breaking prefixes in Hausa, so using English file
        en = EnglishLanguage()
        return en.split_text_to_sentences(text)
