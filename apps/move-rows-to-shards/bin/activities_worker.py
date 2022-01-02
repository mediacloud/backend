#!/usr/bin/env python3

import asyncio

# noinspection PyPackageRequirements
from temporal.workerfactory import WorkerFactory

from mediawords.util.log import create_logger
from mediawords.workflow.client import workflow_client

from move_rows_to_shards.workflow import MoveRowsToShardsActivitiesImpl
from move_rows_to_shards.workflow_interface import TASK_QUEUE, MoveRowsToShardsActivities

log = create_logger(__name__)


async def _start_activities():
    client = workflow_client()
    factory = WorkerFactory(client=client, namespace=client.namespace)
    worker = factory.new_worker(task_queue=TASK_QUEUE)
    worker.register_activities_implementation(
        activities_instance=MoveRowsToShardsActivitiesImpl(),
        activities_cls_name=MoveRowsToShardsActivities.__name__,
    )
    factory.start()


if __name__ == '__main__':
    loop = asyncio.get_event_loop()
    asyncio.ensure_future(_start_activities())
    loop.run_forever()
