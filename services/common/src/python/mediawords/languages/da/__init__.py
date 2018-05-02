from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class DanishLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """Danish language support module."""

    @staticmethod
    def language_code() -> str:
        return "da"

    @staticmethod
    def sample_sentence() -> str:
        return "Quizdeltagerne spiste jordbær med fløde, mens cirkusklovnen Walther spillede på xylofon."
