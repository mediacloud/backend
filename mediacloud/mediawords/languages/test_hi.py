from unittest import TestCase

from mediawords.languages.hi import HindiLanguage


# noinspection SpellCheckingInspection
class TestHindiLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = HindiLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "hi"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "जितना" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["लडका", "लडके", "लडकों"]
        expected_stems = ["लडका", "लडके", "लडकों"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_stem_lucene_set(self):
        """Test dataset taken from Lucene's Hindi stemmer test."""
        words_and_expected_stems = {
            # Masculine noun inflections
            'लडका': 'लडका',
            'लडके': 'लडके',
            'लडकों': 'लडकों',
            'गुरु': 'गुरु',
            'गुरुओं': 'गुरु',
            'दोस्त': 'दोस्त',
            'दोस्तों': 'दोस',

            # Feminine noun inflections
            'लडकी': 'लडकी',
            'लडकियों': 'लडकियों',
            'किताब': 'किताब',
            'किताबें': 'किताबे',
            'किताबों': 'किताबो',
            'आध्यापीका': 'आध्यापीका',
            'आध्यापीकाएं': 'आध्यापीकाएं',
            'आध्यापीकाओं': 'आध्यापीकाओं',

            # Some verb forms
            'खाना': 'खाना',
            'खाता': 'खाता',
            'खाती': 'खाती',
            'खा': 'खा',

            # Exceptions
            'कठिनाइयां': 'कठिना',
            'कठिन': 'कठिन',

            # Empty tokens
            '': '',
        }

        for word, expected_stem in words_and_expected_stems.items():
            actual_stem = self.__tokenizer.stem_words([word])[0]
            assert expected_stem == actual_stem

    def test_split_text_to_sentences(self):
        input_text = """
            अंटार्कटिका (या अन्टार्टिका) पृथ्वी का दक्षिणतम महाद्वीप है, जिसमें दक्षिणी
            ध्रुव अंतर्निहित है। यह दक्षिणी गोलार्द्ध के अंटार्कटिक क्षेत्र और लगभग पूरी तरह
            से अंटार्कटिक वृत के दक्षिण में स्थित है। यह चारों ओर से दक्षिणी महासागर से घिरा
            हुआ है। अपने 140 लाख वर्ग किलोमीटर (54 लाख वर्ग मील) क्षेत्रफल के साथ यह, एशिया,
            अफ्रीका, उत्तरी अमेरिका और दक्षिणी अमेरिका के बाद, पृथ्वी का पांचवां सबसे बड़ा
            महाद्वीप है, अंटार्कटिका का 98% भाग औसतन 1.6 किलोमीटर मोटी बर्फ से आच्छादित है।
        """
        expected_sentences = [
            'अंटार्कटिका (या अन्टार्टिका) पृथ्वी का दक्षिणतम महाद्वीप है, जिसमें दक्षिणी ध्रुव अंतर्निहित है।',
            'यह दक्षिणी गोलार्द्ध के अंटार्कटिक क्षेत्र और लगभग पूरी तरह से अंटार्कटिक वृत के दक्षिण में स्थित है।',
            'यह चारों ओर से दक्षिणी महासागर से घिरा हुआ है।',
            (
                'अपने 140 लाख वर्ग किलोमीटर (54 लाख वर्ग मील) क्षेत्रफल के साथ यह, एशिया, अफ्रीका, '
                'उत्तरी अमेरिका और दक्षिणी अमेरिका के बाद, पृथ्वी का पांचवां सबसे बड़ा महाद्वीप है, अंटार्कटिका '
                'का 98% भाग औसतन 1.6 किलोमीटर मोटी बर्फ से आच्छादित है।'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words(self):
        input_sentence = """
            अंटार्कटिका (या अन्टार्टिका) पृथ्वी का दक्षिणतम महाद्वीप है, जिसमें दक्षिणी ध्रुव अंतर्निहित है।
        """
        expected_words = [
            "अंटार्कटिका", "या", "अन्टार्टिका", "पृथ्वी", "का", "दक्षिणतम", "महाद्वीप", "है", "जिसमें", "दक्षिणी",
            "ध्रुव", "अंतर्निहित", "है",
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
