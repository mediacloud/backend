import unittest

from mediawords.test.text import TestCaseTextUtilities


class TestTestCaseTextUtilities(unittest.TestCase, TestCaseTextUtilities):

    def test_assertTextEqual_equal_texts(self):

        got_text = 'Foo bar baz.'
        expected_text = 'Foo bar baz.'

        try:
            self.assertTextEqual(got_text=got_text, expected_text=expected_text)
        except AssertionError as ex:
            raise AssertionError("Texts are equal but method doesn't think so: {}".format(ex))

    def test_assertTextEqual_equal_texts_different_whitespace(self):

        got_text = 'Foo   bar baz. '
        expected_text = ' Foo bar   baz.'

        try:
            self.assertTextEqual(got_text=got_text, expected_text=expected_text)
        except AssertionError as ex:
            raise AssertionError("Texts are equal but method doesn't think so: {}".format(ex))

    def test_assertTextEqual_equal_texts_crlf(self):

        got_text = 'Foo bar\r\nbaz.'
        expected_text = 'Foo bar\nbaz.'

        try:
            self.assertTextEqual(got_text=got_text, expected_text=expected_text)
        except AssertionError as ex:
            raise AssertionError("Texts are equal but method doesn't think so: {}".format(ex))

    def test_assertTextEqual_different_texts(self):

        got_text = '     The quick brown fox jumps over the      dog. The quick brown fox jumps      the lazy dog.'
        expected_text = '    quick brown fox jumps over the lazy dog.           brown fox jumps over the lazy dog.'

        try:
            self.assertTextEqual(got_text=got_text, expected_text=expected_text)
        except AssertionError as ex:
            message = str(ex)
            assert '+ The' in message
            assert '- lazy' in message
            assert '+ quick' in message
            assert '- over' in message
            print(message)

        else:
            raise AssertionError("Texts are not equal but method thinks so.")
