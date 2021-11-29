import dataclasses
from datetime import timedelta
from typing import Optional

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
        start_to_close_timeout=timedelta(seconds=60),
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def identify_story_bcp47_language_code(self, stories_id: int) -> Optional[str]:
        """
        Guess BCP 47 language code of a story.

        https://cloud.google.com/speech-to-text/docs/languages

        :param stories_id: Story to guess the language code for.
        :return: BCP 47 language code (e.g. 'en-US') or None if the language code could not be determined.
        """
        raise NotImplementedError


class MoveRowsToShardsWorkflow(object):
    """Workflow interface."""

    @workflow_method(task_queue=TASK_QUEUE)
    async def move_rows_to_shards(self) -> None:
        raise NotImplementedError
