import os
from datetime import timedelta
from typing import Union

# noinspection PyPackageRequirements
import pytest
# noinspection PyPackageRequirements
from temporal.workerfactory import WorkerFactory
# noinspection PyPackageRequirements
from temporal.workflow import WorkflowOptions

from mediawords.db import connect_to_db
from mediawords.dbi.downloads.store import fetch_content
from mediawords.test.db.create import create_test_feed, create_test_medium, create_test_story, create_download_for_feed
from mediawords.test.hash_server import HashServer
from mediawords.util.log import create_logger
from mediawords.util.network import random_unused_port
from mediawords.workflow.client import workflow_client
from mediawords.workflow.worker import stop_worker_faster


log = create_logger(__name__)


@pytest.mark.asyncio
async def test_feeds_workflow():
    db = connect_to_db()

    test_medium = create_test_medium(db=db, label='test')
    test_parent_feed = create_test_feed(db=db, label='parent', medium=test_medium)
    test_child_feeds = []
    for i in range(1,4):
        test_child_feeds.append(create_test_feed(db=db, label=F'child_feed_{str(i)}', medium=test_medium))

    for feed in test_child_feeds:
        create_download_for_feed(db=db, feed=feed)
        create_test_story(db=db, label=F"story for {feed['label']}", feed=feed)
        db.insert(table='scraped_feeds', insert_hash={
            'feeds_id': int(feed['feeds_id']),
            'url': feed['url'],
            'scrape_date': 'NOW()',
            'import_module': 'mediawords'
        })
        db.insert(table='feeds_from_yesterday', insert_hash={
            'feeds_id': int(feed['feeds_id']),
            'media_id': int(test_medium['media_id']),
            'name': F"feed_from_yesterday_{feed['name']}",
            'url': feed['url'],
            'type': 'test',
            'active': True
        })
        db.insert(table='feeds_tags_map', insert_hash={
            'feeds_id': int(feed['feeds_id']),
            'tags_id': int(test_medium['media_id']),
        })


    client = workflow_client()

    # Start worker
    factory = WorkerFactory(client=client, namespace=client.namespace)
    worker = factory.new_worker(task_queue=TASK_QUEUE)

    activities = FeedsMergeActivities()

    worker.register_activities_implementation(
        activities_instance=activities,
        activities_cls_name=FeedsMergeActivities.__name__,
    )
    worker.register_workflow_implementation_type(impl_cls=FeedsMergeWorkflowImpl)
    factory.start()

    # Initialize workflow instance
    workflow: FeedsMergeWorkflow = client.new_workflow_stub(
        cls=FeedsMergeWorkflow,
        workflow_options=WorkflowOptions(
            workflow_id=str(stories_id),

            # By default, if individual activities of the workflow fail, they will get restarted pretty much
            # indefinitely, and so this test might run for days (or rather just timeout on the CI). So we cap the
            # workflow so that if it doesn't manage to complete in X minutes, we consider it as failed.
            workflow_run_timeout=timedelta(minutes=5),

        ),
    )

    # Wait for the workflow to complete
    await workflow.merge_feeds(feeds_id=feed[], parent_feeds_id=test_parent_feed['feeds_id'])

    downloads = db.select(table='downloads', what_to_select='*').hashes()
    assert len(downloads) == 1
    first_download = downloads[0]
    assert first_download['stories_id'] == stories_id
    assert first_download['type'] == 'content'
    assert first_download['state'] == 'success'


    # Initiate the worker shutdown in the background while we do the GCS cleanup so that the stop_workers_faster()
    # doesn't have to wait that long
    await worker.stop(background=True)

    log.info("Stopping workers...")
    await stop_worker_faster(worker)
    log.info("Stopped workers")
