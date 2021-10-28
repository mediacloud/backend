#!/usr/bin/env python3

import asyncio

# noinspection PyPackageRequirements
from temporal.workerfactory import WorkerFactory

from mediawords.util.log import create_logger
from mediawords.workflow.client import workflow_client

from merge_media_sources.workflow import MergeMediaWorkflowImpl, MergeMediaActivitiesImpl
from merge_media_sources.workflow_interface import TASK_QUEUE, MergeMediaActivities

log = create_logger(__name__)


async def _start_worker():
    client = workflow_client()
    factory = WorkerFactory(client=client, namespace=client.namespace)
    worker = factory.new_worker(task_queue=TASK_QUEUE)
    worker.register_activities_implementation(
        activities_instance=MergeMediaActivitiesImpl(),
        activities_cls_name=MergeMediaActivities.__name__,
    )
    worker.register_workflow_implementation_type(impl_cls=MergeMediaWorkflowImpl)
    factory.start()


if __name__ == '__main__':
    loop = asyncio.get_event_loop()
    asyncio.ensure_future(_start_worker())
    loop.run_forever()
