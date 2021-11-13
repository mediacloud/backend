#!/usr/bin/env python3

import asyncio

# noinspection PyPackageRequirements
from temporal.workerfactory import WorkerFactory

from mediawords.util.log import create_logger
from mediawords.workflow.client import workflow_client

from merge_media_sources.feeds_workflow import FeedsMergeWorkflowImpl, FeedsMergeActivitiesImpl
from merge_media_sources.feeds_workflow_interface import TASK_QUEUE, FeedsMergeActivities
from load_feeds_workflows import submit_feed_workflows

log = create_logger(__name__)


async def _start_worker():
    client = workflow_client()
    factory = WorkerFactory(client=client, namespace=client.namespace)
    worker = factory.new_worker(task_queue=TASK_QUEUE)
    worker.register_activities_implementation(
        activities_instance=FeedsMergeActivitiesImpl(),
        activities_cls_name=FeedsMergeActivities.__name__,
    )
    worker.register_workflow_implementation_type(impl_cls=FeedsMergeWorkflowImpl)
    factory.start()


if __name__ == '__main__':
    loop = asyncio.get_event_loop()
    asyncio.ensure_future(_start_worker())
    submit_feed_workflows()
    loop.run_forever()
