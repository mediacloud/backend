from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class GermanLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """German language support module."""

    @staticmethod
    def language_code() -> str:
        return "de"

    @staticmethod
    def sample_sentence() -> str:
        return "Victor jagt zwölf Boxkämpfer quer über den großen Sylter Deich."
