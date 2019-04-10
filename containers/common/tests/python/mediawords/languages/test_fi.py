#!/usr/bin/env py.test

from unittest import TestCase

from mediawords.languages.fi import FinnishLanguage


# noinspection SpellCheckingInspection
class TestFinnishLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = FinnishLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "fi"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "ette" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["kalaheimo", "koralliriutoilla", "ilmaa"]
        expected_stems = ["kalaheimo", "koralliriuto", "ilm"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            Pallokalat (Tetraodontidae) on kalaheimo, johon kuuluu sekä koralliriutoilla, murtovedessä että makeassa
            vedessä eläviä lajeja. Vuonna 2004 heimosta tunnettiin 187 lajia, joista jotkut elävät makeassa tai
            murtovedessä, jotkut taas viettävät osan elämästään murto- ja osan merivedessä. Pallokalat ovat saaneet
            nimensä siitä, että pelästyessään ne imevät itsensä täyteen vettä tai ilmaa ja pullistuvat palloiksi. Toinen
            pullistelevien kalojen heimo on siilikalat. Pallokalat ovat terävähampaisia petoja, jotka syövät muun muassa
            simpukoita, kotiloita ja muita kaloja. Pallokaloja voidaan pitää akvaariossa, mutta hoitajan tulee olla
            perehtynyt niiden hoitoon hyvin.

        """
        expected_sentences = [
            (
                'Pallokalat (Tetraodontidae) on kalaheimo, johon kuuluu sekä koralliriutoilla, murtovedessä että '
                'makeassa vedessä eläviä lajeja.'
            ),
            (
                'Vuonna 2004 heimosta tunnettiin 187 lajia, joista jotkut elävät makeassa tai murtovedessä, jotkut '
                'taas viettävät osan elämästään murto- ja osan merivedessä.'
            ),
            (
                'Pallokalat ovat saaneet nimensä siitä, että pelästyessään ne imevät itsensä täyteen vettä tai ilmaa '
                'ja pullistuvat palloiksi.'
            ),
            'Toinen pullistelevien kalojen heimo on siilikalat.',
            'Pallokalat ovat terävähampaisia petoja, jotka syövät muun muassa simpukoita, kotiloita ja muita kaloja.',
            'Pallokaloja voidaan pitää akvaariossa, mutta hoitajan tulee olla perehtynyt niiden hoitoon hyvin.'
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_period_number(self):
        """Number followed by a period."""
        input_text = "Katso Teiniäidit-sarjan 8. jakso ennakkoon."
        expected_sentences = ['Katso Teiniäidit-sarjan 8. jakso ennakkoon.']
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_date_with_period(self):
        """Dates with a period ("31. tammikuuta", "1. helmikuuta")."""
        input_text = "Aikaraja ehdotusten lähettämiseen on 31. tammikuuta. Rauhanpalkinnon aikaraja on 1. helmikuuta."
        expected_sentences = [
            'Aikaraja ehdotusten lähettämiseen on 31. tammikuuta.',
            'Rauhanpalkinnon aikaraja on 1. helmikuuta.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_abbreviations(self):
        """Abbreviations."""
        input_text = """
            Ajanlaskun ensimmäisenä pidetty vuosi on 1 jKr., ja vasta sen päätyttyä oli Kristuksen syntymästä kulunut 1
            vuosi.
        """
        expected_sentences = [
            (
                'Ajanlaskun ensimmäisenä pidetty vuosi on 1 jKr., ja vasta sen päätyttyä oli Kristuksen syntymästä '
                'kulunut 1 vuosi.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_numbers(self):
        """Numbers."""
        input_text = """
            Vuotta 0 ei jostakin syystä ole otettu käyttöön juliaanisessa eikä gregoriaanisessa ajanlaskussa, vaikka
            normaalisti ajan kulun laskeminen aloitetaan nollasta, kuten kalenterivuorokausi kello 0.00 ja vasta
            ensimmäisen tunnin kuluttua on kello 1.00.
        """
        expected_sentences = [
            (
                'Vuotta 0 ei jostakin syystä ole otettu käyttöön juliaanisessa eikä gregoriaanisessa ajanlaskussa, '
                'vaikka normaalisti ajan kulun laskeminen aloitetaan nollasta, kuten kalenterivuorokausi kello 0.00 ja '
                'vasta ensimmäisen tunnin kuluttua on kello 1.00.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = "kuten kalenterivuorokausi kello 0.00 ja vasta ensimmäisen tunnin kuluttua on kello 1.00."
        expected_words = [
            "kuten", "kalenterivuorokausi", "kello", "0.00", "ja", "vasta", "ensimmäisen", "tunnin", "kuluttua", "on",
            "kello", "1.00",
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
