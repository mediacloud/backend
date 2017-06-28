# -*- coding: UTF-8 -*-
from unittest import TestCase

from mediawords.languages.zh import *


# noinspection SpellCheckingInspection
class TestChineseTokenizer(TestCase):
    __jieba = None

    def setUp(self):
        self.__tokenizer = McChineseTokenizer()

    def test_tokenize_text_to_sentences(self):
        # noinspection PyTypeChecker
        assert self.__tokenizer.tokenize_text_to_sentences(None) == []
        assert self.__tokenizer.tokenize_text_to_sentences("") == []
        assert self.__tokenizer.tokenize_text_to_sentences(" ") == []
        assert self.__tokenizer.tokenize_text_to_sentences(".") == ["."]

        # English-only punctuation
        sentences = self.__tokenizer.tokenize_text_to_sentences(
            "Hello. How do you do? I'm doing okay."
        )
        assert sentences == [
            "Hello.",
            "How do you do?",
            "I'm doing okay.",
        ]

        # English-only punctuation, no period at the end of sentence
        sentences = self.__tokenizer.tokenize_text_to_sentences(
            "Hello. How do you do? I'm doing okay"
        )
        assert sentences == [
            "Hello.",
            "How do you do?",
            "I'm doing okay",
        ]

        # Chinese-only punctuation
        sentences = self.__tokenizer.tokenize_text_to_sentences(
            "問責制既不能吸引政治人才加入政府。"
            "時任政務司長林鄭月娥被指在未有公開諮詢下，突然宣布西九文化區興建故宮博物館，並委聘建築師嚴迅奇擔任設計顧問，被立法會議員向廉政公署舉報。"
            "她一出生就被父母遺棄，住在八里愛心教養院。"
            "堆填區個綠色真係靚，心曠神怡。"
        )
        assert sentences == [
            "問責制既不能吸引政治人才加入政府。",
            "時任政務司長林鄭月娥被指在未有公開諮詢下，突然宣布西九文化區興建故宮博物館，並委聘建築師嚴迅奇擔任設計顧問，被立法會議員向廉政公署舉報。",
            "她一出生就被父母遺棄，住在八里愛心教養院。",
            "堆填區個綠色真係靚，心曠神怡。",
        ]

        # Chinese-only punctuation, no EOS at the end of the sentence
        sentences = self.__tokenizer.tokenize_text_to_sentences(
            "問責制既不能吸引政治人才加入政府。"
            "時任政務司長林鄭月娥被指在未有公開諮詢下，突然宣布西九文化區興建故宮博物館，並委聘建築師嚴迅奇擔任設計顧問，被立法會議員向廉政公署舉報。"
            "她一出生就被父母遺棄，住在八里愛心教養院。"
            "堆填區個綠色真係靚，心曠神怡"
        )
        assert sentences == [
            "問責制既不能吸引政治人才加入政府。",
            "時任政務司長林鄭月娥被指在未有公開諮詢下，突然宣布西九文化區興建故宮博物館，並委聘建築師嚴迅奇擔任設計顧問，被立法會議員向廉政公署舉報。",
            "她一出生就被父母遺棄，住在八里愛心教養院。",
            "堆填區個綠色真係靚，心曠神怡",
        ]

        # Chinese and English punctuation
        sentences = self.__tokenizer.tokenize_text_to_sentences(
            "問責制既不能吸引政治人才加入政府。"
            "This is some English text out of the blue. "
            "時任政務司長林鄭月娥被指在未有公開諮詢下，突然宣布西九文化區興建故宮博物館，並委聘建築師嚴迅奇擔任設計顧問，被立法會議員向廉政公署舉報。"
            "This is some more English text."
        )
        assert sentences == [
            "問責制既不能吸引政治人才加入政府。",
            "This is some English text out of the blue.",
            "時任政務司長林鄭月娥被指在未有公開諮詢下，突然宣布西九文化區興建故宮博物館，並委聘建築師嚴迅奇擔任設計顧問，被立法會議員向廉政公署舉報。",
            "This is some more English text.",
        ]

        # Chinese and English punctuation (with newlines)
        sentences = self.__tokenizer.tokenize_text_to_sentences("""問責制既不能吸引政治人才加入政府。
This is some English text out of the blue. 
時任政務司長林鄭月娥被指在未有公開諮詢下，突然宣布西九文化區興建故宮博物館，並委聘建築師嚴迅奇擔任設計顧問，被立法會議員向廉政公署舉報。
This is some more English text.
This is some more English text.
dsds.
""")
        assert sentences == [
            "問責制既不能吸引政治人才加入政府。",
            "This is some English text out of the blue.",
            "時任政務司長林鄭月娥被指在未有公開諮詢下，突然宣布西九文化區興建故宮博物館，並委聘建築師嚴迅奇擔任設計顧問，被立法會議員向廉政公署舉報。",
            "This is some more English text.",
            "This is some more English text.",
            "dsds.",
        ]

        # Chinese and English sentences separates by double-newlines
        # (test has extra whitespace between line breaks)
        sentences = self.__tokenizer.tokenize_text_to_sentences("""
問責制既不能吸引政治人才加入政府
  
This is some English text out of the blue
  
香港的主要官員問責制（下稱「問責制」）於2002年由當時的特首董建華提出
  
This is some more English text
""")
        assert sentences == [
            "問責制既不能吸引政治人才加入政府",
            "This is some English text out of the blue",
            "香港的主要官員問責制（下稱「問責制」）於2002年由當時的特首董建華提出",
            "This is some more English text",
        ]

        # Chinese and English sentences in a list
        # (test has extra whitespace between line breaks)
        sentences = self.__tokenizer.tokenize_text_to_sentences("""
問責制既不能吸引政治人才加入政府

* This is some English text out of the blue. Some more English text.
* 本文會從幾方面討論問責制的成效和影響。首先是行政領導和問責制的制度設計問題。 

This is some more English text
    """)
        assert sentences == [
            "問責制既不能吸引政治人才加入政府",
            "* This is some English text out of the blue.",
            "Some more English text.",
            "* 本文會從幾方面討論問責制的成效和影響。",
            "首先是行政領導和問責制的制度設計問題。",
            "This is some more English text",
        ]

    def test_tokenize_sentence_to_words(self):
        # noinspection PyTypeChecker
        assert self.__tokenizer.tokenize_sentence_to_words(None) == []
        assert self.__tokenizer.tokenize_sentence_to_words("") == []
        assert self.__tokenizer.tokenize_sentence_to_words(" ") == []
        assert self.__tokenizer.tokenize_sentence_to_words(".") == []

        # English sentence
        words = self.__tokenizer.tokenize_sentence_to_words("How do you do?")
        assert words == [
            "How",
            "do",
            "you",
            "do",
        ]

        # English sentence, no period at the end of the sentence
        words = self.__tokenizer.tokenize_sentence_to_words("How do you do")
        assert words == [
            "How",
            "do",
            "you",
            "do",
        ]

        # English sentence, literal string "EOS"
        words = self.__tokenizer.tokenize_sentence_to_words("EOS this, EOS that.")
        assert words == [
            "EOS",
            "this",
            "EOS",
            "that",
        ]

        # English sentence; tab, newline and comma characters
        words = self.__tokenizer.tokenize_sentence_to_words(
            "Something\tSomething else\nSomething, completely, different."
        )
        assert words == [
            "Something",
            "Something",
            "else",
            "Something",
            "completely",
            "different",
        ]
        """
        # Chinese sentence
        words = self.__tokenizer.tokenize_sentence_to_words(
            "時任政務司長林鄭月娥被指在未有公開諮詢下，突然宣布西九文化區興建故宮博物館，並委聘建築師嚴迅奇擔任設計顧問，被立法會議員向廉政公署舉報。"
        )
        print(words)
        assert words == [
            '時任',
            '政務',
            '司長'
            '林鄭月娥',
            '被',
            '指',
            '在',
            '未有',
            '公開',
            '諮詢',
            '下',
            '突然',
            '宣布',
            '西九文化區',
            '興建',
            '故宮博物館',
            '並',
            '委聘',
            '建築師',
            '嚴迅奇',
            '擔任',
            '設計顧問',
            '被',
            '立法會',
            '議員',
            '向',
            '廉政公署',
            '舉報',
        ]
        """

        # Chinese + English sentence
        words = self.__tokenizer.tokenize_sentence_to_words("他建議想學好英文，必須人格分裂、要代入外國人的思想（mindset）。")
        assert words == [
            "他",
            "建議",
            "想",
            "學好",
            "英文",
            "必須",
            "人格分裂",
            "要",
            "代入",
            "外國人",
            "的",
            "思想",
            "mindset",
        ]

        # Chinese punctuation
        words = self.__tokenizer.tokenize_sentence_to_words(
            "Badger、badger。Badger・Badger『badger』「Badger」badger？Badger！Badger！？"
            "Badger【badger】Badger～badger（badger）《Badger》，badger；badger……badger：badger"
        )
        print(words)
        assert words == [
            'Badger', 'badger', 'Badger', 'Badger', 'badger', 'Badger', 'badger', 'Badger', 'Badger',
            'Badger', 'badger', 'Badger', 'badger', 'badger', 'Badger', 'badger', 'badger', 'badger', 'badger',
        ]
