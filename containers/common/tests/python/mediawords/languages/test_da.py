#!/usr/bin/env py.test

from unittest import TestCase

from mediawords.languages.da import DanishLanguage


# noinspection SpellCheckingInspection
class TestDanishLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = DanishLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "da"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "efter" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["elleve", "Nordenskiöldbreen"]
        expected_stems = ["ellev", "nordenskiöldbre"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            Sør-Georgia (engelsk: South Georgia) er ei øy i Søratlanteren som høyrer til det britiske oversjøiske
            territoriet Sør-Georgia og Sør-Sandwichøyane. Argentina gjer krav på Sør-Georgia og resten av dei britiske
            territoria i Søratlanteren. Sør-Georgia har eit areal på 3 756 km² og er 170 km lang og 30 km brei. Det
            høgste punktet på øya er Mount Paget på 2 934 moh. I alt elleve fjelltoppar er høgare enn 2 000 moh. 75 % av
            øya er dekt av snø og is. Det er meir enn 150 isbrear på øya, og Nordenskiöldbreen er den største. Øya har
            ingen fastbuande, men har forskingspersonell som er tilknytte museumsdrifta og forskingsstasjonane på
            Birdøya og King Edward Point.
        """
        expected_sentences = [
            (
                "Sør-Georgia (engelsk: South Georgia) er ei øy i Søratlanteren som høyrer til det britiske oversjøiske "
                "territoriet Sør-Georgia og Sør-Sandwichøyane."
            ),
            "Argentina gjer krav på Sør-Georgia og resten av dei britiske territoria i Søratlanteren.",
            "Sør-Georgia har eit areal på 3 756 km² og er 170 km lang og 30 km brei.",
            "Det høgste punktet på øya er Mount Paget på 2 934 moh.",
            "I alt elleve fjelltoppar er høgare enn 2 000 moh.",
            "75 % av øya er dekt av snø og is.",
            "Det er meir enn 150 isbrear på øya, og Nordenskiöldbreen er den største.",
            (
                "Øya har ingen fastbuande, men har forskingspersonell som er tilknytte museumsdrifta og "
                "forskingsstasjonane på Birdøya og King Edward Point."
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_date(self):
        """Date ("14. januar 1776")"""
        input_text = """
            Sør-Georgia vart oppdaga av Antoine de la Roché i april 1675, fartøyet hans var kome ut av kurs på ein
            segltur frå Lima i Peru til England. Øya vart på ny sett av spanjolen Gregorio Jerez i 1756. James Cook kom
            til Sør-Georgia 14. januar 1776 og var den fyrste som gjekk i land på øya.
        """
        expected_sentences = [
            (
                "Sør-Georgia vart oppdaga av Antoine de la Roché i april 1675, fartøyet hans var kome ut av kurs på "
                "ein segltur frå Lima i Peru til England."
            ),
            "Øya vart på ny sett av spanjolen Gregorio Jerez i 1756.",
            "James Cook kom til Sør-Georgia 14. januar 1776 og var den fyrste som gjekk i land på øya.",
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = (
            "James Cook kom til Sør-Georgia 14. januar 1776 og var den fyrste som gjekk i land på øya."
        )
        expected_words = [
            "james", "cook", "kom", "til", "sør-georgia", "14", "januar", "1776", "og", "var", "den", "fyrste", "som",
            "gjekk", "i", "land", "på", "øya",
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
