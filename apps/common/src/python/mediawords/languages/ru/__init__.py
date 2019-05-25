from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class RussianLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """Russian language support module."""

    @staticmethod
    def language_code() -> str:
        return "ru"

    @staticmethod
    def sample_sentence() -> str:
        return "а неправильный формат идентификатора дн назад"
