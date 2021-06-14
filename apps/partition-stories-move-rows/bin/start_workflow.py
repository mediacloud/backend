#!/usr/bin/env python3

from temporal.workflow import WorkflowClient

from mediawords.util.log import create_logger
from mediawords.workflow.client import workflow_client

from partition_stories_move_rows import MoveRowsWorkflow

log = create_logger(__name__)


def start_workflow():
    log.info("Starting the workflow to rows from 'stories_unpartitioned' to 'stories_partitioned'...")
    client = workflow_client()
    workflow: MoveRowsWorkflow = client.new_workflow_stub(cls=MoveRowsWorkflow)
    await WorkflowClient.start(workflow.move_rows)
    log.info("Started the workflow to rows from 'stories_unpartitioned' to 'stories_partitioned'")


if __name__ == '__main__':
    start_workflow()
