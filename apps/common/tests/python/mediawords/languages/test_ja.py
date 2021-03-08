from unittest import TestCase

import os

from mediawords.languages.ja import JapaneseLanguage


# noinspection SpellCheckingInspection
class TestJapaneseLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = JapaneseLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "ja"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "向こう" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        assert self.__tokenizer.stem_words(['abc']) == ['abc']

    def test_split_text_to_sentences(self):
        # noinspection PyTypeChecker
        assert self.__tokenizer.split_text_to_sentences(None) == []
        assert self.__tokenizer.split_text_to_sentences("") == []
        assert self.__tokenizer.split_text_to_sentences(" ") == []
        assert self.__tokenizer.split_text_to_sentences(".") == ["."]

        # English-only punctuation
        sentences = self.__tokenizer.split_text_to_sentences(
            "Hello. How do you do? I'm doing okay."
        )
        assert sentences == [
            "Hello.",
            "How do you do?",
            "I'm doing okay.",
        ]

        # English-only punctuation, no period at the end of sentence
        sentences = self.__tokenizer.split_text_to_sentences(
            "Hello. How do you do? I'm doing okay"
        )
        assert sentences == [
            "Hello.",
            "How do you do?",
            "I'm doing okay",
        ]

        # Japanese-only punctuation
        sentences = self.__tokenizer.split_text_to_sentences(
            "ジアゼパムはてんかんや興奮の治療に用いられる。"
            "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。"
            "鎮静作用を生かし手術などの前投薬にも用いられる。"
            "アルコールやドラッグによる離脱症状の治療にも用いられる。"
        )
        assert sentences == [
            "ジアゼパムはてんかんや興奮の治療に用いられる。",
            "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。",
            "鎮静作用を生かし手術などの前投薬にも用いられる。",
            "アルコールやドラッグによる離脱症状の治療にも用いられる。",
        ]

        # Japanese-only punctuation, no EOS at the end of the sentence
        sentences = self.__tokenizer.split_text_to_sentences(
            "ジアゼパムはてんかんや興奮の治療に用いられる。"
            "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。"
            "鎮静作用を生かし手術などの前投薬にも用いられる。"
            "アルコールやドラッグによる離脱症状の治療にも用いられる"
        )
        assert sentences == [
            "ジアゼパムはてんかんや興奮の治療に用いられる。",
            "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。",
            "鎮静作用を生かし手術などの前投薬にも用いられる。",
            "アルコールやドラッグによる離脱症状の治療にも用いられる",
        ]

        # Japanese and English punctuation
        sentences = self.__tokenizer.split_text_to_sentences(
            "ジアゼパムはてんかんや興奮の治療に用いられる。"
            "This is some English text out of the blue. "
            "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。"
            "This is some more English text."
        )
        assert sentences == [
            "ジアゼパムはてんかんや興奮の治療に用いられる。",
            "This is some English text out of the blue.",
            "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。",
            "This is some more English text.",
        ]

        # Japanese and English punctuation (with newlines)
        sentences = self.__tokenizer.split_text_to_sentences("""ジアゼパムはてんかんや興奮の治療に用いられる。
This is some English text out of the blue. 
また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。
This is some more English text.
This is some more English text.
Dsds.
""")
        assert sentences == [
            "ジアゼパムはてんかんや興奮の治療に用いられる。",
            "This is some English text out of the blue.",
            "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている。",
            "This is some more English text.",
            "This is some more English text.",
            "Dsds.",
        ]

        # Japanese and English sentences separates by double-newlines
        # (test has extra whitespace between line breaks)
        sentences = self.__tokenizer.split_text_to_sentences("""
ジアゼパムはてんかんや興奮の治療に用いられる
  
This is some English text out of the blue
  
また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている
  
This is some more English text
""")
        assert sentences == [
            "ジアゼパムはてんかんや興奮の治療に用いられる",
            "This is some English text out of the blue",
            "また、有痛性筋痙攣（いわゆる“こむらがえり”）などの筋痙攣の治療にはベンゾジアゼピン類の中で最も有用であるとされている",
            "This is some more English text",
        ]

        # Japanese and English sentences in a list
        # (test has extra whitespace between line breaks)
        sentences = self.__tokenizer.split_text_to_sentences("""
ジアゼパムはてんかんや興奮の治療に用いられる

* This is some English text out of the blue. Some more English text.
* ジアゼパムはてんかんや興奮の治療に用いられる。ジアゼパムはてんかんや興奮の治療に用いられる 

This is some more English text
    """)
        assert sentences == [
            "ジアゼパムはてんかんや興奮の治療に用いられる",
            "* This is some English text out of the blue.",
            "Some more English text.",
            "* ジアゼパムはてんかんや興奮の治療に用いられる。",
            "ジアゼパムはてんかんや興奮の治療に用いられる",
            "This is some more English text",
        ]

    def test_split_sentence_to_words(self):
        # noinspection PyTypeChecker
        assert self.__tokenizer.split_sentence_to_words(None) == []
        assert self.__tokenizer.split_sentence_to_words("") == []
        assert self.__tokenizer.split_sentence_to_words(" ") == []
        assert self.__tokenizer.split_sentence_to_words(".") == []

        # English sentence
        words = self.__tokenizer.split_sentence_to_words("How do you do?")
        assert words == [
            "How",
            "do",
            "you",
            "do",
        ]

        # English sentence, no period at the end of the sentence
        words = self.__tokenizer.split_sentence_to_words("How do you do")
        assert words == [
            "How",
            "do",
            "you",
            "do",
        ]

        # English sentence, literal string "EOS"
        words = self.__tokenizer.split_sentence_to_words("EOS this, EOS that.")
        assert words == [
            "EOS",
            "this",
            "EOS",
            "that",
        ]

        # English sentence; tab, newline and comma characters
        words = self.__tokenizer.split_sentence_to_words(
            "Something\tSomething else\nSomething, completely, different."
        )
        assert words == [
            "Something",
            "Something else",  # curiously, mecab-ipadic-neologd treats "something else" as a single token
            "Something",
            "completely",
            "different",
        ]

        # Japanese sentence
        words = self.__tokenizer.split_sentence_to_words(
            "10日放送の「中居正広のミになる図書館」（テレビ朝日系）で、SMAPの中居正広が、篠原信一の過去の勘違いを明かす一幕があった。"
        )
        assert words == [
            '10日',
            '放送',
            '中居正広のミになる図書館',
            'テレビ朝日',
            'SMAP',
            '中居正広',
            '篠原信一',
            '勘違い',
            '一幕',
        ]

        # Japanese + English sentence
        words = self.__tokenizer.split_sentence_to_words("pythonが大好きです")
        assert words == [
            "python",
            "大好き",
        ]

        # Japanese punctuation
        words = self.__tokenizer.split_sentence_to_words(
            "Badger、badger。Badger・Badger『badger』badger？Badger！Badger！？"
            "Badger【badger】Badger～badger▽badger（badger）"
        )
        assert words == [
            'Badger', 'badger', 'Badger', 'Badger', 'badger', 'badger', 'Badger',
            'Badger', 'Badger', 'badger', 'Badger', 'badger', 'badger', 'badger',
        ]


def test_mecab_pos_ids():
    """Make sure hardcoded POS IDs point to expected (hardcoded) parts of speech."""
    # noinspection PyProtectedMember
    dictionary_path = JapaneseLanguage._mecab_ipadic_neologd_path()
    assert dictionary_path is not None
    assert os.path.isdir(dictionary_path)

    pos_id_path = os.path.join(dictionary_path, "pos-id.def")
    assert os.path.isfile(pos_id_path)

    pos_id_map = {}
    with open(pos_id_path, 'r', encoding='utf-8') as pos_id_file:
        for line in pos_id_file:
            line = line.strip()
            if len(line) > 0:
                pos_string, pos_number = line.split(' ')
                assert pos_string
                assert len(pos_string) > 0
                assert pos_number
                assert pos_number.isdigit()

                pos_number = int(pos_number)
                pos_id_map[pos_number] = pos_string

    # noinspection PyProtectedMember
    allowed_pos_ids = JapaneseLanguage._mecab_allowed_pos_ids()

    for allowed_pos_id in allowed_pos_ids:
        assert allowed_pos_ids[allowed_pos_id] == pos_id_map[allowed_pos_id]
