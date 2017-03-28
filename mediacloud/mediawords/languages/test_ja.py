from unittest import TestCase

from mediawords.languages.ja import *


# FIXME text -> sentence tokenization with newlines
# FIXME text -> sentence tokenization with lists

# noinspection SpellCheckingInspection
class TestJapaneseTokenizer(TestCase):
    __mecab = None

    def setUp(self):
        self.__tokenizer = McJapaneseTokenizer()

    def test_tokenize_text_to_sentences(self):
        # noinspection PyTypeChecker
        assert self.__tokenizer.tokenize_text_to_sentences(None) == []
        assert self.__tokenizer.tokenize_text_to_sentences("") == []
        assert self.__tokenizer.tokenize_text_to_sentences(" ") == []
        assert self.__tokenizer.tokenize_text_to_sentences(".") == ["."]

        # English-only punctuation
        assert self.__tokenizer.tokenize_text_to_sentences(
            "Hello. How do you do? I'm doing okay."
        ) == [
                   "Hello.",
                   "How do you do?",
                   "I'm doing okay.",
               ]

        # English-only punctuation, no period at the end of sentence
        assert self.__tokenizer.tokenize_text_to_sentences(
            "Hello. How do you do? I'm doing okay"
        ) == [
                   "Hello.",
                   "How do you do?",
                   "I'm doing okay",
               ]

        # Japanese-only punctuation
        assert self.__tokenizer.tokenize_text_to_sentences(
            "ジアゼパムはてんかんや興奮の治療に用いられる。"
            "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。"
            "鎮静作用を生かし手術などの前投薬にも用いられる。"
            "アルコールやドラッグによる離脱症状の治療にも用いられる。"
        ) == [
                   "ジアゼパムはてんかんや興奮の治療に用いられる。",
                   "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。",
                   "鎮静作用を生かし手術などの前投薬にも用いられる。",
                   "アルコールやドラッグによる離脱症状の治療にも用いられる。",
               ]

        # Japanese-only punctuation, no EOS at the end of the sentence
        assert self.__tokenizer.tokenize_text_to_sentences(
            "ジアゼパムはてんかんや興奮の治療に用いられる。"
            "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。"
            "鎮静作用を生かし手術などの前投薬にも用いられる。"
            "アルコールやドラッグによる離脱症状の治療にも用いられる"
        ) == [
                   "ジアゼパムはてんかんや興奮の治療に用いられる。",
                   "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。",
                   "鎮静作用を生かし手術などの前投薬にも用いられる。",
                   "アルコールやドラッグによる離脱症状の治療にも用いられる",
               ]

        # Japanese and English punctuation
        assert self.__tokenizer.tokenize_text_to_sentences(
            "ジアゼパムはてんかんや興奮の治療に用いられる。"
            "This is some English text out of the blue. "
            "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。"
            "This is some more English text."
        ) == [
                   "ジアゼパムはてんかんや興奮の治療に用いられる。",
                   "This is some English text out of the blue.",
                   "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。",
                   "This is some more English text.",
               ]

    def test_tokenize_sentence_to_words(self):
        # noinspection PyTypeChecker
        assert self.__tokenizer.tokenize_sentence_to_words(None) == []
        assert self.__tokenizer.tokenize_sentence_to_words("") == []
        assert self.__tokenizer.tokenize_sentence_to_words(" ") == []
        assert self.__tokenizer.tokenize_sentence_to_words(".") == []

        # English sentence
        assert self.__tokenizer.tokenize_sentence_to_words("How do you do?") == [
            "How",
            "do",
            "you",
            "do",
        ]

        # English sentence, no period at the end of the sentence
        assert self.__tokenizer.tokenize_sentence_to_words("How do you do") == [
            "How",
            "do",
            "you",
            "do",
        ]

        # English sentence, literal string "EOS"
        assert self.__tokenizer.tokenize_sentence_to_words("EOS this, EOS that.") == [
            "EOS",
            "this",
            "EOS",
            "that",
        ]

        # English sentence; tab, newline and comma characters
        assert self.__tokenizer.tokenize_sentence_to_words(
            "Something\tSomething else\nSomething, completely, different."
        ) == [
                   "Something",
                   "Something else",  # curiously, mecab-ipadic-neologd treats "something else" as a single token
                   "Something",
                   "completely",
                   "different",
               ]

        # Japanese sentence
        assert self.__tokenizer.tokenize_sentence_to_words(
            "10日放送の「中居正広のミになる図書館」（テレビ朝日系）で、SMAPの中居正広が、篠原信一の過去の勘違いを明かす一幕があった。"
        ) == [
                   "10日",
                   "放送",
                   "の",
                   "中居正広のミになる図書館",
                   "テレビ朝日",
                   "系",
                   "で",
                   "SMAP",
                   "の",
                   "中居正広",
                   "が",
                   "篠原信一",
                   "の",
                   "過去",
                   "の",
                   "勘違い",
                   "を",
                   "明かす",
                   "一幕",
                   "が",
                   "あっ",
                   "た",
               ]

        # Japanese + English sentence
        assert self.__tokenizer.tokenize_sentence_to_words("pythonが大好きです") == [
            "python",
            "が",
            "大好き",
            "です",
        ]
