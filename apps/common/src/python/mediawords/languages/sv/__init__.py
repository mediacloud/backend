from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class SwedishLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """Swedish language support module."""

    @staticmethod
    def language_code() -> str:
        return "sv"

    @staticmethod
    def sample_sentence() -> str:
        return "a bort objekt från google desktop post äldst meny öretag dress etaljer alternativ för vad är inne yaste"
