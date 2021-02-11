from unittest import TestCase

from mediawords.languages.zh import ChineseLanguage


# noinspection SpellCheckingInspection
class TestChineseLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = ChineseLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "zh"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "不勝" in stop_words
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

        # Chinese-only punctuation
        sentences = self.__tokenizer.split_text_to_sentences(
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

        sentences = self.__tokenizer.split_text_to_sentences("""
            范妮·伊姆利，是英国女权主义者玛丽·沃斯通克拉夫特与美国商人吉尔伯特·伊姆利的私生女。
            在范妮出生不久，伊姆利便将沃斯通克拉夫特抛弃在了法国大革命日趋混乱的局势之中。
            在经历了这次失意的爱情后，沃斯通克拉夫特与哲学家戈德温建立了亲密的关系，并最终与他结婚。
            1797年，沃斯通克拉夫特死于产后并发症，将三岁的范妮与新生的玛丽·沃斯通克拉夫特·戈德温留给了戈德温一人抚育。
            四年后，戈德温与第二任妻子结婚，范妮姐妹俩都不喜欢新的戈德温太太。
            1814年，年少的玛丽与新戈德温太太带来的女儿克莱尔·克莱尔蒙特一同离家出走，并与浪漫主义诗人雪莱前往了欧洲大陆。
            独自留下的范妮于1816年服毒自杀，时年22岁。
        """)
        assert sentences == [
            '范妮·伊姆利，是英国女权主义者玛丽·沃斯通克拉夫特与美国商人吉尔伯特·伊姆利的私生女。',
            '在范妮出生不久，伊姆利便将沃斯通克拉夫特抛弃在了法国大革命日趋混乱的局势之中。',
            '在经历了这次失意的爱情后，沃斯通克拉夫特与哲学家戈德温建立了亲密的关系，并最终与他结婚。',
            '1797年，沃斯通克拉夫特死于产后并发症，将三岁的范妮与新生的玛丽·沃斯通克拉夫特·戈德温留给了戈德温一人抚育。',
            '四年后，戈德温与第二任妻子结婚，范妮姐妹俩都不喜欢新的戈德温太太。',
            '1814年，年少的玛丽与新戈德温太太带来的女儿克莱尔·克莱尔蒙特一同离家出走，并与浪漫主义诗人雪莱前往了欧洲大陆。',
            '独自留下的范妮于1816年服毒自杀，时年22岁。',
        ]

        # Chinese-only punctuation, no EOS at the end of the sentence
        sentences = self.__tokenizer.split_text_to_sentences(
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
        sentences = self.__tokenizer.split_text_to_sentences(
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
        sentences = self.__tokenizer.split_text_to_sentences("""問責制既不能吸引政治人才加入政府。
This is some English text out of the blue. 
時任政務司長林鄭月娥被指在未有公開諮詢下，突然宣布西九文化區興建故宮博物館，並委聘建築師嚴迅奇擔任設計顧問，被立法會議員向廉政公署舉報。
This is some more English text.
This is some more English text.
Dsds.
""")
        assert sentences == [
            "問責制既不能吸引政治人才加入政府。",
            "This is some English text out of the blue.",
            "時任政務司長林鄭月娥被指在未有公開諮詢下，突然宣布西九文化區興建故宮博物館，並委聘建築師嚴迅奇擔任設計顧問，被立法會議員向廉政公署舉報。",
            "This is some more English text.",
            "This is some more English text.",
            "Dsds.",
        ]

        # Chinese and English sentences separates by double-newlines
        # (test has extra whitespace between line breaks)
        sentences = self.__tokenizer.split_text_to_sentences("""
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
        sentences = self.__tokenizer.split_text_to_sentences("""
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
            "Something",
            "else",
            "Something",
            "completely",
            "different",
        ]

        # Chinese sentence
        words = self.__tokenizer.split_sentence_to_words(
            "時任政務司長林鄭月娥被指在未有公開諮詢下，突然宣布西九文化區興建故宮博物館，並委聘建築師嚴迅奇擔任設計顧問，被立法會議員向廉政公署舉報。"
        )
        assert words == [
            '時任',
            '政務司長',
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

        # Tokenize names of top political figures or celebrities
        words = self.__tokenizer.split_sentence_to_words(
            "習近平王毅黃毓民汤家骅"
        )
        assert words == [
            "習近平",
            "王毅",
            "黃毓民",
            "汤家骅",
        ]

        # Chinese + English sentence
        words = self.__tokenizer.split_sentence_to_words("他建議想學好英文，必須人格分裂、要代入外國人的思想（mindset）。")
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
        words = self.__tokenizer.split_sentence_to_words(
            "Badger、badger。Badger・Badger『badger』「Badger」badger？Badger！Badger！？"
            "Badger【badger】Badger～badger（badger）《Badger》，badger；badger……badger：badger"
        )
        assert words == [
            'Badger', 'badger', 'Badger', 'Badger', 'badger', 'Badger', 'badger', 'Badger', 'Badger',
            'Badger', 'badger', 'Badger', 'badger', 'badger', 'Badger', 'badger', 'badger', 'badger', 'badger',
        ]
