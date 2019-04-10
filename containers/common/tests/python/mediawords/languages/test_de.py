#!/usr/bin/env py.test

from unittest import TestCase

from mediawords.languages.de import GermanLanguage


# noinspection SpellCheckingInspection
class TestGermanLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = GermanLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "de"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "dazu" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["Records", "wollte", "es", "ursprünglich", "am", "8.", "Dezember", "1987", "veröffentlichen"]
        expected_stems = ["record", "wollt", "es", "ursprung", "am", "8.", "dezemb", "1987", "veroffent"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        """Simple paragraph + period in the middle of the date + period in the middle of the number."""
        input_text = """
            Das Black Album (deutsch: Schwarzes Album) ist das sechzehnte Studioalbum des US-amerikanischen Musikers
            Prince. Es erschien am 22. November 1994 bei dem Label Warner Bros. Records. Prince hatte das Album bereits
            während der Jahre 1986 und 1987 aufgenommen und Warner Bros. Records wollte es ursprünglich am 8. Dezember
            1987 veröffentlichen. Allerdings zog Prince das Album eine Woche vor dem geplanten Veröffentlichungstermin
            ohne Angabe von Gründen zurück. Anschließend entwickelte es sich mit über 250.000 Exemplaren zu einem der
            meistverkauften Bootlegs der Musikgeschichte, bis es sieben Jahre später offiziell veröffentlicht wurde.
        """
        expected_sentences = [
            (
                "Das Black Album (deutsch: Schwarzes Album) ist das sechzehnte Studioalbum des US-amerikanischen "
                "Musikers Prince."
            ),
            "Es erschien am 22. November 1994 bei dem Label Warner Bros. Records.",
            (
                "Prince hatte das Album bereits während der Jahre 1986 und 1987 aufgenommen und Warner Bros. Records "
                "wollte es ursprünglich am 8. Dezember 1987 veröffentlichen."
            ),
            (
                "Allerdings zog Prince das Album eine Woche vor dem geplanten Veröffentlichungstermin ohne Angabe von "
                "Gründen zurück."
            ),
            (
                "Anschließend entwickelte es sich mit über 250.000 Exemplaren zu einem der meistverkauften Bootlegs "
                "der Musikgeschichte, bis es sieben Jahre später offiziell veröffentlicht wurde."
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = (
            "Anschließend entwickelte es sich mit über 250.000 Exemplaren zu einem der meistverkauften Bootlegs "
            "der Musikgeschichte, bis es sieben Jahre später offiziell veröffentlicht wurde."
        )
        expected_words = [
            "anschließend", "entwickelte", "es", "sich", "mit", "über", "250.000", "exemplaren", "zu", "einem", "der",
            "meistverkauften", "bootlegs", "der", "musikgeschichte", "bis", "es", "sieben", "jahre", "später",
            "offiziell", "veröffentlicht", "wurde",
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
