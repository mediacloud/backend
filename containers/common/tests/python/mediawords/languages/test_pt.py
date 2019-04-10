#!/usr/bin/env py.test

from unittest import TestCase

from mediawords.languages.pt import PortugueseLanguage


# noinspection SpellCheckingInspection
class TestPortugueseLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = PortugueseLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "pt"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "fãs" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["localizado", "Territórios"]
        expected_stems = ["localiz", "territóri"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            França (em francês: France; AFI: [fʁɑ̃s] ouça), oficialmente República Francesa (em francês: République
            française; [ʁepyblik fʁɑ̃sɛz]) é um país localizado na Europa Ocidental, com várias ilhas e territórios
            ultramarinos noutros continentes. A França Metropolitana se estende do Mediterrâneo ao Canal da Mancha e Mar
            do Norte, e do Rio Reno ao Oceano Atlântico. É muitas vezes referida como L'Hexagone ("O Hexágono") por
            causa da forma geométrica do seu território. A nação é o maior país da União Europeia em área e o terceiro
            maior da Europa, atrás apenas da Rússia e da Ucrânia (incluindo seus territórios extraeuropeus, como a
            Guiana Francesa, o país torna-se maior que a Ucrânia).
        """
        expected_sentences = [
            (
                'França (em francês: France; AFI: [fʁɑ̃s] ouça), oficialmente República Francesa (em francês: '
                'République française; [ʁepyblik fʁɑ̃sɛz]) é um país localizado na Europa Ocidental, com várias ilhas '
                'e territórios ultramarinos noutros continentes.'
            ),
            (
                'A França Metropolitana se estende do Mediterrâneo ao Canal da Mancha e Mar do Norte, e do Rio Reno ao '
                'Oceano Atlântico.'
            ),
            'É muitas vezes referida como L\'Hexagone ("O Hexágono") por causa da forma geométrica do seu território.',
            (
                'A nação é o maior país da União Europeia em área e o terceiro maior da Europa, atrás apenas da Rússia '
                'e da Ucrânia (incluindo seus territórios extraeuropeus, como a Guiana Francesa, o país torna-se maior '
                'que a Ucrânia).'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_period_in_number(self):
        """Period in the middle of the number ("1:26.250")."""
        input_text = """
            O Grande Prêmio da Espanha de 2012 foi a quinta corrida da temporada de 2012 da Fórmula 1. A prova foi
            disputada no dia 13 de maio no Circuito da Catalunha, em Barcelona, com treino de classificação no sábado
            dia 12 de maio. O primeiro treino livre de sexta-feira teve Fernando Alonso como líder, já a segunda sessão
            do mesmo dia foi liderado por Jenson Button. No dia seguinte, a terceira sessão foi dominada por Sebastian
            Vettel. O pole position havia sido Lewis Hamilton, entretanto, o piloto inglês foi punido, sendo excluído do
            classificatório. Quem herdou a pole position foi o venezuelano Pastor Maldonado, tornando-se o primeiro
            venezuelano na história a conquistar a posição de honra na categoria. Maldonado veio a vencer a prova no dia
            seguinte e tornou-se também o primeiro venezuelano na história a vencer uma corrida de Formula 1. O pódio
            foi completado por Fernando Alonso, da Ferrari, e Kimi Raikkonen, da Lotus. A volta mais rápida da corrida
            foi feita pelo francês Romain Grosjean da Lotus com o tempo de 1:26.250.
        """
        expected_sentences = [
            'O Grande Prêmio da Espanha de 2012 foi a quinta corrida da temporada de 2012 da Fórmula 1.',
            (
                'A prova foi disputada no dia 13 de maio no Circuito da Catalunha, em Barcelona, com treino de '
                'classificação no sábado dia 12 de maio.'
            ),
            (
                'O primeiro treino livre de sexta-feira teve Fernando Alonso como líder, já a segunda sessão do mesmo '
                'dia foi liderado por Jenson Button.'
            ),
            'No dia seguinte, a terceira sessão foi dominada por Sebastian Vettel.',
            (
                'O pole position havia sido Lewis Hamilton, entretanto, o piloto inglês foi punido, sendo excluído do '
                'classificatório.'
            ),
            (
                'Quem herdou a pole position foi o venezuelano Pastor Maldonado, tornando-se o primeiro venezuelano na '
                'história a conquistar a posição de honra na categoria.'
            ),
            (
                'Maldonado veio a vencer a prova no dia seguinte e tornou-se também o primeiro venezuelano na história '
                'a vencer uma corrida de Formula 1.'
            ),
            'O pódio foi completado por Fernando Alonso, da Ferrari, e Kimi Raikkonen, da Lotus.',
            'A volta mais rápida da corrida foi feita pelo francês Romain Grosjean da Lotus com o tempo de 1:26.250.'

        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_abbreviation(self):
        """Abbreviation ("a.C.") with an end-of-sentence period."""
        input_text = "Segundo a lenda, Rômulo e Remo fundaram Roma em 753 a.C.."
        expected_sentences = ["Segundo a lenda, Rômulo e Remo fundaram Roma em 753 a.C.."]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_abbreviation_2(self):
        """Abbreviation ("a.C.") with an end-of-sentence period, plus another sentence."""
        input_text = "Segundo a lenda, Rômulo e Remo fundaram Roma em 753 a.C.. This is a test."
        expected_sentences = [
            'Segundo a lenda, Rômulo e Remo fundaram Roma em 753 a.C..',
            'This is a test.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = "Segundo a lenda, Rômulo e Remo fundaram Roma em 753 a.C.."
        expected_words = ["segundo", "a", "lenda", "rômulo", "e", "remo", "fundaram", "roma", "em", "753", "a", "c"]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
