from mediawords.db import connect_to_db, DatabaseHandler
from mediawords.dbi.stories.ap import get_ap_medium_name, is_syndicated
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story, add_content_to_test_story

AP_SENTENCES = [
    'AP sentence < 32.',
    'AP sentence >= 32 #1 (with some more text to pad out the length to 32).',
    'AP sentence >= 32 #2 (with some more text to pad out the length to 32).',
    'AP sentence >= 32 #3 (with some more text to pad out the length to 32).',
    'AP sentence >= 32 #4 (with some more text to pad out the length to 32).',
    'AP sentence >= 32 #5 (with some more text to pad out the length to 32).',
    'AP sentence >= 32 #6 (with some more text to pad out the length to 32).',
    'AP sentence >= 32 #7 (with some more text to pad out the length to 32).',
    'AP sentence >= 32 #8 (with some more text to pad out the length to 32).',
    'AP sentence >= 32 #9 (with some more text to pad out the length to 32).',
    'AP sentence >= 32 #10 (with some more text to pad out the length to 32).',
    'AP sentence >= 32 #11 (with some more text to pad out the length to 32).',
    'AP sentence >= 32 #12 (with some more text to pad out the length to 32).',
    'AP sentence >= 32 #13 (with some more text to pad out the length to 32).',
    'AP sentence >= 32 #14 (with some more text to pad out the length to 32).',
]


def __is_syndicated(db: DatabaseHandler, content: str) -> bool:
    label = content[:64]

    medium = create_test_medium(db=db, label=label)
    feed = create_test_feed(db=db, label=label, medium=medium)
    story = create_test_story(db=db, label=label, feed=feed)

    story['content'] = content

    story = add_content_to_test_story(db=db, story=story, feed=feed)

    return is_syndicated(db=db, story_title=story['title'], story_text=content)


def test_ap_calls():
    db = connect_to_db()

    ap_medium = create_test_medium(db=db, label=get_ap_medium_name())
    feed = create_test_feed(db=db, label='feed', medium=ap_medium)
    story = create_test_story(db=db, label='story', feed=feed)

    story['content'] = "\n".join(AP_SENTENCES)

    add_content_to_test_story(db=db, story=story, feed=feed)

    ap_content_single_16_sentence = None
    ap_content_32_sentences = []

    for sentence in AP_SENTENCES:

        if ap_content_single_16_sentence is None and len(sentence) < 32:
            ap_content_single_16_sentence = sentence

        if len(sentence) > 32:
            ap_content_32_sentences.append(sentence)

    assert ap_content_single_16_sentence is not None
    assert len(ap_content_32_sentences) > 0

    ap_content_single_32_sentence = ap_content_32_sentences[0]

    assert __is_syndicated(db=db, content='foo') is False, "Simple unsyndicated story"
    assert __is_syndicated(db=db, content='(ap)') is True, "Simple ('ap') pattern"

    assert __is_syndicated(db=db, content="associated press") is False, "Only 'associated press'"
    assert __is_syndicated(db=db, content="'associated press'") is True, "Quoted 'associated press'"

    assert __is_syndicated(
        db=db,
        content="associated press.\n" + ap_content_single_32_sentence
    ) is True, "Associated press and AP sentence"
    assert __is_syndicated(
        db=db,
        content="associated press.\n" + ap_content_single_16_sentence
    ) is False, "Associated press and short AP sentence"

    assert __is_syndicated(
        db=db,
        content=ap_content_single_32_sentence
    ) is False, 'Single AP sentence'

    assert __is_syndicated(
        db=db,
        content="Boston (AP)\n" + ap_content_single_32_sentence
    ) is True, 'AP sentence and AP location'

    assert __is_syndicated(
        db=db,
        content=' '.join(AP_SENTENCES)
    ) is True, 'All AP sentences'

    assert is_syndicated(db=db, story_text='foo') is False, "No DB story: simple story"

    assert is_syndicated(db=db, story_text='(ap)') is True, "No DB story: ('ap') story"

    assert is_syndicated(
        db=db,
        story_text=' '.join(AP_SENTENCES),
    ) is True, "No DB story: AP sentences"
