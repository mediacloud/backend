import csv
from datetime import timedelta

# noinspection PyPackageRequirements
import pytest
# noinspection PyPackageRequirements
from temporal.workerfactory import WorkerFactory
# noinspection PyPackageRequirements
from temporal.workflow import WorkflowOptions

from mediawords.db import connect_to_db
from mediawords.db.handler import DatabaseHandler
from mediawords.test.db.create import create_test_feed, create_test_medium, create_test_story, create_download_for_feed
from mediawords.util.log import create_logger
from mediawords.workflow.client import workflow_client
from mediawords.workflow.worker import stop_worker_faster

from merge_media_sources import FeedsMergeWorkflow, FeedsMergeWorkflowImpl, FeedsMergeActivities, FeedsMergeActivitiesImpl

log = create_logger(__name__)


def check_successful_feed_migration(db: DatabaseHandler, table: str, parent_feed_id: int) -> None:
    results = db.select(table=f'{table}', what_to_select='*').hashes()
    assert len(results) == 1
    assert results[0]['feeds_id'] == parent_feed_id


@pytest.mark.asyncio
async def test_feeds_merge_workflow() -> None:
    db = connect_to_db()
    test_medium = create_test_medium(db=db, label='test')
    child_feed = create_test_feed(db=db, label='child_feed', medium=test_medium)
    parent_feed = create_test_feed(db=db, label='parent_feed', medium=test_medium)

    create_download_for_feed(db=db, feed=child_feed)

    db.insert(table='feeds_stories_map_p', insert_hash={
        'feeds_id': child_feed['feeds_id'],
        'stories_id': 1
    })
    db.insert(table='scraped_feeds', insert_hash={
        'feeds_id': child_feed['feed_id'],
        'url': child_feed['url'],
        'scrape_date': 'NOW()',
        'import_module': 'mediawords'
    })
    db.insert(table='feeds_from_yesterday', insert_hash={
        'feeds_id': child_feed['feeds_id'],
        'media_id': test_medium['media_id'],
        'name': F"feed_from_yesterday_{child_feed['name']}",
        'url': child_feed['url'],
        'type': 'test',
        'active': True
    })
    db.insert(table='feeds_tags_map', insert_hash={
        'feeds_id': child_feed['feeds_id'],
        'tags_id': test_medium['media_id'],
    })

    client = workflow_client()

    # Start worker
    factory = WorkerFactory(client=client, namespace=client.namespace)
    worker = factory.new_worker(task_queue="merge-feeds")

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
        workflow_options=WorkflowOptions(workflow_id='test'),
    )

    # Fire and forget as the workflow will do everything (including adding a extraction job) itself
    await client.start(workflow.merge_feeds, child_feed['feeds_id'], parent_feed['feeds_id'])
    # Wait for the workflow to complete
    await workflow.merge_feeds( child_feed['feeds_id'], parent_feed['feeds_id'])

    downloads = db.select(table='downloads', what_to_select='*').hashes()
    assert len(downloads) == 1
    first_download = downloads[0]
    assert first_download['feeds_id'] == parent_feed['feeds_id']

    tables = ['downloads', 'scraped_feeds', 'feeds_from_yesterday', 'feeds_tags_map', 'feeds_stories_map_p']
    for table in tables:
        check_successful_feed_migration(db, table, parent_feed['feeds_id'])

    results = db.select(table='feeds', what_to_select='*', condition_hash={'id': child_feed['feeds_id']}).hashes()
    assert len(results) == 0

    await worker.stop(background=True)

    log.info("Stopping workers...")
    await stop_worker_faster(worker)
    log.info("Stopped workers")
