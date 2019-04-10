#!/usr/bin/env py.test

from unittest import TestCase

from mediawords.languages.ro import RomanianLanguage


# noinspection SpellCheckingInspection
class TestRomanianLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = RomanianLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "ro"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "acesta" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["apropierea", "Splaiului"]
        expected_stems = ["apropier", "splai"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            În prezent, din întreg ansamblul mănăstirii s-a mai păstrat doar biserica și o clopotniță. Acestea se află
            amplasate pe strada Sapienței din sectorul 5 al municipiului București, în spatele unor blocuri construite
            în timpul regimului comunist, din apropierea Splaiului Independenței și a parcului Izvor. În 1813 Mănăstirea
            Mihai-Vodă „era printre mănăstirile mari ale țării”.
        """
        expected_sentences = [
            'În prezent, din întreg ansamblul mănăstirii s-a mai păstrat doar biserica și o clopotniță.',
            (
                'Acestea se află amplasate pe strada Sapienței din sectorul 5 al municipiului București, în spatele '
                'unor blocuri construite în timpul regimului comunist, din apropierea Splaiului Independenței și a '
                'parcului Izvor.'
            ),
            'În 1813 Mănăstirea Mihai-Vodă „era printre mănăstirile mari ale țării”.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_names(self):
        """Names ("Sf. Mc. Trifon" and others)."""
        input_text = """
            În prezent în interiorul bisericii există o raclă în care sunt păstrate moștele următorilor Sfinți: Sf. Ioan
            Iacob Hozevitul, Sf. Xenia Petrovna, Sf. Teofil, Sf. Mc. Sevastiana, Sf. Mc. Ciprian, Sf. Mc. Iustina, Sf.
            Mc. Clement, Sf. Mc. Trifon, Cuv. Auxenție, Sf. Dionisie Zakynthos, Sf. Mc. Anastasie, Sf. Mc. Panaghiotis,
            Sf. Spiridon, Sf. Nifon II, Sf. Ignatie Zagorski, Sf. Prooroc Ioan Botezătorul, Cuv. Sava cel Sfințit, Sf.
            Mc. Eustatie, Sf. Mc. Theodor Stratilat, Cuv. Paisie, Cuv. Stelian Paflagonul, Sf. Mc. Mercurie, Sf. Mc.
            Arhidiacon Ștefan, Sf. Apostol Andrei, Sf. Mc. Dimitrie, Sf. Mc. Haralambie.
        """
        expected_sentences = [
            (
                'În prezent în interiorul bisericii există o raclă în care sunt păstrate moștele următorilor Sfinți: '
                'Sf. Ioan Iacob Hozevitul, Sf. Xenia Petrovna, Sf. Teofil, Sf. Mc. Sevastiana, Sf. Mc. Ciprian, Sf. '
                'Mc. Iustina, Sf. Mc. Clement, Sf. Mc. Trifon, Cuv. Auxenție, Sf. Dionisie Zakynthos, Sf. Mc. '
                'Anastasie, Sf. Mc. Panaghiotis, Sf. Spiridon, Sf. Nifon II, Sf. Ignatie Zagorski, Sf. Prooroc Ioan '
                'Botezătorul, Cuv. Sava cel Sfințit, Sf. Mc. Eustatie, Sf. Mc. Theodor Stratilat, Cuv. Paisie, Cuv. '
                'Stelian Paflagonul, Sf. Mc. Mercurie, Sf. Mc. Arhidiacon Ștefan, Sf. Apostol Andrei, Sf. Mc. '
                'Dimitrie, Sf. Mc. Haralambie.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_abbreviation(self):
        """Abbreviation ("nr.4")."""
        input_text = """
            Translatarea în pantă a bisericii, pe o distanță de 289 m și coborâtă pe verticală cu 6,2 m, a avut loc în
            anul 1985. Operațiune în sine de translatare a edificiului, de pe Dealul Mihai Vodă, fosta stradă a
            Arhivelor nr.2 și până în locul în care se află și astăzi, Strada Sapienței nr.4, în apropierea malului
            Dâmboviței, a fost considerată la vremea respectivă o performanță deosebită.
        """
        expected_sentences = [
            (
                'Translatarea în pantă a bisericii, pe o distanță de 289 m și coborâtă pe verticală cu 6,2 m, a avut '
                'loc în anul 1985.'
            ),
            (
                'Operațiune în sine de translatare a edificiului, de pe Dealul Mihai Vodă, fosta stradă a Arhivelor '
                'nr.2 și până în locul în care se află și astăzi, Strada Sapienței nr.4, în apropierea malului '
                'Dâmboviței, a fost considerată la vremea respectivă o performanță deosebită.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = 'În 1813 Mănăstirea Mihai-Vodă „era printre mănăstirile mari ale țării”.'
        expected_words = [
            'în', '1813', 'mănăstirea', 'mihai-vodă', 'era', 'printre', 'mănăstirile', 'mari', 'ale', 'țării',
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
