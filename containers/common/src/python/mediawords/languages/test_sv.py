from unittest import TestCase

from mediawords.languages.sv import SwedishLanguage


# noinspection SpellCheckingInspection
class TestSwedishLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = SwedishLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "sv"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "vår" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["processer", "Tillgängliga"]
        expected_stems = ["process", "tillgäng"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            I sin ungdom studerade Lutosławski piano och komposition i Warszawa. Hans tidiga verk var påverkade av polsk
            folkmusik. Han började utveckla sin karaktäristiska kompositionsteknik i slutet av 1950-talet. Musiken från
            den här perioden och framåt inbegriper en egen metod att bygga harmonier av mindre grupper av intervall. Den
            använder också slumpmässiga processer i vilka stämmornas rytmiska samordning inbegriper ett moment av
            slumpmässighet. Hans kompositioner omfattar fyra symfonier, en konsert för orkester, flera konserter för
            solo och orkester och orkestrala sångcykler. Efter andra världskriget bannlyste de stalinistiska makthavarna
            hans kompositioner då de uppfattades som formalistiska och därmed tillgängliga bara för en insatt elit,
            medan Lutosławski själv alltid motsatte sig den socialistiska realismen. Under 1980-talet utnyttjade
            Lutosławski sin internationella ryktbarhet för att stödja Solidaritet.
        """
        expected_sentences = [
            'I sin ungdom studerade Lutosławski piano och komposition i Warszawa.',
            'Hans tidiga verk var påverkade av polsk folkmusik.',
            'Han började utveckla sin karaktäristiska kompositionsteknik i slutet av 1950-talet.',
            (
                'Musiken från den här perioden och framåt inbegriper en egen metod att bygga harmonier av mindre '
                'grupper av intervall.'
            ),
            (
                'Den använder också slumpmässiga processer i vilka stämmornas rytmiska samordning inbegriper ett '
                'moment av slumpmässighet.'
            ),
            (
                'Hans kompositioner omfattar fyra symfonier, en konsert för orkester, flera konserter för solo och '
                'orkester och orkestrala sångcykler.'
            ),
            (
                'Efter andra världskriget bannlyste de stalinistiska makthavarna hans kompositioner då de uppfattades '
                'som formalistiska och därmed tillgängliga bara för en insatt elit, medan Lutosławski själv alltid '
                'motsatte sig den socialistiska realismen.'
            ),
            'Under 1980-talet utnyttjade Lutosławski sin internationella ryktbarhet för att stödja Solidaritet.'
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_abbreviations(self):
        """Abbreviations ("f. Kr.", "a.C.n.", "A. D.")."""
        input_text = """
            Efter Kristus (förkortat e. Kr.) är den i modern svenska vanligtvis använda benämningen på Anno Domini
            (latin för Herrens år), utförligare Anno Domini Nostri Iesu Christi (i vår Herres Jesu Kristi år), oftast
            förkortat A. D. eller AD, vilket har varit den dominerande tideräkningsnumreringen av årtal i modern tid i
            Europa. Årtalssystemet används fortfarande i hela västvärlden och i vetenskapliga och kommersiella
            sammanhang även i resten av världen, när man anser att "efter" behöver förtydligas. Efter den Gregorianska
            kalenderns införande har bruket att sätta ut AD vid årtalet stadigt minskat.
        """
        expected_sentences = [
            (
                'Efter Kristus (förkortat e. Kr.) är den i modern svenska vanligtvis använda benämningen på Anno '
                'Domini (latin för Herrens år), utförligare Anno Domini Nostri Iesu Christi (i vår Herres Jesu Kristi '
                'år), oftast förkortat A. D. eller AD, vilket har varit den dominerande tideräkningsnumreringen av '
                'årtal i modern tid i Europa.'
            ),
            (
                'Årtalssystemet används fortfarande i hela västvärlden och i vetenskapliga och kommersiella sammanhang '
                'även i resten av världen, när man anser att "efter" behöver förtydligas.'
            ),
            'Efter den Gregorianska kalenderns införande har bruket att sätta ut AD vid årtalet stadigt minskat.'
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = 'I sin ungdom studerade Lutosławski piano och komposition i Warszawa.'
        expected_words = [
            'i', 'sin', 'ungdom', 'studerade', 'lutosławski', 'piano', 'och', 'komposition', 'i', 'warszawa',
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
