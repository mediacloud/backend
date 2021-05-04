#!/usr/bin/env python3

import asyncio

from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

# noinspection PyPackageRequirements
from temporal.workflow import WorkflowClient, WorkflowOptions

from podcast_transcribe_episode.workflow_interface import NAMESPACE, AbstractPodcastTranscribeWorkflow

log = create_logger(__name__)


async def _start_workflow(stories_id: int) -> None:
    log.info(f"Starting a workflow for story {stories_id}...")

    client = WorkflowClient.new_client(host='temporal-server', namespace=NAMESPACE)
    workflow: AbstractPodcastTranscribeWorkflow = client.new_workflow_stub(
        cls=AbstractPodcastTranscribeWorkflow,
        workflow_options=WorkflowOptions(workflow_id=str(stories_id)),
    )

    # Fire and forget as the workflow will do everything (including adding a extraction job) itself
    await WorkflowClient.start(workflow.transcribe_episode, stories_id)

    log.info(f"Started a workflow for story {stories_id}...")


def run_podcast_fetch_episode(stories_id: int) -> None:
    if isinstance(stories_id, bytes):
        stories_id = decode_object_from_bytes_if_needed(stories_id)
    stories_id = int(stories_id)

    asyncio.run(_start_workflow(stories_id=stories_id))


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::Podcast::TranscribeEpisode')
    app.start_worker(handler=run_podcast_fetch_episode)
