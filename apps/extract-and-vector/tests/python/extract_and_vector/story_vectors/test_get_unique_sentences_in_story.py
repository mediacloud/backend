# noinspection PyProtectedMember
from extract_and_vector.story_vectors import _get_unique_sentences_in_story


def test_get_unique_sentences_in_story():
    assert _get_unique_sentences_in_story(['c', 'c', 'b', 'a', 'a']) == ['c', 'b', 'a']
