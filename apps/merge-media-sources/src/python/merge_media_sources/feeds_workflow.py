# noinspection PyPackageRequirements
from temporal.workflow import Workflow

from mediawords.db import connect_to_db_or_raise
from mediawords.db.handler import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.workflow.exceptions import McProgrammingError, McTransientError, McPermanentError

from .feeds_workflow_interface import FeedsMergeWorkflow, FeedsMergeActivities

log = create_logger(__name__)


class FeedsMergeActivitiesImpl(FeedsMergeActivities):

    #TODO: when implementing media merge, consider breaking helper functions below into separate module

    @staticmethod
    def chunk_results(results: list) -> list:
        """Break results of a query into chunks of 1000 (returns list of lists)."""
        return [results[i:i + 1000] for i in range(0, len(results), 1000)]

    @staticmethod
    def get_child_feed_entries(db: DatabaseHandler, table: str, table_id_field: str, child_feed_id: int) -> list:
        log.info(f"Getting entries in {table} table associated with feed {str(child_feed_id)}")

        child_feed_id = db.find_by_id(table='feeds', object_id=child_feed_id)
        if not child_feed_id:
            raise McPermanentError(f"Feed {child_feed_id} was not found.")

        get_child_feed_entries_query = f"""
            SELECT {table_id_field}
            FROM {table}
            WHERE feeds_id = {child_feed_id};
        """

        child_feed_entries = db.query(get_child_feed_entries_query)

        log.info(f"Got all entries in downloads table for feed {str(child_feed_id)}")

        return child_feed_entries

    async def migrate_child_entries(self, table: str, table_id_field: str, id_list: list, child_feed_id: int, 
                                    parent_feed_id: int) -> None:
        log.info(f"Updating {table} table to migrate {len(id_list)} entries associated with {child_feed_id} to "
                 f"parent {parent_feed_id}")

        db = connect_to_db_or_raise()
        update_query = f"""
            UPDATE {table}
            SET feeds_id = {parent_feed_id}
            WHERE {table_id_field} IN {id_list};
        """

        db.query(update_query)

        log.info(f"Migrated {len(id_list)} entries in {table} for feed {child_feed_id} to parent {parent_feed_id}")
    
    async def delete_child_entries(self, child_feed_id: int, table: str) -> None:
        log.info(f"Deleting entries in {table} table associated with feed {str(child_feed_id)}")

        db = connect_to_db_or_raise()

        delete_query = f"""
            DELETE FROM {table}
            WHERE feeds_id = {child_feed_id};
        """

        db.query(delete_query)

        log.info(f"Deleted entries in {table} table associated with feed {str(child_feed_id)}")


class FeedsMergeWorkflowImpl(FeedsMergeWorkflow):
    """Workflow implementation."""

    def __init__(self):
        self.activities: FeedsMergeActivities = Workflow.new_activity_stub(
            activities_cls=FeedsMergeWorkflow,
            # No retry_parameters here as they get set individually in @activity_method()
        )

    async def merge_feeds(self, child_feed_id: int, parent_feed_id: int) -> None:

        child_feed_downloads = self.activities.get_child_feed_entries('downloads', 'downloads_id', child_feed_id)

        for chunk in self.activities.chunk_results(child_feed_downloads):
            await self.activities.migrate_child_entries('downloads', 'downloads_id', chunk, child_feed_id,
                                                        parent_feed_id)

        child_feed_stories_map = self.activities.get_child_feed_entries('feeds_stories_map_p', 'feeds_stories_map_p_id',
                                                                        child_feed_id)

        for chunk in self.activities.chunk_results(child_feed_stories_map):
            await self.activities.migrate_child_entries('feeds_stories_map_p', 'feeds_stories_map_p_id', chunk,
                                                        child_feed_id)
        
        child_scraped_feeds = self.activities.get_child_feed_entries('scraped_feeds', 'scraped_feeds_id', child_feed_id)

        await self.activities.migrate_child_entries('scraped_feeds', 'feed_scrapes_id', child_scraped_feeds,
                                                    child_feed_id, parent_feed_id)

        child_feeds_from_yesterday = self.activities.get_child_feed_entries('feeds_from_yesterday', 'feeds_id',
                                                                            child_feed_id)

        await self.activities.migrate_child_entries('feeds_from_yesterday', 'feeds_id', child_feeds_from_yesterday,
                                                    child_feed_id, parent_feed_id)

        child_feeds_tags_map = self.activities.get_child_feed_entries('feeds_tags_map', 'feeds_tags_map_id', 
                                                                      child_feed_id) 

        await self.activities.migrate_child_entries('feeds_tags_map', 'feeds_tags_map_id', child_feeds_tags_map,
                                                    child_feed_id, parent_feed_id)

        await self.activities.delete_child_entries(child_feed_id, 'downloads')

        await self.activities.delete_child_entries(child_feed_id, 'feeds_stories_map')

        await self.activities.delete_child_entries(child_feed_id, 'scraped_feeds')

        await self.activities.delete_child_entries(child_feed_id, 'feeds_from_yesterday')

        await self.activities.delete_child_entries(child_feed_id, 'feeds_tags_map')

        await self.activities.delete_child_entries(child_feed_id, 'feeds')
