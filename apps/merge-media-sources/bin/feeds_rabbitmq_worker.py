#!/usr/bin/env python3

import asyncio

from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.workflow.client import workflow_client

# noinspection PyPackageRequirements
from temporal.workflow import WorkflowClient, WorkflowOptions

from merge_media_sources.workflow_interface import FeedsMergeWorkflow

log = create_logger(__name__)


async def _start_workflow(parent_feeds_id: int, child_feeds_id: int) -> None:
    log.info(f"Starting a workflow to merge feed {child_feeds_id} into {parent_feeds_id}...")

    client = workflow_client()
    workflow: FeedsMergeWorkflow = client.new_workflow_stub(
        cls=FeedsMergeWorkflow,
        workflow_options=WorkflowOptions(workflow_id=str(child_feeds_id)),
    )

    # Fire and forget as the workflow will do everything (including adding a extraction job) itself
    await WorkflowClient.start(workflow.merge_feeds, child_feeds_id, parent_feeds_id)

    log.info(f"Started a workflow to merge feed {child_feeds_id} into {parent_feeds_id}...")


    def run_merge_feeds(parent_feeds_id: int, child_feeds_id: int) -> None:
        # todo: some stuff


    asyncio.run(_start_workflow(feeds_id=child_feeds_id, parent_feeds_id=parent_feeds_id))


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::Feeds::MergeFeeds')
    app.start_worker(handler=run_merge_feeds)
