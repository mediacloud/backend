#!/usr/bin/env py.test

# noinspection PyProtectedMember
from mediawords.story_vectors import _clean_sentences


def test_clean_sentences():
    good_sentences = [
        # Normal ones (should go through)
        "The quick brown fox jumps over the lazy dog.",
        "Įlinkdama fechtuotojo špaga sublykčiojusi pragręžė apvalų arbūzą.",
        "いろはにほへと ちりぬるを わかよたれそ つねならむ うゐのおくやま けふこえて あさきゆめみし ゑひもせす",
        "視野無限廣，窗外有藍天",

        # Very short but not ASCII
        "視",
    ]

    bad_sentences = [
        # Too short
        "this",
        "this.",

        # Too weird
        "[{[{[{[{[{",
    ]

    cleaned_sentences = _clean_sentences(sentences=good_sentences + bad_sentences)

    assert cleaned_sentences == good_sentences
