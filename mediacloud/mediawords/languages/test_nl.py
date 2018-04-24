from unittest import TestCase

from mediawords.languages.nl import DutchLanguage


# noinspection SpellCheckingInspection
class TestDutchLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = DutchLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "nl"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "geweest" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["rationele", "Organismen"]
        expected_stems = ["rationel", "organism"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            Onder neogotiek wordt een 19e-eeuwse stroming in de architectuur verstaan die zich geheel heeft laten
            inspireren door de middeleeuwse gotiek. De neogotiek ontstond in Engeland en was een reactie op de strakke,
            koele vormen van het classicisme met haar uitgesproken rationele karakter. De neogotiek vond haar oorsprong
            in de romantiek met haar belangstelling voor de middeleeuwen.
        """
        expected_sentences = [
            (
                'Onder neogotiek wordt een 19e-eeuwse stroming in de architectuur verstaan die zich geheel heeft laten '
                'inspireren door de middeleeuwse gotiek.'
            ),
            (
                'De neogotiek ontstond in Engeland en was een reactie op de strakke, koele vormen van het classicisme '
                'met haar uitgesproken rationele karakter.'
            ),
            'De neogotiek vond haar oorsprong in de romantiek met haar belangstelling voor de middeleeuwen.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_period_in_number(self):
        """Period in the middle of the number."""
        input_text = """
            De vulkaan, meestal gewoon Tongariro genoemd, heeft een hoogte van 1978 meter. Ruim 260.000 jaar geleden
            barstte de vulkaan voor het eerst uit. De Tongariro bestaat uit ten minste twaalf toppen. De Ngarahoe, vaak
            gezien als een aparte berg, is eigenlijk een bergtop met krater van de Tongariro. Het is de meest actieve
            vulkaan in het gebied. Sinds 1839 hebben er meer dan zeventig uitbarstingen plaatsgevonden. De meest recente
            uitbarsting was op 21 november 2012 om 13:22 uur, waarbij een aswolk tot 4213 m is gerapporteerd. Dit was
            slechts 3,5 maand na de voorlaatste uitbarsting op 6 augustus 2012.
        """
        expected_sentences = [
            'De vulkaan, meestal gewoon Tongariro genoemd, heeft een hoogte van 1978 meter.',
            'Ruim 260.000 jaar geleden barstte de vulkaan voor het eerst uit.',
            'De Tongariro bestaat uit ten minste twaalf toppen.',
            'De Ngarahoe, vaak gezien als een aparte berg, is eigenlijk een bergtop met krater van de Tongariro.',
            'Het is de meest actieve vulkaan in het gebied.',
            'Sinds 1839 hebben er meer dan zeventig uitbarstingen plaatsgevonden.',
            (
                'De meest recente uitbarsting was op 21 november 2012 om 13:22 uur, waarbij een aswolk tot 4213 m is '
                'gerapporteerd.'
            ),
            'Dit was slechts 3,5 maand na de voorlaatste uitbarsting op 6 augustus 2012.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_abbreviation(self):
        """Abbreviation ("m.a.w")."""
        input_text = """
            Aeroob betekent dat een organisme alleen met zuurstof kan gedijen, m.a.w dat het zuurstof gebruikt. Dit in
            tegenstelling tot anaerobe organismen, die geen zuurstof nodig hebben.
        """
        expected_sentences = [
            'Aeroob betekent dat een organisme alleen met zuurstof kan gedijen, m.a.w dat het zuurstof gebruikt.',
            'Dit in tegenstelling tot anaerobe organismen, die geen zuurstof nodig hebben.'
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = 'Ruim 260.000 jaar geleden barstte de vulkaan voor het eerst uit.'
        expected_words = [
            'ruim', '260.000', 'jaar', 'geleden', 'barstte', 'de', 'vulkaan', 'voor', 'het', 'eerst', 'uit',
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
