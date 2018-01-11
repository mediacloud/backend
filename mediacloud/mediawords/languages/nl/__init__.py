from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class DutchLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """Dutch language support module."""

    @staticmethod
    def language_code() -> str:
        return "nl"

    @staticmethod
    def sample_sentence() -> str:
        return "Pa’s wijze lynx bezag vroom het fikse aquaduct."
