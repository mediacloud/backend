from unittest import TestCase

from mediawords.languages.en import EnglishLanguage
from mediawords.languages.factory import LanguageFactory
from mediawords.languages.lt import LithuanianLanguage


class TestLanguageFactory(TestCase):

    def test_enabled_languages(self):
        assert 'lt' in LanguageFactory.enabled_languages()
        assert 'en' in LanguageFactory.enabled_languages()
        assert 'xx' not in LanguageFactory.enabled_languages()

    def test_language_is_enabled(self):
        assert LanguageFactory.language_is_enabled('en') is True
        assert LanguageFactory.language_is_enabled('lt') is True

        # noinspection PyTypeChecker
        assert LanguageFactory.language_is_enabled(None) is False
        assert LanguageFactory.language_is_enabled('') is False
        assert LanguageFactory.language_is_enabled('xx') is False

    def test_language_for_code(self):
        assert isinstance(LanguageFactory.language_for_code('en'), EnglishLanguage)
        assert isinstance(LanguageFactory.language_for_code('lt'), LithuanianLanguage)

        # noinspection PyTypeChecker
        assert LanguageFactory.language_for_code(None) is None
        assert LanguageFactory.language_for_code('') is None
        assert LanguageFactory.language_for_code('xx') is None

    def test_default_language_code(self):
        assert LanguageFactory.default_language_code() == 'en'

    def test_default_language(self):
        assert isinstance(LanguageFactory.default_language(), EnglishLanguage)
