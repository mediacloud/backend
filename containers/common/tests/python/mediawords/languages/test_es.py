#!/usr/bin/env py.test

from unittest import TestCase

from mediawords.languages.es import SpanishLanguage


# noinspection SpellCheckingInspection
class TestSpanishLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = SpanishLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "es"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "el" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["antiinflamatorias", "habitualmente", "Además"]
        expected_stems = ["antiinflamatori", "habitual", "ademas"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            El paracetamol (DCI) o acetaminofén (acetaminofeno) es un fármaco con propiedades analgésicas, sin
            propiedades antiinflamatorias clínicamente significativas. Actúa inhibiendo la síntesis de prostaglandinas,
            mediadores celulares responsables de la aparición del dolor. Además, tiene efectos antipiréticos. Se
            presenta habitualmente en forma de cápsulas, comprimidos, supositorios o gotas de administración oral.
        """
        expected_sentences = [
            (
                'El paracetamol (DCI) o acetaminofén (acetaminofeno) es un fármaco con propiedades analgésicas, sin '
                'propiedades antiinflamatorias clínicamente significativas.'
            ),
            (
                'Actúa inhibiendo la síntesis de prostaglandinas, mediadores celulares responsables de la aparición '
                'del dolor.'
            ),
            'Además, tiene efectos antipiréticos.',
            'Se presenta habitualmente en forma de cápsulas, comprimidos, supositorios o gotas de administración oral.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_period_in_number(self):
        """Period in the middle of the number."""
        input_text = """
            Esa misma noche el ministro de Defensa, Ehud Barak, consiguió el apoyo del gabinete israelí para ampliar la
            movilización de reservistas de 30.000 a 75.000, de cara a una posible operación terrestre sobre la Franja de
            Gaza. El ministro de Relaciones Exteriores Avigdor Lieberman, aclaró que el gobierno actual no estaba
            considerando el derrocamiento del gobierno de Hamas en la Franja, y que lo tendría que decidir el próximo
            gobierno.
        """
        expected_sentences = [
            (
                'Esa misma noche el ministro de Defensa, Ehud Barak, consiguió el apoyo del gabinete israelí para '
                'ampliar la movilización de reservistas de 30.000 a 75.000, de cara a una posible operación terrestre '
                'sobre la Franja de Gaza.'
            ),
            (
                'El ministro de Relaciones Exteriores Avigdor Lieberman, aclaró que el gobierno actual no estaba '
                'considerando el derrocamiento del gobierno de Hamas en la Franja, y que lo tendría que decidir el '
                'próximo gobierno.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = "la movilización de reservistas de 30.000 a 75.000"
        expected_words = ["la", "movilización", "de", "reservistas", "de", "30.000", "a", "75.000", ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
