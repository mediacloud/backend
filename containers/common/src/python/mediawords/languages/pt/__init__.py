from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class PortugueseLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """Portuguese language support module."""

    @staticmethod
    def language_code() -> str:
        return "pt"

    @staticmethod
    def sample_sentence() -> str:
        return "Luís argüia à Júlia que «brações, fé, chá, óxido, pôr, zângão» eram palavras do português."
