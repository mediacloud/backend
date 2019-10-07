from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class HungarianLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """Hungarian language support module."""

    @staticmethod
    def language_code() -> str:
        return "hu"

    @staticmethod
    def sample_sentence() -> str:
        return "Jó foxim és don Quijote húszwattos lámpánál ülve egy pár bűvös cipőt készít."
