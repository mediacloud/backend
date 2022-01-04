from datetime import timedelta
from typing import List, Optional

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
        # If we need to rerun everything, min. value might take a while to find
        # because we'll be skipping a bunch of dead tuples
        start_to_close_timeout=timedelta(hours=2),
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def min_column_value(self, table: str, id_column: str) -> Optional[int]:
        """
        Return smallest value of a column in a table.

        :param table: Table name with schema, e.g. "unsharded_public.stories".
        :param id_column: Column name, e.g. "stories_id".
        :return Smallest value of a column in a table, or None if table is empty.
        """
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        # If we need to rerun everything, max. value might take a while to find
        # because we'll be skipping a bunch of dead tuples
        start_to_close_timeout=timedelta(hours=2),
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def max_column_value(self, table: str, id_column: str) -> Optional[int]:
        """
        Return biggest value of a column in a table.

        :param table: Table name with schema, e.g. "unsharded_public.stories".
        :param id_column: Column name, e.g. "stories_id".
        :return Biggest value of a column in a table, or None if table is empty.
        """
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        # We should be able to hopefully move at least a chunk every 36 hours
        start_to_close_timeout=timedelta(hours=36),
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def run_queries_in_transaction(self, sql_queries: List[str]) -> None:
        """
        Execute a list of SQL queries in a transaction in order to move a chunk of rows.

        Transaction won't be started if only one SQL query is to be run.

        :param sql_queries: One or more SQL queries to execute in a transaction.
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
