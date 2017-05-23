import MeCab
from nltk import RegexpTokenizer, PunktSentenceTokenizer
import os
import re
from typing import Dict

from mediawords.util.log import create_logger
from mediawords.util.paths import mc_root_path
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.text import random_string

l = create_logger(__name__)


class McJapaneseTokenizerException(Exception):
    """McJapaneseTokenizer class exception."""
    pass


class McJapaneseTokenizer(object):
    """Japanese language tokenizer that uses MeCab."""

    # Path to MeCab dictionary
    # (protected and not private because used by the unit test)
    _MECAB_DICTIONARY_PATH = os.path.join(mc_root_path(), 'lib/MediaWords/Languages/resources/ja/mecab-ipadic-neologd/')

    # MeCab instance
    __mecab = None

    # Text -> sentence tokenizer for Japanese text
    __japanese_sentence_tokenizer = RegexpTokenizer(
        r'([^！？。]*[！？。])',
        gaps=True,  # don't discard non-Japanese text
        discard_empty=True,
    )

    # Text -> sentence tokenizer for non-Japanese (e.g. English) text
    __non_japanese_sentence_tokenizer = PunktSentenceTokenizer()

    __MECAB_TOKEN_POS_SEPARATOR = random_string(length=16)  # for whatever reason tab doesn't work
    __MECAB_EOS_MARK = 'EOS'

    def __init__(self):
        """Initialize MeCab tokenizer."""

        if not os.path.isdir(self._MECAB_DICTIONARY_PATH):
            raise McJapaneseTokenizerException("""
                MeCab dictionary directory was not found: %s
                Maybe you forgot to initialize Git submodules?
                """ % self._MECAB_DICTIONARY_PATH)

        if not os.path.isfile(os.path.join(self._MECAB_DICTIONARY_PATH, 'sys.dic')):
            raise McJapaneseTokenizerException("""
                MeCab dictionary directory does not contain a dictionary: %s
                Maybe you forgot to run ./install/install_mecab-ipadic-neologd.sh?
                """ % self._MECAB_DICTIONARY_PATH)

        try:
            self.__mecab = MeCab.Tagger(
                '--dicdir=%(dictionary_path)s '
                '--node-format=%%m%(token_pos_separator)s%%h\\n '
                '--eos-format=%(eos_mark)s\\n' % {
                    'token_pos_separator': self.__MECAB_TOKEN_POS_SEPARATOR,
                    'eos_mark': self.__MECAB_EOS_MARK,
                    'dictionary_path': self._MECAB_DICTIONARY_PATH,
                }
            )
        except Exception as ex:
            raise McJapaneseTokenizerException("Unable to initialize MeCab: %s" % str(ex))

    def tokenize_text_to_sentences(self, text: str) -> list:
        """Tokenize Japanese text into sentences."""

        text = decode_object_from_bytes_if_needed(text)

        if text is None:
            l.warning("Text to tokenize into sentences is None.")
            return []

        text = text.strip()

        if len(text) == 0:
            return []

        # First split Japanese text
        japanese_sentences = self.__japanese_sentence_tokenizer.tokenize(text)
        sentences = []
        for sentence in japanese_sentences:

            # Split paragraphs separated by two line breaks denoting a list
            paragraphs = re.split("\n\s*?\n", sentence)
            for paragraph in paragraphs:

                # Split lists separated by "* "
                list_items = re.split("\n\s*?(?=\* )", paragraph)
                for list_item in list_items:
                    # Split non-Japanese text
                    non_japanese_sentences = self.__non_japanese_sentence_tokenizer.tokenize(list_item)

                    sentences += non_japanese_sentences

        # Trim whitespace
        sentences = [sentence.strip() for sentence in sentences]

        return sentences

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

    def tokenize_sentence_to_words(self, sentence: str) -> list:
        """Tokenize Japanese sentence into words.
        
        Removes punctuation and words that don't belong to part-of-speech whitelist."""

        sentence = decode_object_from_bytes_if_needed(sentence)

        if sentence is None:
            l.warning("Sentence to tokenize into words is None.")
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
