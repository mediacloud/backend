import os
import tempfile
from typing import Optional

# noinspection PyPackageRequirements
from temporal.workflow import Workflow

from mediawords.db import connect_to_db_or_raise
from mediawords.job import JobBroker
from mediawords.util.parse_json import encode_json, decode_json
from mediawords.util.config.common import RabbitMQConfig
from mediawords.util.log import create_logger
from mediawords.workflow.exceptions import McProgrammingError, McTransientError, McPermanentError

from .feeds_workflow_interface import FeedsMergeWorkflow, FeedsMergeActivities

log = create_logger(__name__)


class FeedsMergeActivitiesImpl(FeedsMergeActivities):
    """Activities implementation."""

    async def

    async def identify_story_bcp47_language_code(self, stories_id: int) -> Optional[str]:
        log.info(f"Identifying story language for story {stories_id}...")

        db = connect_to_db_or_raise()

        story = db.find_by_id(table='stories', object_id=stories_id)
        if not story:
            raise McPermanentError(f"Story {stories_id} was not found.")

        # Podcast episodes typically come with title and description set so try guessing from that
        story_title = story['title']
        story_description = html_strip(story['description'])
        sample_text = f"{story_title}\n{story_description}"

        bcp_47_language_code = None
        if identification_would_be_reliable(text=sample_text):
            iso_639_1_language_code = language_code_for_text(text=sample_text)

            # Convert to BCP 47 identifier
            bcp_47_language_code = iso_639_1_code_to_bcp_47_identifier(
                iso_639_1_code=iso_639_1_language_code,
                url_hint=story['url'],
            )

        log.info(f"Language code for story {stories_id} is {bcp_47_language_code}")

        return bcp_47_language_code


        await self.activities.add_to_extraction_queue(stories_id)
