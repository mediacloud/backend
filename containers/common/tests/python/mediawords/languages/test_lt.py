from unittest import TestCase

from mediawords.languages.lt import LithuanianLanguage


# noinspection SpellCheckingInspection
class TestLithuanianLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = LithuanianLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "lt"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "buvo" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = [
            "Niekada",
            "myliu",

            # UTF-8 suffix
            "grožį",
        ]
        expected_stems = ["niekad", "myl", "grož"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            Kinijos civilizacija yra viena seniausių pasaulyje. Kinijos istorija pasižymi gausa įvairių rašytinių
            šaltinių, kurie, kartu su archeologiniais duomenimis, leidžia rekonstruoti politinį Kinijos gyvenimą ir
            socialius procesus pradedant gilia senove. Politiškai Kinija per keletą tūkstantmečių keletą kartų perėjo
            per besikartojančius politinės vienybės ir susiskaidymo ciklus. Kinijos teritoriją reguliariai užkariaudavo
            ateiviai iš išorės, tačiau daugelis jų anksčiau ar vėliau buvo asimiliuojami į kinų etnosą.
        """
        expected_sentences = [
            'Kinijos civilizacija yra viena seniausių pasaulyje.',
            (
                'Kinijos istorija pasižymi gausa įvairių rašytinių šaltinių, kurie, kartu su archeologiniais '
                'duomenimis, leidžia rekonstruoti politinį Kinijos gyvenimą ir socialius procesus pradedant gilia '
                'senove.'
            ),
            (
                'Politiškai Kinija per keletą tūkstantmečių keletą kartų perėjo per besikartojančius politinės '
                'vienybės ir susiskaidymo ciklus.'
            ),
            (
                'Kinijos teritoriją reguliariai užkariaudavo ateiviai iš išorės, tačiau daugelis jų anksčiau ar vėliau '
                'buvo asimiliuojami į kinų etnosą.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_abbreviated_name(self):
        """Abbreviated name ("S. Daukanto")."""
        input_text = """
            Lenkimų senosios kapinės, Pušų kapai, Maro kapeliai, Kapeliai (saugotinas kultūros paveldo objektas) –
            neveikiančios kapinės vakariniame Skuodo rajono savivaldybės teritorijos pakraštyje, 1,9 km į rytus nuo
            Šventosios upės ir Latvijos sienos, Lenkimų miestelio (Lenkimų seniūnija) pietvakariniame pakraštyje, kelio
            Skuodas–Kretinga (S. Daukanto gatvės) dešinėje pusėje. Įrengtos šiaurės – pietų kryptimi pailgoje kalvelėje,
            apjuostos statinių tvoros, kurios rytinėje pusėje įrengti varteliai. Kapinių pakraščiuose auga kelios pušys,
            o centrinėje dalyje – vietinės reikšmės gamtos paminklu laikoma Kapų pušis. Į pietus nuo jos stovi
            monumentalus kryžius ir pora koplytėlių. Pietinėje dalyje išliko pora betoninių antkapių, ženklinančių
            buvusius kapus. Priešais kapines pakelėje pastatytas stogastulpio tipo anotacinis ženklas su įrašu „PUŠŲ
            KAPAI“. Teritorijos plotas – 0,06 ha.
        """
        expected_sentences = [
            (
                'Lenkimų senosios kapinės, Pušų kapai, Maro kapeliai, Kapeliai (saugotinas kultūros paveldo '
                'objektas) – neveikiančios kapinės vakariniame Skuodo rajono savivaldybės teritorijos pakraštyje, 1,9 '
                'km į rytus nuo Šventosios upės ir Latvijos sienos, Lenkimų miestelio (Lenkimų seniūnija) '
                'pietvakariniame pakraštyje, kelio Skuodas–Kretinga (S. Daukanto gatvės) dešinėje pusėje.'
            ),
            (
                'Įrengtos šiaurės – pietų kryptimi pailgoje kalvelėje, apjuostos statinių tvoros, kurios rytinėje '
                'pusėje įrengti varteliai.'
            ),
            (
                'Kapinių pakraščiuose auga kelios pušys, o centrinėje dalyje – vietinės reikšmės gamtos paminklu '
                'laikoma Kapų pušis.'
            ),
            'Į pietus nuo jos stovi monumentalus kryžius ir pora koplytėlių.',
            'Pietinėje dalyje išliko pora betoninių antkapių, ženklinančių buvusius kapus.',
            'Priešais kapines pakelėje pastatytas stogastulpio tipo anotacinis ženklas su įrašu „PUŠŲ KAPAI“.',
            'Teritorijos plotas – 0,06 ha.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_dates_abbreviations(self):
        """Date ("1338 m. rugpjūčio 14 d."), abbreviation ("vok.")."""
        input_text = """
            Galialaukių mūšis – 1338 m. rugpjūčio 14 d. netoli Ragainės pilies vykusios kautynės tarp LDK ir Vokiečių
            ordino kariuomenių. Ordino maršalo Heinricho Dusmerio vadovaujami kryžiuočiai Galialaukių vietovėje (vok.
            Galelouken, Galelauken) pastojo kelią lietuviams, grįžtantiems į Lietuvą po trijų dienų niokojamo žygio į
            Prūsiją, surengto greičiausiai keršijant ordinui už Bajerburgo pilies pastatymą bei Medininkų valsčiaus
            nuniokojimą.
        """
        expected_sentences = [
            (
                'Galialaukių mūšis – 1338 m. rugpjūčio 14 d. netoli Ragainės pilies vykusios kautynės tarp LDK ir '
                'Vokiečių ordino kariuomenių.'
            ),
            (
                'Ordino maršalo Heinricho Dusmerio vadovaujami kryžiuočiai Galialaukių vietovėje (vok. Galelouken, '
                'Galelauken) pastojo kelią lietuviams, grįžtantiems į Lietuvą po trijų dienų niokojamo žygio į '
                'Prūsiją, surengto greičiausiai keršijant ordinui už Bajerburgo pilies pastatymą bei Medininkų '
                'valsčiaus nuniokojimą.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_dates_abbreviations_2(self):
        """Dates ("II tūkst. pr. m. e." and others), abbreviation ("kin.")."""
        input_text = """
            Daugiausia žinių yra išlikę apie Geltonosios upės vidurupio (taip vadinamos Vidurio lygumos) arealo raidą,
            kur jau II tūkst. pr. m. e. viduryje į valdžią atėjo pusiau legendinė Šia dinastija, kurią pakeitė Šangų
            dinastija. XI a. pr. m. e. čia įsigalėjo Džou dinastija. Tuo metu Vidurio lygumos karalystė pradėta vadinti
            tiesiog "Vidurio karalyste" (kin. Zhongguo), kas ir davė pavadinimą visai Kinijai. Valdant Džou dinastijai,
            jos monarchų simbolinis autoritetas išplito po didžiulę teritoriją. Nors atskiros Kinijos valstybės kovojo
            tarpusavyje, kultūriniai mainai intensyvėjo, kas ilgainiui vedė į politinį suvienijimą III a. pr. m. e.
        """
        expected_sentences = [
            (
                'Daugiausia žinių yra išlikę apie Geltonosios upės vidurupio (taip vadinamos Vidurio lygumos) arealo '
                'raidą, kur jau II tūkst. pr. m. e. viduryje į valdžią atėjo pusiau legendinė Šia dinastija, kurią '
                'pakeitė Šangų dinastija.'
            ),
            'XI a. pr. m. e. čia įsigalėjo Džou dinastija.',
            (
                'Tuo metu Vidurio lygumos karalystė pradėta vadinti tiesiog "Vidurio karalyste" (kin. Zhongguo), kas '
                'ir davė pavadinimą visai Kinijai.'
            ),
            'Valdant Džou dinastijai, jos monarchų simbolinis autoritetas išplito po didžiulę teritoriją.',
            (
                'Nors atskiros Kinijos valstybės kovojo tarpusavyje, kultūriniai mainai intensyvėjo, kas ilgainiui '
                'vedė į politinį suvienijimą III a. pr. m. e.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = 'Valdant Džou dinastijai, jos monarchų simbolinis autoritetas išplito po didžiulę teritoriją.'
        expected_words = [
            'valdant', 'džou', 'dinastijai', 'jos', 'monarchų', 'simbolinis', 'autoritetas', 'išplito', 'po',
            'didžiulę', 'teritoriją',
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
