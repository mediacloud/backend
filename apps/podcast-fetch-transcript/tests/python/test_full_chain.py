import os
import socket
import time
from typing import Union

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story
from mediawords.test.hash_server import HashServer
from mediawords.util.log import create_logger

from podcast_fetch_transcript.fetch_transcript import fetch_speech_api_transcripts

log = create_logger(__name__)

# Run the test with AAC file to test out both transcoding to FLAC and whether Speech API can transcribe audio files
# after lossy -> lossless transcoding
TEST_M4A_PATH = '/opt/mediacloud/tests/data/media-samples/samples/kim_kardashian-aac.m4a'
assert os.path.isfile(TEST_M4A_PATH), f"Test M4A file '{TEST_M4A_PATH}' should exist."

RETRIES_PER_STEP = 120
"""How many retries to do per each step."""

SECONDS_BETWEEN_RETRIES = 0.5
"""How many seconds to wait between retries."""


def test_full_chain():
    db = connect_to_db()

    test_medium = create_test_medium(db=db, label='test')
    test_feed = create_test_feed(db=db, label='test', medium=test_medium)

    # 'label' is important as it will be stored in both stories.title and stories.description, which in turn will be
    # used to guess the probable language of the podcast episode
    test_story = create_test_story(db=db, label='keeping up with Kardashians', feed=test_feed)

    stories_id = test_story['stories_id']

    with open(TEST_M4A_PATH, mode='rb') as f:
        test_m4a_data = f.read()

    # noinspection PyUnusedLocal
    def __m4a_callback(request: HashServer.Request) -> Union[str, bytes]:
        response = "".encode('utf-8')
        response += "HTTP/1.0 200 OK\r\n".encode('utf-8')
        response += "Content-Type: audio/mp4\r\n".encode('utf-8')
        response += f"Content-Length: {len(test_m4a_data)}\r\n".encode('utf-8')
        response += "\r\n".encode('utf-8')
        response += test_m4a_data
        return response

    port = 8080  # Port exposed on docker-compose.tests.yml
    pages = {
        '/test.m4a': {
            'callback': __m4a_callback,
        }
    }

    hs = HashServer(port=port, pages=pages)
    hs.start()

    # Using our hostname as it will be another container that will be connecting to us
    m4a_url = f'http://{socket.gethostname()}:{port}/test.m4a'

    db.insert(table='story_enclosures', insert_hash={
        'stories_id': stories_id,
        'url': m4a_url,
        'mime_type': 'audio/mp4',
        'length': len(test_m4a_data),
    })

    # Add a "podcast-fetch-episode" job
    JobBroker(queue_name='MediaWords::Job::Podcast::FetchEpisode').add_to_queue(stories_id=stories_id)

    # Wait for "podcast-fetch-episode" to transcode, upload to Google Storage, and write it to "podcast_episodes"
    episodes = None
    for x in range(1, RETRIES_PER_STEP + 1):
        log.info(f"Waiting for episode to appear (#{x})...")

        episodes = db.select(table='podcast_episodes', what_to_select='*').hashes()
        if episodes:
            log.info(f"Episode is here!")
            break

        time.sleep(SECONDS_BETWEEN_RETRIES)

    assert episodes, f"Episode didn't show up in {int(RETRIES_PER_STEP * SECONDS_BETWEEN_RETRIES)} seconds."

    # Wait for "podcast-submit-operation" to submit Speech API operation
    # FIXME race condition here
    operations = None
    for x in range(1, RETRIES_PER_STEP + 1):
        log.info(f"Waiting for operation to appear (#{x})...")

        operations = db.select(table='podcast_episode_operations', what_to_select='*').hashes()
        if operations:
            log.info(f"Operation is here!")
            break

        time.sleep(SECONDS_BETWEEN_RETRIES)

    assert operations, f"Operation didn't show up in {int(RETRIES_PER_STEP * SECONDS_BETWEEN_RETRIES)} seconds."

    # Now let's do our thing and try to fetch the transcript
    transcripts = fetch_speech_api_transcripts(speech_operation_id=operations[0]['speech_operation_id'])
    assert len(transcripts) == 1
    assert len(transcripts[0].alternatives) == 1
    assert transcripts[0].alternatives[0].text.lower() == 'kim kardashian'
