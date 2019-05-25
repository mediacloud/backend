# noinspection PyProtectedMember
from extract_and_vector.story_vectors import _get_sentences_from_story_text


def test_get_sentences_from_story_text():
    story_text = """
        The banded stilt (Cladorhynchus leucocephalus) is a nomadic wader of the stilt and avocet family,
        Recurvirostridae, native to Australia. It gets its name from the red-brown breast band found on breeding adults,
        though this is mottled or entirely absent in non-breeding adults and juveniles.
    """

    sentences = _get_sentences_from_story_text(story_text=story_text, story_lang='en')
    assert len(sentences) == 2
