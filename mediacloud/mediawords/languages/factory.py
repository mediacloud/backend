from typing import Union

from mediawords.languages import AbstractLanguage
from mediawords.languages.ca import CatalanLanguage
from mediawords.languages.da import DanishLanguage
from mediawords.languages.de import GermanLanguage
from mediawords.languages.en import EnglishLanguage
from mediawords.languages.es import SpanishLanguage
from mediawords.languages.fi import FinnishLanguage
from mediawords.languages.fr import FrenchLanguage
from mediawords.languages.ha import HausaLanguage
from mediawords.languages.hi import HindiLanguage
from mediawords.languages.hu import HungarianLanguage
from mediawords.languages.it import ItalianLanguage
from mediawords.languages.ja import JapaneseLanguage
from mediawords.languages.lt import LithuanianLanguage
from mediawords.languages.nl import DutchLanguage
from mediawords.languages.no import NorwegianLanguage
from mediawords.languages.pt import PortugueseLanguage
from mediawords.languages.ro import RomanianLanguage
from mediawords.languages.ru import RussianLanguage
from mediawords.languages.sv import SwedishLanguage
from mediawords.languages.tr import TurkishLanguage
from mediawords.languages.zh import ChineseLanguage
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class LanguageFactory(object):
    """Language instance factory."""

    # Supported + enabled language codes and their corresponding classes
    __ENABLED_LANGUAGES = {
        CatalanLanguage.language_code(): CatalanLanguage,
        ChineseLanguage.language_code(): ChineseLanguage,
        DanishLanguage.language_code(): DanishLanguage,
        DutchLanguage.language_code(): DutchLanguage,
        EnglishLanguage.language_code(): EnglishLanguage,
        FinnishLanguage.language_code(): FinnishLanguage,
        FrenchLanguage.language_code(): FrenchLanguage,
        GermanLanguage.language_code(): GermanLanguage,
        HausaLanguage.language_code(): HausaLanguage,
        HindiLanguage.language_code(): HindiLanguage,
        HungarianLanguage.language_code(): HungarianLanguage,
        ItalianLanguage.language_code(): ItalianLanguage,
        JapaneseLanguage.language_code(): JapaneseLanguage,
        LithuanianLanguage.language_code(): LithuanianLanguage,
        NorwegianLanguage.language_code(): NorwegianLanguage,
        PortugueseLanguage.language_code(): PortugueseLanguage,
        RomanianLanguage.language_code(): RomanianLanguage,
        RussianLanguage.language_code(): RussianLanguage,
        SpanishLanguage.language_code(): SpanishLanguage,
        SwedishLanguage.language_code(): SwedishLanguage,
        TurkishLanguage.language_code(): TurkishLanguage,
    }

    # Static language object instances ({'language code': language object, ... })
    __language_instances = dict()

    @staticmethod
    def enabled_languages() -> set:
        """Return set of enabled languages (their codes)."""
        return set(LanguageFactory.__ENABLED_LANGUAGES.keys())

    @staticmethod
    def language_is_enabled(language_code: str) -> bool:
        """Return True if language is supported + enabled, False if it's not."""

        language_code = decode_object_from_bytes_if_needed(language_code)

        if language_code is None:
            log.warning("Language code is None.")
            return False

        return language_code in LanguageFactory.__ENABLED_LANGUAGES

    @staticmethod
    def language_for_code(language_code: str) -> Union[AbstractLanguage, None]:
        """Return language module instance for the language code, None if language is not supported."""

        language_code = decode_object_from_bytes_if_needed(language_code)

        if not LanguageFactory.language_is_enabled(language_code):
            return None

        if language_code not in LanguageFactory.__language_instances:
            language_class = LanguageFactory.__ENABLED_LANGUAGES[language_code]
            language = language_class()
            LanguageFactory.__language_instances[language_code] = language

        return LanguageFactory.__language_instances[language_code]

    @staticmethod
    def default_language_code() -> str:
        """Return default language code ('en' for English)."""
        return EnglishLanguage.language_code()

    @staticmethod
    def default_language() -> AbstractLanguage:
        """Return default language module instance (English)."""
        return LanguageFactory.language_for_code(LanguageFactory.default_language_code())
