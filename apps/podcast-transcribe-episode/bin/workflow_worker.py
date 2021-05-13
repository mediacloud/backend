#!/usr/bin/env python3

import asyncio

# noinspection PyPackageRequirements
from temporal.workerfactory import WorkerFactory
# noinspection PyPackageRequirements
from temporal.workflow import WorkflowClient

from mediawords.util.log import create_logger
from mediawords.util.network import wait_for_tcp_port_to_open

from podcast_transcribe_episode.workflow import PodcastTranscribeWorkflow, PodcastTranscribeActivities
from podcast_transcribe_episode.workflow_interface import NAMESPACE, TASK_QUEUE, AbstractPodcastTranscribeActivities

log = create_logger(__name__)


async def _start_worker():

    # FIXME it's super lame to wait for this port to open, but the Python SDK seems to fail otherwise
    wait_for_tcp_port_to_open(hostname='temporal-server', port=7233)

    client = WorkflowClient.new_client(host='temporal-server', namespace=NAMESPACE)

    factory = WorkerFactory(client=client, namespace=NAMESPACE)
    worker = factory.new_worker(task_queue=TASK_QUEUE)
    worker.register_activities_implementation(
        activities_instance=PodcastTranscribeActivities(),
        activities_cls_name=AbstractPodcastTranscribeActivities.__name__,
    )
    worker.register_workflow_implementation_type(impl_cls=PodcastTranscribeWorkflow)
    factory.start()


if __name__ == '__main__':
    loop = asyncio.get_event_loop()
    asyncio.ensure_future(_start_worker())
    loop.run_forever()
