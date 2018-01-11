from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class EnglishLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """English language support module."""

    @staticmethod
    def language_code() -> str:
        return "en"

    @staticmethod
    def sample_sentence() -> str:
        return "The quick brown fox jumps over the lazy dog."
