import os
import re
from typing import List

# noinspection PyProtectedMember
from hunspell import Hunspell
from nltk import TreebankWordTokenizer

from mediawords.languages import McLanguageException, StopWordsFromFileMixIn
from mediawords.languages.en import EnglishLanguage
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class HindiLanguage(StopWordsFromFileMixIn):
    """Hindi language support module."""

    __slots__ = [
        # Stop words map
        '__stop_words_map',

        # Hunspell instance
        '__hindi_hunspell',

        # Word tokenizer
        '__treebank_tokenizer',
    ]

    def __init__(self):
        """Constructor."""
        super().__init__()

        self.__treebank_tokenizer = TreebankWordTokenizer()

        hunspell_dict_dir = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            'hindi-hunspell',
            'dict-hi_IN',
        )
        if not os.path.isdir(hunspell_dict_dir):
            raise McLanguageException(
                "Hunspell dictionary directory does not exist at path: %s." % hunspell_dict_dir
            )

        if not os.path.isfile(os.path.join(hunspell_dict_dir, 'hi_IN.dic')):
            raise McLanguageException("Hunspell dictionary file does not exist at path: %s" % hunspell_dict_dir)
        if not os.path.isfile(os.path.join(hunspell_dict_dir, 'hi_IN.aff')):
            raise McLanguageException("Hunspell affix file does not exist at path: %s" % hunspell_dict_dir)

        try:
            self.__hindi_hunspell = Hunspell(lang='hi_IN', hunspell_data_dir=hunspell_dict_dir)
        except Exception as ex:
            raise McLanguageException(
                "Unable to initialize Hunspell with data directory '%s': %s" % (hunspell_dict_dir, str(ex),)
            )

        # Quick self-test to make sure that Hunspell is installed and dictionary is available
        hunspell_exc_message = """
            Hunspell self-test failed; make sure that Hunspell is installed and dictionaries are accessible, e.g.
            you might need to fetch Git submodules by running:

                git submodule update --init --recursive
        """
        try:
            test_stems = self.stem_words(['गुरुओं'])
        except Exception as _:
            raise McLanguageException(hunspell_exc_message)
        else:
            if len(test_stems) == 0 or test_stems[0] != 'गुरु':
                raise McLanguageException(hunspell_exc_message)

    @staticmethod
    def language_code() -> str:
        return "hi"

    @staticmethod
    def sample_sentence() -> str:
        return (
            "ऋषियों को सताने वाले दुष्ट राक्षसों के राजा रावण का सर्वनाश करने वाले "
            "विष्णुवतार भगवान श्रीराम, अयोध्या के महाराज दशरथ के बड़े सपुत्र थे।"
        )

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
                term_stems = self.__hindi_hunspell.stem(word)
                if len(term_stems) > 0:
                    stem = term_stems[0]

                    if stem is None or len(stem) == 0:
                        log.debug("Stem for word '%s' is empty or None." % word)
                        stem = word

                else:
                    log.debug("Stem for word '%s' was not found." % word)
                    stem = word

            stems.append(stem)

        if len(words) != len(stems):
            log.warning("Stem count is not the same as word count; words: %s; stems: %s" % (str(words), str(stems),))

        return stems

    def split_text_to_sentences(self, text: str) -> List[str]:
        text = decode_object_from_bytes_if_needed(text)
        if text is None:
            log.warning("Text is None.")
            return []

        # Replace Hindi's "।" with line break to make tokenizer split on both "।" and period
        text = text.replace("।", "।\n\n")

        # No non-breaking prefixes in Hausa, so using English file
        en = EnglishLanguage()
        return en.split_text_to_sentences(text)

    def split_sentence_to_words(self, sentence: str) -> List[str]:
        sentence = decode_object_from_bytes_if_needed(sentence)
        if sentence is None:
            log.warning("Sentence is None.")
            return []

        # Normalize apostrophe so that "it’s" and "it's" get treated identically
        sentence = sentence.replace("’", "'")

        # Replace Hindi's "।" with line break to make tokenizer split on both "।" and period
        sentence = sentence.replace("।", ".")

        # TweetTokenizer / sentence_splitter don't work with Hindi for whatever reason, and word_tokenize() would
        # require NLTK data to be installed which is time consuming on Travis
        tokens = self.__treebank_tokenizer.tokenize(sentence)

        def is_word(token_: str) -> bool:
            """Returns True if token looks like a word."""
            if re.match(pattern=r'\w', string=token_, flags=re.UNICODE):
                return True
            else:
                return False

        # TweetTokenizer leaves punctuation in-place
        tokens = [token for token in tokens if is_word(token)]

        return tokens
