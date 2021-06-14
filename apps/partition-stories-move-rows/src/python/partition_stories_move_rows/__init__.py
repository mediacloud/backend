"""
Workflow that gradually moves rows from "stories_unpartitioned" to "stories_partitioned".
"""

from datetime import timedelta

# noinspection PyPackageRequirements
from temporal.activity_method import activity_method, RetryParameters
# noinspection PyPackageRequirements
from temporal.workflow import workflow_method, Workflow

from mediawords.db import connect_to_db_or_raise
from mediawords.util.log import create_logger

log = create_logger(__name__)

TASK_QUEUE = "partition-stories-move-rows"

DEFAULT_RETRY_PARAMETERS = RetryParameters(
    initial_interval=timedelta(seconds=1),
    backoff_coefficient=2,
    maximum_interval=timedelta(hours=2),
    maximum_attempts=1000,
    non_retryable_error_types=[],
)


class MoveRowsActivities(object):

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=60),
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def max_stories_id(self) -> int:
        """
        Get the biggest "stories_id" from "stories_unpartitioned".
        :return: Biggest "stories_id" from "stories_unpartitioned".
        """
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(hours=2),  # Might take a while, hope this is enough
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def move_chunk_of_stories(self, start_stories_id: int, end_stories_id: int) -> None:
        """
        Move a chunk of stories from "stories_unpartitioned" to "stories_partitioned".

        :param start_stories_id: Starting story ID to move.
        :param end_stories_id: Ending story ID to move (inclusive).
        """
        raise NotImplementedError


class MoveRowsWorkflow(object):

    @workflow_method(task_queue=TASK_QUEUE)
    async def move_rows(self) -> None:
        """
        Move all rows from "stories_unpartitioned" to "stories_partitioned".
        """
        raise NotImplementedError


# noinspection SqlResolve
class MoveRowsActivitiesImpl(MoveRowsActivities):

    async def max_stories_id(self) -> int:
        log.info("Determining max. story ID...")

        db = connect_to_db_or_raise()

        max_stories_id = db.query("""
            SELECT MAX(stories_id)
            FROM stories_unpartitioned
        """).flat()[0]

        log.info(f"Max. story ID: {max_stories_id}")

        return max_stories_id

    async def move_chunk_of_stories(self, start_stories_id: int, end_stories_id: int) -> None:
        log.info(f"Moving stories between {start_stories_id} and {end_stories_id}...")

        db = connect_to_db_or_raise()

        db.query("""
            WITH rows_to_move AS (
                DELETE FROM stories_unpartitioned
                WHERE stories_id IN (
                    SELECT stories_id
                    FROM stories_unpartitioned
                    WHERE stories_id BETWEEN %(start_stories_id)s AND %(end_stories_id)s
                )
                RETURNING stories_unpartitioned.*
            )
            INSERT INTO stories_partitioned (
                stories_id,
                media_id,
                url,
                guid,
                title,
                normalized_title_hash,
                description,
                publish_date,
                collect_date,
                full_text_rss,
                language
            )
                SELECT
                    stories_id::bigint,
                    media_id,
                    url::text,
                    guid::text,
                    title,
                    normalized_title_hash,
                    description,
                    publish_date,
                    collect_date,
                    full_text_rss,
                    language
                FROM rows_to_move
        """)

        log.info(f"Moved stories between {start_stories_id} and {end_stories_id}...")


class MoveRowsWorkflowImpl(object):

    def __init__(self):
        self.activities: MoveRowsActivities = Workflow.new_activity_stub(activities_cls=MoveRowsActivities)

    async def move_rows(self) -> None:
        max_stories_id = await self.activities.max_stories_id()

        # We can have up to about 1000 activity invocations in a single workflow (a few less or more shouldn't be an
        # issue) so split the stories_id space into 1000 chunks and copy each chunk separately
        max_chunk_count = 1000
        chunk_size = max(int(max_stories_id / max_chunk_count), 1)

        # Iterator is a bit off here, but copying nonexistent stories is fine as long as we cover them all
        for start_stories_id in range(0, max_stories_id + chunk_size, chunk_size):
            end_stories_id = start_stories_id + chunk_size - 1
            await self.activities.move_chunk_of_stories(start_stories_id, end_stories_id)
