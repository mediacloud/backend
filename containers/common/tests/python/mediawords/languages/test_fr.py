from unittest import TestCase

from mediawords.languages.fr import FrenchLanguage


# noinspection SpellCheckingInspection
class TestFrenchLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = FrenchLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "fr"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "dans" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["conduisant", "l'espèce", "apprivoisements"]
        expected_stems = ["conduis", "l'espec", "apprivois"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            Jusqu'aux années 2000, l'origine du cheval domestique est étudiée par synapomorphie, en comparant des
            fossiles et squelettes. Les progrès de la génétique permettent désormais une autre approche, le nombre de
            gènes entre les différentes espèces d'équidés étant variable. La différentiation entre les espèces d’Equus
            laisse à penser que cette domestication est récente, et qu'elle concerne un nombre restreint d'étalons pour
            un grand nombre de juments, capturées à l'état sauvage afin de repeupler les élevages domestiques. Peu à
            peu, l'élevage sélectif entraîne une distinction des chevaux selon leur usage, la traction ou la selle, et
            un accroissement de la variété des robes de leurs robes.
        """
        expected_sentences = [
            (
                "Jusqu'aux années 2000, l'origine du cheval domestique est étudiée par synapomorphie, en comparant des "
                "fossiles et squelettes."
            ),
            (
                "Les progrès de la génétique permettent désormais une autre approche, le nombre de gènes entre les "
                "différentes espèces d'équidés étant variable."
            ),
            (
                "La différentiation entre les espèces d’Equus laisse à penser que cette domestication est récente, et "
                "qu'elle concerne un nombre restreint d'étalons pour un grand nombre de juments, capturées à l'état "
                "sauvage afin de repeupler les élevages domestiques."
            ),
            (
                "Peu à peu, l'élevage sélectif entraîne une distinction des chevaux selon leur usage, la traction ou "
                "la selle, et un accroissement de la variété des robes de leurs robes."
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_non_breakable_abbreviation(self):
        """Non-breakable abbreviation (e.g. "4500 av. J.-C.")."""
        input_text = """
            La première preuve archéologique date de 4500 av. J.-C. dans les steppes au Nord du Kazakhstan, parmi la
            culture Botaï. D'autres éléments en évoquent indépendamment dans la péninsule ibérique, et peut-être la
            péninsule arabique. Les recherches précédentes se sont longtemps focalisées sur les steppes d'Asie centrale,
            vers 4000 à 3500 av. J.-C..
        """
        expected_sentences = [
            (
                "La première preuve archéologique date de 4500 av. J.-C. dans les steppes au Nord du Kazakhstan, parmi "
                "la culture Botaï."
            ),
            (
                "D'autres éléments en évoquent indépendamment dans la péninsule ibérique, et peut-être la péninsule "
                "arabique."
            ),
            (
                "Les recherches précédentes se sont longtemps focalisées sur les steppes d'Asie centrale, vers 4000 à "
                "3500 av. J.-C.."
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = (
            "Les recherches précédentes se sont longtemps focalisées sur les steppes d'Asie centrale, vers 4000 à "
            "3500 av. J.-C.."
        )
        expected_words = [
            "les", "recherches", "précédentes", "se", "sont", "longtemps", "focalisées", "sur", "les", "steppes",
            "d'asie", "centrale", "vers", "4000", "à", "3500", "av", "j", "c",
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
