from unittest import TestCase

from mediawords.languages.hu import HungarianLanguage


# noinspection SpellCheckingInspection
class TestHungarianLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = HungarianLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "hu"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "cikk" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["megfelelően", "matematikát", "tanult"]
        expected_stems = ["megfelelő", "matemat", "tanul"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            Ifjúkoráról keveset tudni, a kor igényeinek megfelelően valószínűleg matematikát és hajózást tanult. Miután
            Kolumbusz Kristóf spanyol zászló alatt hajózva felfedezte Amerikát 1492-ben, Portugália joggal érezhette,
            hogy lépéshátrányba került nagy riválisával szemben. Öt esztendővel később a lisszaboni kikötőből kifutott
            az első olyan flotta, amelyik Indiába akart eljutni azon az útvonalon, amelyet Bartolomeu Dias megnyitott a
            portugálok számára.
        """
        expected_sentences = [
            'Ifjúkoráról keveset tudni, a kor igényeinek megfelelően valószínűleg matematikát és hajózást tanult.',
            (
                'Miután Kolumbusz Kristóf spanyol zászló alatt hajózva felfedezte Amerikát 1492-ben, Portugália joggal '
                'érezhette, hogy lépéshátrányba került nagy riválisával szemben.'
            ),
            (
                'Öt esztendővel később a lisszaboni kikötőből kifutott az első olyan flotta, amelyik Indiába akart '
                'eljutni azon az útvonalon, amelyet Bartolomeu Dias megnyitott a portugálok számára.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_dates_abbreviations_brackets(self):
        """Dates, abbreviations ("1845. febr. 8. Edgeworthstown, † 1926. febr. 13. Oxford"), brackets."""
        input_text = """
            Edgeworth, Francis Ysidro (1845. febr. 8. Edgeworthstown, † 1926. febr. 13. Oxford): ír közgazdász és
            statisztikus, aki a közgazdaságtudományban maradandót alkotott a közömbösségi görbék rendszerének
            megalkotásával. Nevéhez fűződik még a szerződési görbe és az úgynevezett Edgeworth-doboz vagy
            Edgeworth-négyszög kidolgozása. ( Az utóbbit Pareto-féle box-diagrammnak is nevezik.) Mint statisztikus, a
            korrelációszámítást fejlesztette tovább, s az index-számításban a bázis és a tárgyidőszak fogyasztási
            szerkezettel számított indexek számtani átlagaként képzett indexet róla nevezik Edgeworth-indexnek.
        """
        expected_sentences = [
            (
                'Edgeworth, Francis Ysidro (1845. febr. 8. Edgeworthstown, † 1926. febr. 13. Oxford): ír közgazdász és '
                'statisztikus, aki a közgazdaságtudományban maradandót alkotott a közömbösségi görbék rendszerének '
                'megalkotásával.'
            ),
            (
                'Nevéhez fűződik még a szerződési görbe és az úgynevezett Edgeworth-doboz vagy Edgeworth-négyszög '
                'kidolgozása. ( Az utóbbit Pareto-féle box-diagrammnak is nevezik.)'
            ),
            (
                'Mint statisztikus, a korrelációszámítást fejlesztette tovább, s az index-számításban a bázis és a '
                'tárgyidőszak fogyasztási szerkezettel számított indexek számtani átlagaként képzett indexet róla '
                'nevezik Edgeworth-indexnek.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_dates_abbreviations_brackets_2(self):
        """Abbreviation ("Dr."), date ("Komárom, 1825. február 18. – Budapest, Erzsébetváros, 1904. május 5.")."""
        input_text = """
            Dr. Ásvay Jókai Móric (Komárom, 1825. február 18. – Budapest, Erzsébetváros, 1904. május 5.) regényíró, a
            „nagy magyar mesemondó”, országgyűlési képviselő, főrendiházi tag, a Magyar Tudományos Akadémia
            igazgató-tanácsának tagja, a Szent István-rend lovagja, a Kisfaludy Társaság tagja, a Petőfi Társaság
            elnöke, a Dugonics Társaság tiszteletbeli tagja.
        """
        expected_sentences = [
            (
                "Dr. Ásvay Jókai Móric (Komárom, 1825. február 18. – Budapest, Erzsébetváros, 1904. május 5.) "
                "regényíró, a „nagy magyar mesemondó”, országgyűlési képviselő, főrendiházi tag, a Magyar Tudományos "
                "Akadémia igazgató-tanácsának tagja, a Szent István-rend lovagja, a Kisfaludy Társaság tagja, a Petőfi "
                "Társaság elnöke, a Dugonics Társaság tiszteletbeli tagja."
            )
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_dates_abbreviations_dates(self):
        """Dates."""
        input_text = """
            Hszi Csin-ping (kínaiul: 习近平, pinjin, hangsúlyjelekkel: Xí Jìnpíng) (Fuping, Shaanxi tartomány, 1953.
            június 1.) kínai politikus, 2008. március 15. óta a Kínai Népköztársaság alelnöke, 2012. november 15. óta a
            KKP KB Politikai Bizottsága Állandó Bizottságának, az ország de facto legfelső hatalmi grémiumának, valamint
            a KKP Központi Katonai Bizottságának az elnöke. A várakozások szerint 2013 márciusától ő lesz a Kínai
            Népköztársaság elnöke. 2010 óta számít az ország kijelölt következő vezetőjének.
        """
        expected_sentences = [
            (
                'Hszi Csin-ping (kínaiul: 习近平, pinjin, hangsúlyjelekkel: Xí Jìnpíng) (Fuping, Shaanxi tartomány, '
                '1953. június 1.) kínai politikus, 2008. március 15. óta a Kínai Népköztársaság alelnöke, 2012. '
                'november 15. óta a KKP KB Politikai Bizottsága Állandó Bizottságának, az ország de facto legfelső '
                'hatalmi grémiumának, valamint a KKP Központi Katonai Bizottságának az elnöke.'
            ),
            'A várakozások szerint 2013 márciusától ő lesz a Kínai Népköztársaság elnöke.',
            '2010 óta számít az ország kijelölt következő vezetőjének.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_dates_period_in_middle_of_number(self):
        """Period in the middle of number."""
        input_text = """
            A döntőben hibátlan gyakorlatára 16.066-os pontszámot kapott, akárcsak Louis Smith; a holtversenyt a
            gyakorlatának magasabb kivitelezési pontszáma döntötte el Berki javára, aki megnyerte első olimpiai
            aranyérmét.
        """
        expected_sentences = [
            (
                'A döntőben hibátlan gyakorlatára 16.066-os pontszámot kapott, akárcsak Louis Smith; a holtversenyt a '
                'gyakorlatának magasabb kivitelezési pontszáma döntötte el Berki javára, aki megnyerte első olimpiai '
                'aranyérmét.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_dates_numbers(self):
        """Numbers."""
        input_text = """
            2002-ben a KSI sportolójaként a junior Európa-bajnokságon lólengésben második, csapatban 11. volt. A felnőtt
            mesterfokú magyar bajnokságon megnyerte a lólengést. A debreceni szerenkénti világbajnokságon kilencedik
            lett. 2004-ben a vk-sorozatban Párizsban 13., Cottbusban hatodik volt. A következő évben Rio de Janeiróban
            vk-versenyt nyert. A ljubljanai Eb-n csapatban 10., lólengésben bronzérmes lett. A világkupában Glasgowban
            ötödik, Gentben negyedik, Stuttgartban harmadik lett. A birminghami világkupa-döntőn hatodik helyezést ért
            el.
        """
        expected_sentences = [
            '2002-ben a KSI sportolójaként a junior Európa-bajnokságon lólengésben második, csapatban 11. volt.',
            'A felnőtt mesterfokú magyar bajnokságon megnyerte a lólengést.',
            'A debreceni szerenkénti világbajnokságon kilencedik lett.',
            '2004-ben a vk-sorozatban Párizsban 13., Cottbusban hatodik volt.',
            'A következő évben Rio de Janeiróban vk-versenyt nyert.',
            'A ljubljanai Eb-n csapatban 10., lólengésben bronzérmes lett.',
            'A világkupában Glasgowban ötödik, Gentben negyedik, Stuttgartban harmadik lett.',
            'A birminghami világkupa-döntőn hatodik helyezést ért el.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_dates_website_name(self):
        """Website name."""
        input_text = "Már előtte a Blikk.hu-n is megnéztem a cikket. Tetszenek a képek, nagyon boldog vagyok."
        expected_sentences = [
            'Már előtte a Blikk.hu-n is megnéztem a cikket.',
            'Tetszenek a képek, nagyon boldog vagyok.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_dates_name_abbreviation(self):
        """Name abbreviation."""
        input_text = """
            Nagy hatással volt rá W.H. Auden, aki többek közt első operájának, a Paul Bunyannak a szövegkönyvét írta.
        """
        expected_sentences = [
            'Nagy hatással volt rá W.H. Auden, aki többek közt első operájának, a Paul Bunyannak a szövegkönyvét írta.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_dates_roman_numeral(self):
        """Roman numeral."""
        input_text = "1953-ban II. Erzsébet koronázására írta a Gloriana című operáját."
        expected_sentences = ['1953-ban II. Erzsébet koronázására írta a Gloriana című operáját.']
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = 'Tetszenek a képek, nagyon boldog vagyok.'
        expected_words = ['tetszenek', 'a', 'képek', 'nagyon', 'boldog', 'vagyok']
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
