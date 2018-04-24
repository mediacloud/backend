from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class FinnishLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """Finnish language support module."""

    @staticmethod
    def language_code() -> str:
        return "fi"

    @staticmethod
    def sample_sentence() -> str:
        return "Hyvän lorun sangen pieneksi hyödyksi jäi suomen kirjaimet."
