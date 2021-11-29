#!/usr/bin/env python3

"""
Add a Temporal job that will gradually move rows to sharded tables
"""

import asyncio

from mediawords.util.log import create_logger
from mediawords.workflow.client import workflow_client

# noinspection PyPackageRequirements
from temporal.workflow import WorkflowClient, WorkflowOptions

from move_rows_to_shards.workflow_interface import MoveRowsToShardsWorkflow

log = create_logger(__name__)


async def _start_move_rows_to_shards() -> None:
    log.info(f"Starting a workflow to move rows to shards...")

    client = workflow_client()
    workflow: MoveRowsToShardsWorkflow = client.new_workflow_stub(
        cls=MoveRowsToShardsWorkflow,
        workflow_options=WorkflowOptions(workflow_id="move_rows_to_shards"),
    )

    # Fire and forget as the workflow will do everything itself
    await WorkflowClient.start(workflow.move_rows_to_shards)

    log.info(f"Started a workflow to move rows to shards")


if __name__ == '__main__':
    asyncio.run(_start_move_rows_to_shards())
