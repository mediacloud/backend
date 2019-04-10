#!/usr/bin/env py.test

from unittest import TestCase

from mediawords.languages.no import NorwegianLanguage


# noinspection SpellCheckingInspection
class TestNorwegianLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = NorwegianLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "no"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "dykkar" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["selvstendig", "Protektoratet"]
        expected_stems = ["selvstend", "protektorat"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            Tuvalu er en øynasjon i Polynesia i Stillehavet. Landet har i overkant av 10 000 innbyggere, og er dermed
            den selvstendige staten i verden med tredje færrest innbyggere, etter Vatikanstaten og Nauru. Tuvalu består
            av ni bebodde atoller spredt over et havområde på rundt 1,3 millioner km². Med et landareal på bare 26 km²
            er det verdens fjerde minste uavhengige stat. De nærmeste øygruppene er Kiribati, Nauru, Samoa og Fiji.
        """
        expected_sentences = [
            'Tuvalu er en øynasjon i Polynesia i Stillehavet.',
            (
                'Landet har i overkant av 10 000 innbyggere, og er dermed den selvstendige staten i verden med tredje '
                'færrest innbyggere, etter Vatikanstaten og Nauru.'
            ),
            'Tuvalu består av ni bebodde atoller spredt over et havområde på rundt 1,3 millioner km².',
            'Med et landareal på bare 26 km² er det verdens fjerde minste uavhengige stat.',
            'De nærmeste øygruppene er Kiribati, Nauru, Samoa og Fiji.'
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_date(self):
        """Date ("1. oktober 1978")."""
        input_text = """
            De første innbyggerne på Tuvalu var polynesiske folk. Den spanske oppdageren Álvaro de Mendaña ble i 1568
            den første europeeren som fikk øye på landet. I 1819 fikk det navnet Elliceøyene. Det kom under britisk
            innflytelse på slutten av 1800-tallet, og fra 1892 til 1976 utgjorde det en del av det britiske
            protektoratet og kolonien Gilbert- og Elliceøyene, sammen med en del av dagens Kiribati. Tuvalu ble
            selvstendig 1. oktober 1978.
        """
        expected_sentences = [
            'De første innbyggerne på Tuvalu var polynesiske folk.',
            'Den spanske oppdageren Álvaro de Mendaña ble i 1568 den første europeeren som fikk øye på landet.',
            'I 1819 fikk det navnet Elliceøyene.',
            (
                'Det kom under britisk innflytelse på slutten av 1800-tallet, og fra 1892 til 1976 utgjorde det en del '
                'av det britiske protektoratet og kolonien Gilbert- og Elliceøyene, sammen med en del av dagens '
                'Kiribati.'
            ),
            'Tuvalu ble selvstendig 1. oktober 1978.'
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_abbreviation(self):
        """Abbreviation."""
        input_text = "Tettest er den på hovedatollen Funafuti, med over 1000 innb./km²."
        expected_sentences = ["Tettest er den på hovedatollen Funafuti, med over 1000 innb./km²."]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = "Tettest er den på hovedatollen Funafuti, med over 1000 innb./km²."
        expected_words = [
            "tettest", "er", "den", "på", "hovedatollen", "funafuti", "med", "over", "1000", "innb", "km²",
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
