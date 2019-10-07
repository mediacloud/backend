from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class NorwegianLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """Norwegian (Bokmål) language support module."""

    @staticmethod
    def language_code() -> str:
        return "no"

    @staticmethod
    def sample_sentence() -> str:
        return "Vår sære Zulu fra badeøya spilte jo whist og quickstep i min taxi."
