#!/usr/bin/env py.test

from unittest import TestCase

from mediawords.languages.ha import HausaLanguage


# noinspection SpellCheckingInspection
class TestHausaLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = HausaLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "ha"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "wannan" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["ababen", "abin", "abincin"]
        expected_stems = ["ababe", "abin", "abinci"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            Ƙabilar Hausa dai, ƙabila ce dake zaune a arewa maso yammacin tarayyar Nijeriya da kudu maso yammacin
            jamhuriyyar Nijar. Kabilace mai ɗimbin al'umma, amma kuma a al'adance mai mutuƙar haɗaka, akalla akwai sama
            da mutane miliyan tamanin da harshen yake asali gare su. A tarihance ƙabilar Hausawa na tattare a salasalar
            birane. Hausawa dai sun sami kafa daularsu ne tun daga shekarun 1300's, sa'adda suka sami nasarori da
            dauloli kamar su daular Mali, Songhai, Borno da kuma.
        """
        expected_sentences = [
            (
                "Ƙabilar Hausa dai, ƙabila ce dake zaune a arewa maso yammacin tarayyar Nijeriya da kudu maso yammacin "
                "jamhuriyyar Nijar."
            ),
            (
                "Kabilace mai ɗimbin al'umma, amma kuma a al'adance mai mutuƙar haɗaka, akalla akwai sama da mutane "
                "miliyan tamanin da harshen yake asali gare su."
            ),
            "A tarihance ƙabilar Hausawa na tattare a salasalar birane.",
            (
                "Hausawa dai sun sami kafa daularsu ne tun daga shekarun 1300's, sa'adda suka sami nasarori da dauloli "
                "kamar su daular Mali, Songhai, Borno da kuma."
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = (
            "Ƙabilar Hausa dai, ƙabila ce dake zaune a arewa maso yammacin tarayyar Nijeriya da kudu maso yammacin "
            "jamhuriyyar Nijar."
        )
        expected_words = [
            "ƙabilar", "hausa", "dai", "ƙabila", "ce", "dake", "zaune", "a", "arewa", "maso", "yammacin", "tarayyar",
            "nijeriya", "da", "kudu", "maso", "yammacin", "jamhuriyyar", "nijar",
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
