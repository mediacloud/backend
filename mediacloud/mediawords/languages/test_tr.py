from unittest import TestCase

from mediawords.languages.tr import TurkishLanguage


# noinspection SpellCheckingInspection
class TestTurkishLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = TurkishLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "tr"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "aslında" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["çevrimiçi", "Sahipliği"]
        expected_stems = ["çevrimiç", "sahiplik"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences(self):
        input_text = """
            Google, (NASDAQ: GOOG), internet araması, çevrimiçi bilgi dağıtımı, reklam teknolojileri ve arama motorları
            için yatırımlar yapan çok uluslu Amerikan anonim şirketidir. İnternet tabanlı hizmet ve ürünler geliştirir,
            ek olarak bunlara ev sahipliği yapar. Kârının büyük kısmını AdWords programı aracılığıyla reklamlardan elde
            etmektedir. Şirket, Larry Page ve Sergey Brin tarafından, Stanford Üniversitesi'nde doktora öğrencisi
            oldukları sırada kurulmuştur. İkili, sık sık "Google Guys" olarak anılmaktadır. Google, ilk olarak, 4 Eylül
            1998 tarihinde özel bir şirket olarak kuruldu ve 19 Ağustos 2004 tarihinde halka arz edildi. Halka arzın
            gerçekleştiği dönemde, Larry Page, Sergey Brin ve Eric Schmidt, takip eden yirmi yıl boyunca, yani 2024
            yılına kadar Google'da birlikte çalışmak üzere anlaştılar. Kuruluşundan bu yana misyonu "dünyadaki bilgiyi
            organize etmek ve bunu evrensel olarak erişilebilir ve kullanılabilir hale getirmek"tir. Gayri resmi sloganı
            ise, Google mühendisi Amit Patel tarafından bulunan ve Paul Buchheit tarafından desteklenen
            "Don't be evil"dir.
        """
        expected_sentences = [
            (
                'Google, (NASDAQ: GOOG), internet araması, çevrimiçi bilgi dağıtımı, reklam teknolojileri ve arama '
                'motorları için yatırımlar yapan çok uluslu Amerikan anonim şirketidir.'
            ),
            'İnternet tabanlı hizmet ve ürünler geliştirir, ek olarak bunlara ev sahipliği yapar.',
            'Kârının büyük kısmını AdWords programı aracılığıyla reklamlardan elde etmektedir.',
            (
                'Şirket, Larry Page ve Sergey Brin tarafından, Stanford Üniversitesi\'nde doktora öğrencisi oldukları '
                'sırada kurulmuştur.'
            ),
            'İkili, sık sık "Google Guys" olarak anılmaktadır.',
            (
                'Google, ilk olarak, 4 Eylül 1998 tarihinde özel bir şirket olarak kuruldu ve 19 Ağustos 2004 '
                'tarihinde halka arz edildi.'
            ),
            (
                'Halka arzın gerçekleştiği dönemde, Larry Page, Sergey Brin ve Eric Schmidt, takip eden yirmi yıl '
                'boyunca, yani 2024 yılına kadar Google\'da birlikte çalışmak üzere anlaştılar.'
            ),
            (
                'Kuruluşundan bu yana misyonu "dünyadaki bilgiyi organize etmek ve bunu evrensel olarak erişilebilir '
                've kullanılabilir hale getirmek"tir.'
            ),
            (
                'Gayri resmi sloganı ise, Google mühendisi Amit Patel tarafından bulunan ve Paul Buchheit tarafından '
                'desteklenen "Don\'t be evil"dir.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_urls_abbreviation(self):
        """URLs ("google.com", "google.co.in", ...), abbreviation ("vb.")."""
        input_text = """
            Alexa, internette en çok ziyaret edilen web sitesi olarak ABD odaklı "google.com"'u listelemektedir,
            YouTube, Blogger, Orkut gibi Google'a ait diğer siteler ve çok sayıda uluslararası Google sitesi
            (google.co.in, google.co.uk vb.) ise en çok ziyaret edilen siteler arasında ilk yüz içinde yer almaktadır.
            Ek olarak şirket, BrandZ marka değeri veritabanı listesinde ikinci sırada yer almaktadır. Buna karşın
            Google, gizlilik, telif hakkı ve sansür gibi konularda eleştiriler almaktadır.
        """
        expected_sentences = [
            (
                'Alexa, internette en çok ziyaret edilen web sitesi olarak ABD odaklı "google.com"\'u listelemektedir, '
                'YouTube, Blogger, Orkut gibi Google\'a ait diğer siteler ve çok sayıda uluslararası Google sitesi '
                '(google.co.in, google.co.uk vb.) ise en çok ziyaret edilen siteler arasında ilk yüz içinde yer '
                'almaktadır.'
            ),
            'Ek olarak şirket, BrandZ marka değeri veritabanı listesinde ikinci sırada yer almaktadır.',
            'Buna karşın Google, gizlilik, telif hakkı ve sansür gibi konularda eleştiriler almaktadır.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_period_in_number(self):
        """Period in the middle of the number"""
        input_text = """
            Bir yıl önceki rakam olan 931 milyon tekil ziyaretçi sayısındaki yüzde 8.4'lük bir artışla, 2001 Mayıs
            ayında; Google'nin tekil ziyaretçi sayısı ilk kez 1 milyarı buldu.
        """
        expected_sentences = [
            (
                "Bir yıl önceki rakam olan 931 milyon tekil ziyaretçi sayısındaki yüzde 8.4'lük bir artışla, 2001 "
                "Mayıs ayında; Google'nin tekil ziyaretçi sayısı ilk kez 1 milyarı buldu."
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = 'İkili, sık sık "Google Guys" olarak anılmaktadır.'
        expected_words = ['i̇kili', 'sık', 'sık', 'google', 'guys', 'olarak', 'anılmaktadır']
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
