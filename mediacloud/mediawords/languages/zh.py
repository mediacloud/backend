# -*- coding: UTF-8 -*-
import jieba, jieba.analyse
import jieba.posseg as pseg
from nltk import RegexpTokenizer, PunktSentenceTokenizer
import os
import re
from typing import Dict

from mediawords.util.log import create_logger
from mediawords.util.paths import mc_root_path
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.text import random_string

#Chinese punctuation list
punc = ["【", "】", "・", ",", ".", "\"", "/", "!", "?", "$", "%", "&", "(", ")",";","'","、", "。", "〈", "〉", "《", "》", "「", "」", "『", "』", "…", "！", "＃", "＄", "％", "＆", "（", "）", "＊", "＋", "，", "：", "；", "＜", "＞", "？", "＠", "［", "］", "｛", "｜", "｝", "～", "￥", "$"]

l = create_logger(__name__)

class McChineseTokenizerException(Exception):
    """McChineseTokenizer class exception."""
    pass


class McChineseTokenizer(object):
    """Chinese language tokenizer that uses jieba."""

    # Path to jieba dictionary(ies)
    # (protected and not private because used by the unit test)
    _dict_path = os.path.join(mc_root_path(), 'lib/MediaWords/Languages/resources/zh/')

    # jieba instance
    __jieba = None

    # Text -> sentence tokenizer for Chinese text
    __chinese_sentence_tokenizer = RegexpTokenizer(
        r'([^！？。]*[！？。])',
        gaps=True,  # don't discard non-Chinese text
        discard_empty=True,
    )

    # Text -> sentence tokenizer for non-Chinese (e.g. English) text
    __non_chinese_sentence_tokenizer = PunktSentenceTokenizer()

    def __init__(self):
        """Initialize jieba tokenizer."""

        if not os.path.isdir(self._dict_path):
            raise McChineseTokenizerException("""
                jieba dictionary directory was not found: %s
                Maybe you forgot to initialize Git submodules?
                """ % self._dict_path)

        if not os.path.isfile(os.path.join(self._dict_path, 'dict.txt.big')):
            raise McChineseTokenizerException("""
                Default dictionary not found in jieba dictionary directory: %s
                Maybe you forgot to run jieba installation script?
                """ % self._dict_path)

        if not os.path.isfile(os.path.join(self._dict_path, 'userdict.txt')):
            raise McChineseTokenizerException("""
                User dictionary not found in jieba dictionary directory: %s
                Maybe you forgot to run jieba installation script?
                """ % self._dict_path)
        try:
            jieba.initialize() #by default, jieba doesn't build the prefix dictionary unless it's necessary
            #loading dictionary is part of the init process
            jieba.set_dictionary(os.path.join(self._dict_path,'dict.txt.big'))
            jieba.load_userdict(os.path.join(self._dict_path,'userdict.txt'))
        except Exception as ex:
            raise McChineseTokenizerException("Unable to initialize jieba: %s" % str(ex))

    def tokenize_text_to_sentences(self, text: str) -> list:
        """Tokenize Chinese text into sentences."""

        text = decode_object_from_bytes_if_needed(text)

        if text is None:
            l.warning("Text to tokenize into sentences is None.")
            return []

        text = text.strip()

        if len(text) == 0:
            return []

        # First split Chinese text
        chinese_sentences = self.__chinese_sentence_tokenizer.tokenize(text)
        sentences = []
        for sentence in chinese_sentences:

            # Split paragraphs separated by two line breaks denoting a list
            paragraphs = re.split("\n\s*?\n", sentence)
            for paragraph in paragraphs:

                # Split lists separated by "* "
                list_items = re.split("\n\s*?(?=\* )", paragraph)
                for list_item in list_items:
                    # Split non-Chinese text
                    non_chinese_sentences = self.__non_chinese_sentence_tokenizer.tokenize(list_item)

                    sentences += non_chinese_sentences

        # Trim whitespace
        sentences = [sentence.strip() for sentence in sentences]

        return sentences

    def tokenize_sentence_to_words(self, sentence: str) -> list:
        """Tokenize Chinese sentence into words.
        
        Removes punctuation."""

        sentence = decode_object_from_bytes_if_needed(sentence)

        if sentence is None:
            l.warning("Sentence to tokenize into words is None.")
            return []

        sentence = sentence.strip()

        if len(sentence) == 0:
            return []

        parsed_text = jieba.lcut(sentence, cut_all=False)
        parsed_tokens = [x for x in parsed_text if x.strip()]
        words = []
        for parsed_token in parsed_tokens:
            if parsed_token not in punc:
                words.append(parsed_token)
            else:
                pass

        return words
