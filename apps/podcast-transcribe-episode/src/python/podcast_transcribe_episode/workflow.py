# noinspection PyPackageRequirements
from typing import Optional

# noinspection PyPackageRequirements
from mediawords.util.identify_language import identification_would_be_reliable, language_code_for_text
from mediawords.util.parse_html import html_strip
from .fetch_episode.enclosure import podcast_viable_enclosure_for_story, MAX_ENCLOSURE_SIZE, StoryEnclosure

from .exceptions import SoftException
from temporal.workflow import Workflow

from mediawords.db import connect_to_db

from .fetch_episode.bcp47_lang import iso_639_1_code_to_bcp_47_identifier

from .shared import (
    AbstractPodcastTranscribeWorkflow,
    AbstractPodcastTranscribeActivities,
    RETRY_PARAMETERS,
)


# FIXME in the example the activities implementation *was not* inheriting from the interface
class PodcastTranscribeActivities(AbstractPodcastTranscribeActivities):
    """Activities implementation."""

    async def identify_story_bcp47_language_code(self, stories_id: int) -> Optional[str]:
        try:
            db = connect_to_db()
        except Exception as ex:
            raise SoftException(f"Unable to connect to the database: {ex}")

        try:
            story = db.find_by_id(table='stories', object_id=stories_id)
        except Exception as ex:
            raise SoftException(f"Database failed when fetching story {stories_id}: {ex}")

        if not story:
            raise SoftException(f"Story {stories_id} was not found.")

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

        return bcp_47_language_code

    async def determine_best_enclosure(self, stories_id: int) -> Optional[StoryEnclosure]:

        try:
            db = connect_to_db()
        except Exception as ex:
            raise SoftException(f"Unable to connect to the database: {ex}")

        # Find the enclosure that might work the best
        best_enclosure = podcast_viable_enclosure_for_story(db=db, stories_id=stories_id)
        if not best_enclosure:
            # FIXME possibly return None here?
            raise SoftException(f"There were no viable enclosures found for story {stories_id}")

        if best_enclosure.length:
            if best_enclosure.length > MAX_ENCLOSURE_SIZE:
                # FIXME possibly return None here?
                raise SoftException(f"Chosen enclosure {best_enclosure} is too big.")

        return best_enclosure


class PodcastTranscribeWorkflow(AbstractPodcastTranscribeWorkflow):
    """Workflow implementation."""

    def __init__(self):
        self.activities: AbstractPodcastTranscribeActivities = Workflow.new_activity_stub(
            activities_cls=AbstractPodcastTranscribeActivities,
            retry_parameters=RETRY_PARAMETERS,
        )

    async def transcribe_episode(self, stories_id: int) -> None:

        bcp47_language_code = await self.activities.identify_story_bcp47_language_code(stories_id=stories_id)
        if bcp47_language_code is None:
            # Default to English in case there wasn't enough sizable text in title / description to make a good guess
            bcp47_language_code = 'en'

        enclosure = await self.activities.determine_best_enclosure(stories_id=stories_id)
        if not enclosure:
            # FIXME what do we do if there's no viable enclosure? Nothing?
            return

        await self.activities.fetch_enclosure_to_gcs(stories_id=stories_id, enclosure=enclosure)

        episode_metadata = await self.activities.fetch_transcode_store_episode(stories_id=stories_id)

        # FIXME we probably want to test the metadata here, e.g. whether it's set at all or if the duration is right

        speech_operation_id = await self.activities.submit_transcribe_operation(
            stories_id=stories_id,
            episode_metadata=episode_metadata,
            bcp47_language_code=bcp47_language_code,
        )

        await Workflow.sleep(int(episode_metadata.duration * 1.1))

        # FIXME get the retries right here
        # FIXME if the operation with a given ID is not found, re-submit the transcription operation
        await self.activities.fetch_store_raw_transcript_json(
            stories_id=stories_id,
            speech_operation_id=speech_operation_id,
        )

        await self.activities.fetch_store_transcript(stories_id=stories_id)
