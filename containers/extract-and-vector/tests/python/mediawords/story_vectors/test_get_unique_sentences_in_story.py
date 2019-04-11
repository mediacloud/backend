#!/usr/bin/env py.test

# noinspection PyProtectedMember
from mediawords.story_vectors import _get_unique_sentences_in_story


def test_get_unique_sentences_in_story():
    assert _get_unique_sentences_in_story(['c', 'c', 'b', 'a', 'a']) == ['c', 'b', 'a']
