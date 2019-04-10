#!/usr/bin/env py.test

from unittest import TestCase

from mediawords.languages.en import EnglishLanguage


# noinspection SpellCheckingInspection
class TestEnglishLanguage(TestCase):

    def setUp(self):
        self.__tokenizer = EnglishLanguage()

    def test_language_code(self):
        assert self.__tokenizer.language_code() == "en"

    def test_sample_sentence(self):
        assert len(self.__tokenizer.sample_sentence())

    def test_stop_words_map(self):
        stop_words = self.__tokenizer.stop_words_map()
        assert "the" in stop_words
        assert "not_a_stopword" not in stop_words

    def test_stem(self):
        input_words = ["stemming"]
        expected_stems = ["stem"]
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_stem_apostrophe_normal(self):
        """Stemming with normal apostrophe."""
        input_words = ["Katz's", "Delicatessen"]
        expected_stems = ['katz', 'delicatessen']
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_stem_apostrophe_right_single_quotation_mark(self):
        """Stemming with right single quotation mark."""
        input_words = ["it’s", "toasted"]
        expected_stems = ['it', 'toast']
        actual_stems = self.__tokenizer.stem_words(input_words)
        assert expected_stems == actual_stems

    def test_split_text_to_sentences_period_in_number(self):
        """Period in number."""
        input_text = "Sentence contain version 2.0 of the text. Foo."
        expected_sentences = [
            'Sentence contain version 2.0 of the text.',
            'Foo.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_may_ending(self):
        """'May' ending."""
        input_text = "Sentence ends in May. This is the next sentence. Foo."
        expected_sentences = [
            'Sentence ends in May.',
            'This is the next sentence.',
            'Foo.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_punctuation(self):
        """'May' ending."""
        input_text = "Leave the city! [Mega No!], l."
        expected_sentences = [
            'Leave the city!',
            '[Mega No!], l.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_unicode(self):
        """Basic Unicode."""
        input_text = "Non Mega Não! [Mega No!], l."
        expected_sentences = [
            'Non Mega Não!',
            '[Mega No!], l.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_quotation(self):
        """Basic Unicode (with fancy Unicode quotation marks)."""
        input_text = """
            Perhaps that’s the best thing the Nobel Committee did by awarding this year’s literature prize to a
            non-dissident, someone whom Peter Englund of the Swedish Academy said was “more a critic of the system,
            sitting within the system.” They’ve given him a chance to bust out.
        """
        expected_sentences = [
            (
                'Perhaps that’s the best thing the Nobel Committee did by awarding this year’s literature prize to a '
                'non-dissident, someone whom Peter Englund of the Swedish Academy said was “more a critic of the '
                'system, sitting within the system.”'
            ),
            'They’ve given him a chance to bust out.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_two_spaces(self):
        """Two spaces in the middle of the sentence."""
        input_text = """
            Although several opposition groups have called for boycotting the coming June 12  presidential election, it
            seems the weight of boycotting groups is much less than four years ago.
        """
        expected_sentences = [
            (
                'Although several opposition groups have called for boycotting the coming June 12 presidential '
                'election, it seems the weight of boycotting groups is much less than four years ago.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_nbsp(self):
        """Non-breaking space."""
        input_text = """
            American Current TV journalists Laura Ling and Euna Lee have been  sentenced  to 12 years of hard labor
            (according to CNN).\u00a0 Jillian York  rounded up blog posts  for Global Voices prior to the journalists'
            sentencing.
        """
        expected_sentences = [
            (
                'American Current TV journalists Laura Ling and Euna Lee have been sentenced to 12 years of hard labor '
                '(according to CNN).'
            ),
            "Jillian York rounded up blog posts for Global Voices prior to the journalists' sentencing.",
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_no_space_after_period(self):
        """No space after a period."""
        input_text = """
            Anger is a waste of energy and what North Korea wants of you.We can and will work together and use our
            minds, to work this through.
        """
        expected_sentences = [
            'Anger is a waste of energy and what North Korea wants of you.',
            'We can and will work together and use our minds, to work this through.',
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_text_to_sentences_unicode_ellipsis(self):
        """Unicode "…"."""
        input_text = """
            One of the most popular Brahmin community, with 28, 726 members, randomly claims: “we r clever &
            hardworking. no one can fool us…” The Brahmans community with 41952 members and the Brahmins of India
            community with 30588 members are also very popular.
        """
        expected_sentences = [
            (
                'One of the most popular Brahmin community, with 28, 726 members, randomly claims: “we r clever & '
                'hardworking. no one can fool us...”'
            ),
            (
                'The Brahmans community with 41952 members and the Brahmins of India community with 30588 members are '
                'also very popular.'
            ),
        ]
        actual_sentences = self.__tokenizer.split_text_to_sentences(input_text)
        assert expected_sentences == actual_sentences

    def test_split_sentence_to_words_normal_apostrophe(self):
        """Normal apostrophe (')."""
        input_sentence = "It's always sunny in Philadelphia."
        expected_words = ["it's", "always", "sunny", "in", "philadelphia"]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words

    def test_split_sentence_to_words_right_single_quotation_mark(self):
        """Right single quotation mark (’), normalized to apostrophe (')."""
        input_sentence = "It’s always sunny in Philadelphia."
        expected_words = ["it's", "always", "sunny", "in", "philadelphia"]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words

    def test_split_sentence_to_words_hyphen_without_split(self):
        """Hyphen without split."""
        input_sentence = "near-total secrecy"
        expected_words = ["near-total", "secrecy"]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words

    def test_split_sentence_to_words_hyphen_without_split_as_dash(self):
        """Hyphen with split (where it's being used as a dash)."""
        input_sentence = "A Pythagorean triple - named for the ancient Greek Pythagoras"
        expected_words = ['a', 'pythagorean', 'triple', 'named', 'for', 'the', 'ancient', 'greek', 'pythagoras']
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words

    def test_split_sentence_to_words_quotes(self):
        """Quotation marks."""
        input_sentence = 'it was in the Guinness Book of World Records as the "most difficult mathematical problem"'
        expected_words = [
            'it', 'was', 'in', 'the', 'guinness', 'book', 'of', 'world', 'records', 'as', 'the', 'most', 'difficult',
            'mathematical', 'problem'
        ]
        actual_words = self.__tokenizer.split_sentence_to_words(input_sentence)
        assert expected_words == actual_words
