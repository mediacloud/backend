from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class TurkishLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """Turkish language support module."""

    @staticmethod
    def language_code() -> str:
        return "tr"

    @staticmethod
    def sample_sentence() -> str:
        return "Pijamalı hasta yağız şoföre çabucak güvendi."
