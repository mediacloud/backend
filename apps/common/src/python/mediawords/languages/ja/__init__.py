import MeCab
from nltk import RegexpTokenizer
import os
import re
from typing import List, Dict

from mediawords.languages import McLanguageException, StopWordsFromFileMixIn
from mediawords.languages.en import EnglishLanguage
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.text import random_string

log = create_logger(__name__)


class JapaneseLanguage(StopWordsFromFileMixIn):
    """Japanese language support module."""

    # Paths where mecab-ipadic-neologd might be located
    __MECAB_DICTIONARY_PATHS = [

        # Ubuntu / Debian
        '/var/lib/mecab/dic/ipadic-neologd',

        # CentOS / Fedora
        '/usr/lib64/mecab/dic/ipadic-neologd/',

        # OS X
        '/usr/local/opt/mecab-ipadic-neologd/lib/mecab/dic/ipadic-neologd/',
    ]

    __MECAB_TOKEN_POS_SEPARATOR = random_string(length=16)  # for whatever reason tab doesn't work
    __MECAB_EOS_MARK = 'EOS'

    __slots__ = [
        # MeCab instance
        '__mecab',

        # Text -> sentence tokenizer for Japanese text
        '__japanese_sentence_tokenizer',

        # English language instance for tokenizing non-Chinese (e.g. English) text
        '__english_language',
    ]

    @staticmethod
    def _mecab_ipadic_neologd_path() -> str:  # (protected and not private because used by the unit test)
        """Return path to mecab-ipadic-neologd dictionary installed on system."""
        mecab_dictionary_path = None
        candidate_paths = JapaneseLanguage.__MECAB_DICTIONARY_PATHS

        for candidate_path in candidate_paths:
            if os.path.isdir(candidate_path):
                if os.path.isfile(os.path.join(candidate_path, 'sys.dic')):
                    mecab_dictionary_path = candidate_path
                    break

        if mecab_dictionary_path is None:
            raise McLanguageException(
                "mecab-ipadic-neologd was not found in paths: %s" % str(candidate_paths)
            )

        return mecab_dictionary_path

    @staticmethod
    def _mecab_allowed_pos_ids() -> Dict[int, str]:
        """Return allowed MeCab part-of-speech IDs and their definitions from pos-id.def.

        Definitions don't do much in the language module itself, they're used by unit tests to verify that pos-id.def
        didn't change in some unexpected way and we're not missing out on newly defined POSes.
        """
        return {
            36: '名詞,サ変接続,*,*',  # noun-verbal
            38: '名詞,一般,*,*',  # noun
            40: '名詞,形容動詞語幹,*,*',  # adjectival nouns or quasi-adjectives
            41: '名詞,固有名詞,一般,*',  # proper nouns
            42: '名詞,固有名詞,人名,一般',  # proper noun, names of people
            43: '名詞,固有名詞,人名,姓',  # proper noun, first name
            44: '名詞,固有名詞,人名,名',  # proper noun, last name
            45: '名詞,固有名詞,組織,*',  # proper noun, organization
            46: '名詞,固有名詞,地域,一般',  # proper noun in general
            47: '名詞,固有名詞,地域,国',  # proper noun, country name
        }

    def __init__(self):
        """Constructor."""
        super().__init__()

        self.__japanese_sentence_tokenizer = RegexpTokenizer(
            r'([^！？。]*[！？。])',
            gaps=True,  # don't discard non-Japanese text
            discard_empty=True,
        )

        self.__english_language = EnglishLanguage()

        mecab_dictionary_path = JapaneseLanguage._mecab_ipadic_neologd_path()

        try:
            self.__mecab = MeCab.Tagger(
                '--dicdir=%(dictionary_path)s '
                '--node-format=%%m%(token_pos_separator)s%%h\\n '
                '--eos-format=%(eos_mark)s\\n' % {
                    'token_pos_separator': self.__MECAB_TOKEN_POS_SEPARATOR,
                    'eos_mark': self.__MECAB_EOS_MARK,
                    'dictionary_path': mecab_dictionary_path,
                }
            )
        except Exception as ex:
            raise McLanguageException("Unable to initialize MeCab: %s" % str(ex))

        # Quick self-test to make sure that MeCab, its dictionaries and Python class are installed and working
        mecab_exc_message = "MeCab self-test failed; make sure that MeCab is built and dictionaries are accessible."
        try:
            test_words = self.split_sentence_to_words('pythonが大好きです')
        except Exception as _:
            raise McLanguageException(mecab_exc_message)
        else:
            if len(test_words) < 2 or test_words[1] != '大好き':
                raise McLanguageException(mecab_exc_message)

    @staticmethod
    def language_code() -> str:
        return "ja"

    @staticmethod
    def sample_sentence() -> str:
        return "いろはにほへと ちりぬるを わかよたれそ つねならむ うゐのおくやま けふこえて あさきゆめみし ゑひもせす（ん）。"

    # noinspection PyMethodMayBeStatic
    def stem_words(self, words: List[str]) -> List[str]:
        words = decode_object_from_bytes_if_needed(words)

        # MeCab's sentence -> word tokenizer already returns "base forms" of every word
        return words

    def split_text_to_sentences(self, text: str) -> List[str]:
        """Tokenize Japanese text into sentences."""
        text = decode_object_from_bytes_if_needed(text)
        if text is None:
            log.warning("Text is None.")
            return []

        text = text.strip()

        if len(text) == 0:
            return []

        # First split Japanese text
        japanese_sentences = self.__japanese_sentence_tokenizer.tokenize(text)
        sentences = []
        for sentence in japanese_sentences:

            # Split paragraphs separated by two line breaks denoting a list
            paragraphs = re.split(r"\n\s*?\n", sentence)
            for paragraph in paragraphs:

                # Split lists separated by "* "
                list_items = re.split(r"\n\s*?(?=\* )", paragraph)
                for list_item in list_items:
                    # Split non-Japanese text
                    non_japanese_sentences = self.__english_language.split_text_to_sentences(list_item)

                    sentences += non_japanese_sentences

        # Trim whitespace
        sentences = [sentence.strip() for sentence in sentences]

        return sentences

    def split_sentence_to_words(self, sentence: str) -> List[str]:
        """Tokenize Japanese sentence into words.

        Removes punctuation and words that don't belong to part-of-speech whitelist."""

        sentence = decode_object_from_bytes_if_needed(sentence)
        if sentence is None:
            log.warning("Sentence is None.")
            return []

        sentence = sentence.strip()

        if len(sentence) == 0:
            return []

        parsed_text = self.__mecab.parse(sentence).strip()
        parsed_tokens = parsed_text.split("\n")

        allowed_pos_ids = self._mecab_allowed_pos_ids()

        words = []
        for parsed_token_line in parsed_tokens:
            if self.__MECAB_TOKEN_POS_SEPARATOR in parsed_token_line:

                primary_form_and_pos_number = parsed_token_line.split(self.__MECAB_TOKEN_POS_SEPARATOR)

                primary_form = primary_form_and_pos_number[0]
                pos_number = primary_form_and_pos_number[1]

                if pos_number.isdigit():
                    pos_number = int(pos_number)

                    if pos_number in allowed_pos_ids:
                        words.append(primary_form)

            else:
                # Ignore all the "EOS" stuff
                pass

        return words
