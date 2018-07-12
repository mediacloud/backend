from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class RomanianLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """Romanian language support module."""

    @staticmethod
    def language_code() -> str:
        return "ro"

    @staticmethod
    def sample_sentence() -> str:
        return "Ex-sportivul își fumează jucăuș țigara bând whisky cu tequila."
