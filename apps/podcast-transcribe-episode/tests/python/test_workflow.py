import os
from typing import Union

# noinspection PyPackageRequirements
import pytest
# noinspection PyPackageRequirements
from temporal.workerfactory import WorkerFactory
# noinspection PyPackageRequirements
from temporal.workflow import WorkflowOptions

from mediawords.db import connect_to_db
from mediawords.dbi.downloads.store import fetch_content
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story
from mediawords.test.hash_server import HashServer
from mediawords.util.log import create_logger
from mediawords.util.network import random_unused_port
from mediawords.workflow.client import workflow_client

from podcast_transcribe_episode.workflow import PodcastTranscribeActivities, PodcastTranscribeWorkflow
from podcast_transcribe_episode.workflow_interface import (
    TASK_QUEUE,
    AbstractPodcastTranscribeActivities,
    AbstractPodcastTranscribeWorkflow,
)

from podcast_transcribe_episode.config import (
    PodcastTranscribeEpisodeConfig,
    AbstractGCBucketConfig,
    RawEnclosuresGCBucketConfig,
    TranscodedEpisodesGCBucketConfig,
    TranscriptsGCBucketConfig,
)

from .random_gcs_prefix import random_gcs_path_prefix

log = create_logger(__name__)

TEST_MP3_PATH = '/opt/mediacloud/tests/data/media-samples/samples/kim_kardashian-mp3-mono.mp3'
assert os.path.isfile(TEST_MP3_PATH), f"Test MP3 file '{TEST_MP3_PATH}' should exist."


class _RandomPrefixesPodcastTranscribeEpisodeConfig(PodcastTranscribeEpisodeConfig):
    """Custom configuration which uses random GCS prefixes."""

    __slots__ = [
        '__raw_enclosures_config',
        '__transcoded_episodes_config',
        '__transcripts_config',
    ]

    def __init__(self):
        super().__init__()

        # Create bucket config classes once so that if we call the getters again, the random prefixes don't get
        # regenerated
        self.__raw_enclosures_config = RawEnclosuresGCBucketConfig(path_prefix=random_gcs_path_prefix())
        self.__transcoded_episodes_config = TranscodedEpisodesGCBucketConfig(path_prefix=random_gcs_path_prefix())
        self.__transcripts_config = TranscriptsGCBucketConfig(path_prefix=random_gcs_path_prefix())

    def raw_enclosures(self) -> AbstractGCBucketConfig:
        return self.__raw_enclosures_config

    def transcoded_episodes(self) -> AbstractGCBucketConfig:
        return self.__transcoded_episodes_config

    def transcripts(self) -> AbstractGCBucketConfig:
        return self.__transcripts_config


# Custom activities subclass with random bucket prefixes
class _RandomPrefixesPodcastTranscribeActivities(PodcastTranscribeActivities):

    @classmethod
    def _create_config(cls) -> PodcastTranscribeEpisodeConfig:
        return _RandomPrefixesPodcastTranscribeEpisodeConfig()


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

    client = workflow_client()

    # Start worker
    factory = WorkerFactory(client=client, namespace=client.namespace)
    worker = factory.new_worker(task_queue=TASK_QUEUE)
    worker.register_activities_implementation(

        # Use an activities implementation with random GCS prefixes set
        activities_instance=_RandomPrefixesPodcastTranscribeActivities(),

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

    downloads = db.select(table='downloads', what_to_select='*').hashes()
    assert len(downloads) == 1
    first_download = downloads[0]
    assert first_download['stories_id'] == stories_id
    assert first_download['type'] == 'content'
    assert first_download['state'] == 'success'

    download_content = fetch_content(db=db, download=first_download)

    # It's what gets said in the sample MP3 file
    assert 'Kim Kardashian' in download_content

    log.info("Stopping workers...")
    await worker.stop()
    log.info("Stopped workers")
