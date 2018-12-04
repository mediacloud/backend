from jieba import Tokenizer as JiebaTokenizer
from nltk import RegexpTokenizer
import os
import re
from typing import List

from mediawords.languages import McLanguageException, StopWordsFromFileMixIn
from mediawords.languages.en import EnglishLanguage
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class ChineseLanguage(StopWordsFromFileMixIn):
    """Chinese language support module."""

    # Path to jieba dictionary(ies)
    __DICT_PATH = os.path.dirname(os.path.abspath(__file__))
    __JIEBA_DICT_PATH = os.path.join(__DICT_PATH, 'dict.txt.big')
    __JIEBA_USERDICT_PATH = os.path.join(__DICT_PATH, 'userdict.txt')

    __slots__ = [
        # Stop words map
        '__stop_words_map',

        # Jieba instance
        '__jieba',

        # Text -> sentence tokenizer for Chinese text
        '__chinese_sentence_tokenizer',

        # English language instance for tokenizing non-Chinese (e.g. English) text
        '__english_language',
    ]

    def __init__(self):
        """Constructor."""
        super().__init__()

        # Text -> sentence tokenizer for Chinese text
        self.__chinese_sentence_tokenizer = RegexpTokenizer(
            r'([^！？。]*[！？。])',
            gaps=True,  # don't discard non-Chinese text
            discard_empty=True,
        )

        self.__english_language = EnglishLanguage()

        self.__jieba = JiebaTokenizer()

        if not os.path.isdir(self.__DICT_PATH):
            raise McLanguageException("Jieba dictionary directory was not found: %s" % self.__DICT_PATH)

        if not os.path.isfile(self.__JIEBA_DICT_PATH):
            raise McLanguageException(
                "Default dictionary not found in Jieba dictionary directory: %s" % self.__DICT_PATH
            )
        if not os.path.isfile(self.__JIEBA_USERDICT_PATH):
            raise McLanguageException(
                "User dictionary not found in jieba dictionary directory: %s" % self.__DICT_PATH
            )
        try:
            self.__jieba.set_dictionary(os.path.join(self.__JIEBA_DICT_PATH))
            self.__jieba.load_userdict(os.path.join(self.__JIEBA_USERDICT_PATH))
        except Exception as ex:
            raise McLanguageException("Unable to initialize jieba: %s" % str(ex))

        # Quick self-test to make sure that Jieba, its dictionaries and Python class are installed and working
        jieba_exc_message = "Jieba self-test failed; make sure that MeCab is built and dictionaries are accessible."
        try:
            test_words = self.split_sentence_to_words('python課程')
        except Exception as _:
            raise McLanguageException(jieba_exc_message)
        else:
            if len(test_words) < 2 or test_words[1] != '課程':
                raise McLanguageException(jieba_exc_message)

    @staticmethod
    def language_code() -> str:
        return "zh"

    @staticmethod
    def sample_sentence() -> str:
        return (
            "2010年宾夕法尼亚州联邦参议员选举民主党初选于2010年5月18日举行，联邦众议员乔·谢斯塔克战胜在任联邦参议员阿伦·斯佩克特，"
            "为后者的连续5个参议员任期划上句点。"
        )

    def stem_words(self, words: List[str]) -> List[str]:
        words = decode_object_from_bytes_if_needed(words)

        # Jieba's sentence -> word tokenizer already returns "base forms" of every word
        return words

    def split_text_to_sentences(self, text: str) -> List[str]:
        """Tokenize Chinese text into sentences."""

        text = decode_object_from_bytes_if_needed(text)
        if text is None:
            log.warning("Text is None.")
            return []

        text = text.strip()

        if len(text) == 0:
            return []

        # First split Chinese text
        chinese_sentences = self.__chinese_sentence_tokenizer.tokenize(text)
        sentences = []
        for sentence in chinese_sentences:

            # Split paragraphs separated by two line breaks denoting a list
            paragraphs = re.split(r"\n\s*?\n", sentence)
            for paragraph in paragraphs:

                # Split lists separated by "* "
                list_items = re.split(r"\n\s*?(?=\* )", paragraph)
                for list_item in list_items:
                    # Split non-Chinese text
                    non_chinese_sentences = self.__english_language.split_text_to_sentences(list_item)

                    sentences += non_chinese_sentences

        # Trim whitespace
        sentences = [sentence.strip() for sentence in sentences]

        return sentences

    def split_sentence_to_words(self, sentence: str) -> List[str]:
        """Tokenize Chinese sentence into words.

        Removes punctuation."""

        sentence = decode_object_from_bytes_if_needed(sentence)

        if sentence is None:
            log.warning("Sentence to tokenize into words is None.")
            return []

        sentence = sentence.strip()

        if len(sentence) == 0:
            return []

        parsed_text = self.__jieba.lcut(sentence, cut_all=False)
        parsed_tokens = [x for x in parsed_text if x.strip()]
        words = []
        for parsed_token in parsed_tokens:
            if re.search(r'\w+', parsed_token, flags=re.UNICODE) is not None:
                words.append(parsed_token)
            else:
                pass

        return words
