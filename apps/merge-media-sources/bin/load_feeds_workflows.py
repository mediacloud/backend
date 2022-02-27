#!/usr/bin/env python3

import asyncio

from mediawords.util.log import create_logger
from mediawords.workflow.client import workflow_client

# noinspection PyPackageRequirements
from temporal.workflow import WorkflowClient, WorkflowOptions

from merge_media_sources.feeds_workflow_interface import FeedsMergeWorkflow

log = create_logger(__name__)


async def _start_workflow(client: WorkflowClient, child_feed_id: int, parent_feed_id: int) -> None:

    log.info(f"Starting a workflow to merge feed {child_feed_id} into {parent_feed_id}...")

    workflow: FeedsMergeWorkflow = client.new_workflow_stub(
        cls=FeedsMergeWorkflow,
        workflow_options=WorkflowOptions(workflow_id=str(child_feed_id) + '_to_' + str(parent_feed_id)),
    )

    # Fire and forget as the workflow will do everything (including adding a extraction job) itself
    await WorkflowClient.start(workflow.merge_feeds, child_feed_id, parent_feed_id)

    log.info(f"Started a workflow to merge feed {child_feed_id} into {parent_feed_id}...")


def submit_feed_workflows():
    client = workflow_client()
    with open('feeds_to_merge.csv') as f:
        feeds_to_merge = [{k: int(v) for k, v in row.items()} for row in csv.DictReader(f, skipinitialspace=True)]
    for feed_pair in feeds_to_merge:
        child_feed = feed_pair['feed_id']
        parent_feed = feed_pair['parent_feed_id']
        _start_workflow(client, child_feed, parent_feed)
