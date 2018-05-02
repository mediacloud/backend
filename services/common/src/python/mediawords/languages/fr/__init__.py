from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class FrenchLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """French language support module."""

    @staticmethod
    def language_code() -> str:
        return "fr"

    @staticmethod
    def sample_sentence() -> str:
        return "Buvez de ce whisky que le patron juge fameux."
