import os
from typing import Union

# noinspection PyPackageRequirements
import pytest
# noinspection PyPackageRequirements
from podcast_transcribe_episode.workflow import PodcastTranscribeActivities, PodcastTranscribeWorkflow
from podcast_transcribe_episode.workflow_interface import (
    NAMESPACE,
    TASK_QUEUE,
    AbstractPodcastTranscribeActivities,
    AbstractPodcastTranscribeWorkflow,
)
# noinspection PyPackageRequirements
from temporal.workerfactory import WorkerFactory
# noinspection PyPackageRequirements
from temporal.workflow import WorkflowClient, WorkflowOptions

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story
from mediawords.test.hash_server import HashServer
from mediawords.util.network import random_unused_port, wait_for_tcp_port_to_open

TEST_MP3_PATH = '/opt/mediacloud/tests/data/media-samples/samples/kim_kardashian-mp3-mono.mp3'
assert os.path.isfile(TEST_MP3_PATH), f"Test MP3 file '{TEST_MP3_PATH}' should exist."


@pytest.mark.asyncio
async def test_workflow():
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

    # Not localhost as this might get fetched from a remote worker
    mp3_url = hs.page_url('/test.mp3')

    db.insert(table='story_enclosures', insert_hash={
        'stories_id': stories_id,
        'url': mp3_url,
        'mime_type': 'audio/mpeg',
        'length': len(test_mp3_data),
    })

    # FIXME it's super lame to wait for this port to open
    wait_for_tcp_port_to_open(hostname='temporal-server', port=7233)

    # FIXME move workflow client init to "common"
    client = WorkflowClient.new_client(host='temporal-server', namespace=NAMESPACE)

    # Start worker
    factory = WorkerFactory(client=client, namespace=NAMESPACE)
    worker = factory.new_worker(task_queue=TASK_QUEUE)
    worker.register_activities_implementation(
        activities_instance=PodcastTranscribeActivities(),
        activities_cls_name=AbstractPodcastTranscribeActivities.__name__,
    )
    worker.register_workflow_implementation_type(impl_cls=PodcastTranscribeWorkflow)
    factory.start()

    # Initialize workflow instance
    workflow: AbstractPodcastTranscribeWorkflow = client.new_workflow_stub(
        cls=AbstractPodcastTranscribeWorkflow,
        workflow_options=WorkflowOptions(workflow_id=str(stories_id)),
    )

    # Wait for the workflow to complete
    await workflow.transcribe_episode(stories_id)

    await worker.stop(background=True)
