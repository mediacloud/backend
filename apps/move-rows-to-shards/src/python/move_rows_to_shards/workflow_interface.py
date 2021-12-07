from datetime import timedelta
from typing import List

# noinspection PyPackageRequirements
from temporal.activity_method import activity_method, RetryParameters
# noinspection PyPackageRequirements
from temporal.workflow import workflow_method

from mediawords.workflow.exceptions import McPermanentError

TASK_QUEUE = "move-rows-to-shards"
"""Temporal task queue."""

DEFAULT_RETRY_PARAMETERS = RetryParameters(
    initial_interval=timedelta(seconds=1),
    backoff_coefficient=2,
    maximum_interval=timedelta(hours=2),
    maximum_attempts=1000,
    non_retryable_error_types=[
        McPermanentError.__name__,
    ],
)


class MoveRowsToShardsActivities(object):

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(minutes=1),
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def min_column_value(self, table: str, id_column: str) -> int:
        """
        Return smallest value of a column in a table.

        :param table: Table name with schema, e.g. "unsharded_public.stories".
        :param id_column: Column name, e.g. "stories_id".
        :return Smallest value of a column in a table.
        """
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(minutes=1),
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def max_column_value(self, table: str, id_column: str) -> int:
        """
        Return biggest value of a column in a table.

        :param table: Table name with schema, e.g. "unsharded_public.stories".
        :param id_column: Column name, e.g. "stories_id".
        :return Biggest value of a column in a table.
        """
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        # We should be able to hopefully move at least a chunk a day
        start_to_close_timeout=timedelta(days=1),
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def move_chunk_of_rows(self,
                                 src_table: str,
                                 src_columns: List[str],
                                 src_id_column: str,
                                 src_id_start: int,
                                 src_id_end: int,
                                 src_extra_using_clause: str,
                                 src_extra_where_clause: str,
                                 dst_table: str,
                                 dst_columns: List[str],
                                 dst_extra_on_conflict_clause: str) -> None:
        """
        Move a chunk of rows from the source table to the destination one, with the triggers being disabled.

        :param src_table: Source table to move the rows from, with schema, e.g. "unsharded_public.stories".
        :param src_columns: List of columns to move from the source table, e.g. ["stories_id", "url", ...].
        :param src_id_column: Indexed column in the source table to use for chunking, e.g. "stories_id".
        :param src_id_start: Start of the chunk to limit "src_id_column"'s value to, e.g. 1_000_000.
        :param src_id_end: End of the chunk to limit "src_id_column"'s value to, e.g. 2_000_000.
        :param src_extra_using_clause: Extra USING clause to add to the DELETE statement; useful when one of the columns
            to be INSERTed into the destination table needs to come from another table that's to be joined with USING.
        :param src_extra_where_clause: Extra WHERE clause to add to the DELETE statement; useful when using DELETE ...
            USING (to do the actual join) or when some other condition is needed to be applied to DELETE.
        :param dst_table: Destination table to move the rows to, with schema, e.g. "sharded_public.stories".
        :param dst_columns: List of columns to move to the destination table, with casts if needed,
            e.g. ["stories_id::BIGINT", "url::TEXT", ...].
        :param dst_extra_on_conflict_clause: Extra ON CONFLICT clause to use when INSERTing rows into destination table.
        """
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        # Making sure that the table is empty might take a while; plus, if TRUNCATE doesn't manage to complete in the
        # allotted time, that probably means it has locked out somewhere and that we should retry instead of waiting
        start_to_close_timeout=timedelta(hours=2),
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def truncate_if_empty(self, table: str) -> None:
        """
        TRUNCATE a table if it's empty, i.e. there are no more live tuples left in that table.

        :param table: Name of a table to truncate with schema, e.g. "unsharded_public.stories".
        """
        raise NotImplementedError


class MoveRowsToShardsWorkflow(object):
    """Workflow interface."""

    @workflow_method(task_queue=TASK_QUEUE)
    async def move_rows_to_shards(self) -> None:
        raise NotImplementedError
