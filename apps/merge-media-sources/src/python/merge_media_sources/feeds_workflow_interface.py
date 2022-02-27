from datetime import timedelta

# noinspection PyPackageRequirements
from temporal.activity_method import activity_method, RetryParameters
# noinspection PyPackageRequirements
from temporal.workflow import workflow_method

from mediawords.workflow.exceptions import McPermanentError


TASK_QUEUE = "merge-feeds"
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


class FeedsMergeActivities(object):
    """Activities interface."""

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=60),
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def migrate_child_entries(self, table: str, table_id_field: str, id_list: list, child_feed_id: int,
                                    parent_feed_id: int) -> None:
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        start_to_close_timeout=timedelta(seconds=60),
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def delete_child_entries(self, child_feed_id: int, table: str) -> None:
        raise NotImplementedError


class FeedsMergeWorkflow(object):
    """Workflow interface."""

    @workflow_method(task_queue=TASK_QUEUE)
    async def merge_feeds(self) -> None:
        raise NotImplementedError
