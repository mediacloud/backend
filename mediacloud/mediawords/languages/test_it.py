from unittest import TestCase

from mediawords.languages.it import ItalianLanguage


# noinspection SpellCheckingInspection
class TestItalianLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = ItalianLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "it"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "fummo" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["combattuto", "provvisorio", "politico"]
        expected_stems = ["combatt", "provvisor", "polit"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            Charles André Joseph Marie de Gaulle (Lilla, 22 novembre 1890 – Colombey-les-deux-Églises, 9 novembre 1970)
            è stato un generale e politico francese. Dopo la sua partenza per Londra nel giugno del 1940, divenne il
            capo della Francia libera, che ha combattuto contro il regime di Vichy e contro l'occupazione italiana e
            tedesca della Francia durante la seconda guerra mondiale. Presidente del governo provvisorio della
            Repubblica francese 1944-1946, ultimo presidente del Consiglio (1958-1959) della Quarta Repubblica, è stato
            il promotore della fondazione della Quinta Repubblica, della quale fu primo presidente dal 1959-1969.
        """
        expected_sentences = [
            (
                'Charles André Joseph Marie de Gaulle (Lilla, 22 novembre 1890 – Colombey-les-deux-Églises, 9 novembre '
                '1970) è stato un generale e politico francese.'
            ),
            (
                "Dopo la sua partenza per Londra nel giugno del 1940, divenne il capo della Francia libera, che ha "
                "combattuto contro il regime di Vichy e contro l'occupazione italiana e tedesca della Francia durante "
                "la seconda guerra mondiale."
            ),
            (
                'Presidente del governo provvisorio della Repubblica francese 1944-1946, ultimo presidente del '
                'Consiglio (1958-1959) della Quarta Repubblica, è stato il promotore della fondazione della Quinta '
                'Repubblica, della quale fu primo presidente dal 1959-1969.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_period_in_number(self):
        """Period in the middle of the number."""
        input_text = """
            Nel 1964, l'azienda di Berlusconi apre un cantiere a Brugherio per edificare una città modello da 4.000
            abitanti. I primi condomini sono pronti già nel 1965, ma non si vendono con facilità.
        """
        expected_sentences = [
            (
                "Nel 1964, l'azienda di Berlusconi apre un cantiere a Brugherio per edificare una città modello da "
                "4.000 abitanti."
            ),
            "I primi condomini sono pronti già nel 1965, ma non si vendono con facilità.",
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_acronym(self):
        """Acronym ("c.a.p.")."""
        input_text = """
            La precompressione è una tecnica industriale consistente nel produrre artificialmente una tensione nella
            struttura dei materiali da costruzione, e in special modo nel calcestruzzo armato, allo scopo di migliorarne
            le caratteristiche di resistenza. Nel calcestruzzo armato precompresso (nel linguaggio comune chiamato anche
            cemento armato precompresso, abbreviato con l'acronimo c.a.p.), la precompressione viene utilizzata per
            sopperire alla scarsa resistenza a trazione del conglomerato cementizio.
        """
        expected_sentences = [
            (
                "La precompressione è una tecnica industriale consistente nel produrre artificialmente una tensione "
                "nella struttura dei materiali da costruzione, e in special modo nel calcestruzzo armato, allo scopo "
                "di migliorarne le caratteristiche di resistenza."
            ),
            (
                "Nel calcestruzzo armato precompresso (nel linguaggio comune chiamato anche cemento armato "
                "precompresso, abbreviato con l'acronimo c.a.p.), la precompressione viene utilizzata per sopperire "
                "alla scarsa resistenza a trazione del conglomerato cementizio."
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = "I primi condomini sono pronti già nel 1965, ma non si vendono con facilità."
        expected_words = [
            "i", "primi", "condomini", "sono", "pronti", "già", "nel", "1965", "ma", "non", "si", "vendono", "con",
            "facilità",
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
