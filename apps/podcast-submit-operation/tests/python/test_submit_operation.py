from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story

from podcast_submit_operation.submit_operation import get_podcast_episode, submit_transcribe_operation


def test_submit_transcribe_operation():
    test_gcs_uri = "gs://mc-podcast-sample-audio-files/samples/kim_kardashian-mp3.mp3"

    db = connect_to_db()
    test_medium = create_test_medium(db=db, label='test')
    test_feed = create_test_feed(db=db, label='test', medium=test_medium)
    story = create_test_story(db=db, label='test', feed=test_feed)

    stories_id = story['stories_id']

    enclosure = db.insert(table='story_enclosures', insert_hash={
        'stories_id': stories_id,
        # URL doesn't really matter as we won't be fetching it
        'url': 'http://example.com/',
        'mime_type': 'audio/mpeg',
        'length': 100000,
    })

    db.insert(table='podcast_episodes', insert_hash={
        'stories_id': stories_id,
        'story_enclosures_id': enclosure['story_enclosures_id'],
        'gcs_uri': test_gcs_uri,

        # We lie about the duration because we want to test whether 'add_to_queue_at' will be set way into the future
        'duration': 60 * 60,

        'codec': 'MP3',
        'sample_rate': 44100,
        'bcp47_language_code': 'en-US',
    })

    episode = get_podcast_episode(db=db, stories_id=stories_id)
    speech_operation_id = submit_transcribe_operation(episode=episode)
    assert speech_operation_id
