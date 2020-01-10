from mediawords.db import connect_to_db
from mediawords.test.db.create import (
    create_test_medium,
    create_test_feed,
    create_test_story,
)

from podcast_fetch_episode.enclosure import podcast_viable_enclosure_for_story, StoryEnclosure


def test_podcast_viable_enclosure_for_story():
    db = connect_to_db()

    test_medium = create_test_medium(db=db, label='test')
    test_feed = create_test_feed(db=db, label='test', medium=test_medium)

    test_story_no_enclosures = create_test_story(
        db=db,
        label='no enclosures',
        feed=test_feed,
    )
    test_story_enclosure_with_empty_url = create_test_story(
        db=db,
        label='enclosure with empty URL',
        feed=test_feed,
    )
    test_story_single_mp3_enclosure = create_test_story(
        db=db,
        label='single MP3 enclosure',
        feed=test_feed,
    )
    test_story_single_mp3_without_mime_enclosure = create_test_story(
        db=db,
        label='single MP3 enclosure without MIME type set',
        feed=test_feed,
    )
    test_story_multiple_audio_enclosures = create_test_story(
        db=db,
        label='multiple audio enclosures',
        feed=test_feed,
    )
    test_story_multiple_unsupported_audio_enclosures = create_test_story(
        db=db,
        label='multiple audio enclosures none of which are supported',
        feed=test_feed,
    )
    test_story_audio_and_video_enclosures = create_test_story(
        db=db,
        label='audio and video enclosures',
        feed=test_feed,
    )
    test_story_only_video_enclosures = create_test_story(
        db=db,
        label='only video enclosures',
        feed=test_feed,
    )

    db.query("""
        INSERT INTO podcast_story_enclosures (stories_id, url, mime_type, length)
        VALUES (%(stories_id)s, '', 'audio/mpeg', 100000)
    """, {'stories_id': test_story_enclosure_with_empty_url['stories_id']})

    db.query("""
        INSERT INTO podcast_story_enclosures (stories_id, url, mime_type, length)
        VALUES (%(stories_id)s, 'http://www.example.com/test.mp3', 'audio/mpeg', 100000)
    """, {'stories_id': test_story_single_mp3_enclosure['stories_id']})

    db.query("""
        INSERT INTO podcast_story_enclosures (stories_id, url, mime_type, length)
        VALUES (%(stories_id)s, 'http://www.example.com/test.mp3', '', 100000)
    """, {'stories_id': test_story_single_mp3_without_mime_enclosure['stories_id']})

    db.query("""
        INSERT INTO podcast_story_enclosures (stories_id, url, mime_type, length)
        VALUES
            (%(stories_id)s, 'http://www.example.com/test.aac', 'audio/aac', 100000),
            (%(stories_id)s, 'http://www.example.com/test.mp3', 'audio/mpeg', 100000)
    """, {'stories_id': test_story_multiple_audio_enclosures['stories_id']})
    db.query("""
        INSERT INTO podcast_story_enclosures (stories_id, url, mime_type, length)
        VALUES
            (%(stories_id)s, 'http://www.example.com/test.aac', 'audio/aac', 100000),
            (%(stories_id)s, 'http://www.example.com/test.m4a', 'audio/mp4', 100000)
    """, {'stories_id': test_story_multiple_unsupported_audio_enclosures['stories_id']})

    db.query("""
        INSERT INTO podcast_story_enclosures (stories_id, url, mime_type, length)
        VALUES
            (%(stories_id)s, 'http://www.example.com/test.mkv', 'video/x-matroska', 100000),
            (%(stories_id)s, 'http://www.example.com/test.aac', 'audio/aac', 100000)
    """, {'stories_id': test_story_audio_and_video_enclosures['stories_id']})

    db.query("""
        INSERT INTO podcast_story_enclosures (stories_id, url, mime_type, length)
        VALUES
            (%(stories_id)s, 'http://www.example.com/test.mkv', 'video/x-matroska', 100000),
            (%(stories_id)s, 'http://www.example.com/test.mp4', 'video/mp4', 100000)
    """, {'stories_id': test_story_only_video_enclosures['stories_id']})

    assert podcast_viable_enclosure_for_story(
        db=db,
        stories_id=test_story_no_enclosures['stories_id'],
    ) is None, "Story with no enclosures."

    assert podcast_viable_enclosure_for_story(
        db=db,
        stories_id=test_story_enclosure_with_empty_url['stories_id'],
    ) is None, "Story with an empty enclosure URL."

    assert podcast_viable_enclosure_for_story(
        db=db,
        stories_id=test_story_single_mp3_enclosure['stories_id'],
    ) == StoryEnclosure(
        url='http://www.example.com/test.mp3',
        mime_type='audio/mpeg',
        length=100000,
    ), "Story with a single MP3 enclosure should return that one enclosure."

    assert podcast_viable_enclosure_for_story(
        db=db,
        stories_id=test_story_single_mp3_without_mime_enclosure['stories_id'],
    ) == StoryEnclosure(
        url='http://www.example.com/test.mp3',
        mime_type='',
        length=100000,
    ), "Story with a single MP3 enclosure without MIME type set should return that enclosure."

    assert podcast_viable_enclosure_for_story(
        db=db,
        stories_id=test_story_multiple_audio_enclosures['stories_id'],
    ) == StoryEnclosure(
        url='http://www.example.com/test.mp3',
        mime_type='audio/mpeg',
        length=100000,
    ), "Story with multiple audio enclosures should return a supported audio enclosure."

    assert podcast_viable_enclosure_for_story(
        db=db,
        stories_id=test_story_multiple_unsupported_audio_enclosures['stories_id'],
    ) == StoryEnclosure(
        url='http://www.example.com/test.aac',
        mime_type='audio/aac',
        length=100000,
    ), "Story with multiple unsupported audio enclosures should return a first audio enclosure."

    assert podcast_viable_enclosure_for_story(
        db=db,
        stories_id=test_story_audio_and_video_enclosures['stories_id'],
    ) == StoryEnclosure(
        url='http://www.example.com/test.aac',
        mime_type='audio/aac',
        length=100000,
    ), "Story with audio and video enclosures should return an audio enclosure."

    assert podcast_viable_enclosure_for_story(
        db=db,
        stories_id=test_story_only_video_enclosures['stories_id'],
    ) == StoryEnclosure(
        url='http://www.example.com/test.mkv',
        mime_type='video/x-matroska',
        length=100000,
    ), "Story with only video enclosures should return the first video enclosure."
