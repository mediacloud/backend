import os
import tempfile
from typing import Optional

# noinspection PyPackageRequirements
from temporal.workflow import Workflow

from mediawords.db import connect_to_db_or_raise
from mediawords.util.parse_json import encode_json, decode_json
from mediawords.util.log import create_logger
from mediawords.workflow.exceptions import McProgrammingError, McTransientError, McPermanentError

from .workflow_interface import MoveRowsToShardsWorkflow, MoveRowsToShardsActivities

log = create_logger(__name__)


class MoveRowsToShardsActivitiesImpl(MoveRowsToShardsActivities):
    """Activities implementation."""

    async def identify_story_bcp47_language_code(self, stories_id: int) -> Optional[str]:
        log.info(f"Identifying story language for story {stories_id}...")

        db = connect_to_db_or_raise()

        story = db.find_by_id(table='stories', object_id=stories_id)
        if not story:
            raise McPermanentError(f"Story {stories_id} was not found.")

        return bcp_47_language_code


class MoveRowsToShardsWorkflowImpl(MoveRowsToShardsWorkflow):
    """Workflow implementation."""

    def __init__(self):
        self.activities: MoveRowsToShardsActivities = Workflow.new_activity_stub(
            activities_cls=MoveRowsToShardsActivities,
            # No retry_parameters here as they get set individually in @activity_method()
        )

    async def move_rows_to_shards(self) -> None:

        bcp47_language_code = await self.activities.identify_story_bcp47_language_code(stories_id)
        if bcp47_language_code is None:
            # Default to English in case there wasn't enough sizable text in title / description to make a good guess
            bcp47_language_code = 'en'
