from unittest import TestCase

from mediawords.languages.ca import CatalanLanguage


# noinspection SpellCheckingInspection
class TestCatalanLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = CatalanLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "ca"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "consigueixes" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = [
            "Palau",
            "Música",
            "Catalana",

            # UTF-8 suffix
            "així",
        ]
        expected_stems = ["pal", "music", "catal", "aix"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            El Palau de la Música Catalana és un auditori de música situat al barri de Sant Pere (Sant Pere, Santa
            Caterina i la Ribera) de Barcelona. Va ser projectat per l'arquitecte barceloní Lluís Domènech i Montaner,
            un dels màxims representants del modernisme català.
        """
        expected_sentences = [
            (
                "El Palau de la Música Catalana és un auditori de música situat al barri de Sant Pere (Sant Pere, "
                "Santa Caterina i la Ribera) de Barcelona."
            ),
            (
                "Va ser projectat per l'arquitecte barceloní Lluís Domènech i Montaner, un dels màxims representants "
                "del modernisme català."
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = (
            "Després del Brexit, es confirma el trasllat de l'Agència Europea de Medicaments i l'Autoritat Bancària "
            "Europea a Amsterdam i París, respectivament."
        )
        expected_words = [
            "després", "del", "brexit", "es", "confirma", "el", "trasllat", "de", "l'agència", "europea", "de",
            "medicaments", "i", "l'autoritat", "bancària", "europea", "a", "amsterdam", "i", "parís", "respectivament",
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
