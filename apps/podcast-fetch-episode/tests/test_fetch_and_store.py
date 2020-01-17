import os
from typing import Union

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story
from mediawords.test.hash_server import HashServer
from mediawords.util.network import random_unused_port

from podcast_fetch_episode.fetch_and_store import fetch_and_store_episode
from podcast_fetch_episode.gcs_store import GCSStore

from .config_random_gcs_prefix import RandomPathPrefixConfig

TEST_MP3_PATH = '/opt/mediacloud/tests/data/media-samples/samples/kim_kardashian-mp3.mp3'
assert os.path.isfile(TEST_MP3_PATH), f"Test MP3 file '{TEST_MP3_PATH}' should exist."


def test_fetch_and_store_episode():
    db = connect_to_db()

    test_medium = create_test_medium(db=db, label='test')
    test_feed = create_test_feed(db=db, label='test', medium=test_medium)

    # 'label' is important as it will be stored in both stories.title and stories.description, which in turn will be
    # used to guess the probable language of the podcast episode
    test_story = create_test_story(db=db, label='keeping up with Kardashians', feed=test_feed)

    stories_id = test_story['stories_id']

    with open(TEST_MP3_PATH, mode='rb') as f:
        test_mp3_data = f.read()

    # noinspection PyUnusedLocal
    def __mp3_callback(request: HashServer.Request) -> Union[str, bytes]:
        response = "".encode('utf-8')
        response += "HTTP/1.0 200 OK\r\n".encode('utf-8')
        response += "Content-Type: audio/mpeg\r\n".encode('utf-8')
        response += f"Content-Length: {len(test_mp3_data)}\r\n".encode('utf-8')
        response += "\r\n".encode('utf-8')
        response += test_mp3_data
        return response

    port = random_unused_port()
    pages = {
        '/test.mp3': {
            'callback': __mp3_callback,
        }
    }

    hs = HashServer(port=port, pages=pages)
    hs.start()

    mp3_url = f'http://127.0.0.1:{port}/test.mp3'

    story_enclosure = db.insert(table='story_enclosures', insert_hash={
        'stories_id': stories_id,
        'url': mp3_url,
        'mime_type': 'audio/mpeg',
        'length': len(test_mp3_data),
    })

    config = RandomPathPrefixConfig()
    fetch_and_store_episode(db=db, stories_id=stories_id, config=config)

    episodes = db.select(table='podcast_episodes', what_to_select='*').hashes()
    assert len(episodes), f"Only one episode is expected."

    episode = episodes[0]
    assert episode['stories_id'] == stories_id
    assert episode['story_enclosures_id'] == story_enclosure['story_enclosures_id']
    assert episode['gcs_uri'] == f"gs://{config.gc_storage_bucket_name()}/{config.gc_storage_path_prefix()}/{stories_id}"
    assert episode['duration'] > 0
    assert episode['codec'] == 'MP3'
    assert episode['audio_channel_count'] == 2
    assert episode['sample_rate'] == 44100
    assert episode['bcp47_language_code'] == 'en-US'

    # Try removing test object
    gcs = GCSStore(config=config)
    gcs.delete_object(object_id=str(stories_id))
