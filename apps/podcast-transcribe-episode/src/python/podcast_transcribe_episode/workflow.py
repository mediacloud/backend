import time

# noinspection PyPackageRequirements
from temporal.workflow import Workflow

from .shared import AbstractPodcastTranscribeWorkflow, AbstractPodcastTranscribeActivities, RETRY_PARAMETERS


# FIXME in the example the activities implementation *was not* inheriting from the interface
class PodcastTranscribeActivities(AbstractPodcastTranscribeActivities):
    """Activities implementation."""

    # noinspection PyMethodMayBeStatic
    async def compose_greeting(self, greeting: str, name: str, number: int):
        time.sleep(1)
        return f"{greeting} {name} number {number}!"


class PodcastTranscribeWorkflow(AbstractPodcastTranscribeWorkflow):
    """Workflow implementation."""

    def __init__(self):
        self.activities: AbstractPodcastTranscribeActivities = Workflow.new_activity_stub(
            activities_cls=AbstractPodcastTranscribeActivities,
            retry_parameters=RETRY_PARAMETERS,
        )

    async def transcribe_episode(self, stories_id: int) -> None:
        bcp47_language_code = await self.activities.identify_story_bcp47_language_code(stories_id=stories_id)

        enclosure = await self.activities.determine_best_enclosure(stories_id=stories_id)
        if not enclosure:
            # FIXME what do we do if there's no viable enclosure? Nothing?
            return

        await self.activities.fetch_store_enclosure(stories_id=stories_id, enclosure=enclosure)

        episode_metadata = await self.activities.fetch_transcode_store_episode(stories_id=stories_id)

        # FIXME we probably want to test the metadata here, e.g. whether it's set at all or if the duration is right

        speech_operation_id = await self.activities.submit_transcribe_operation(
            stories_id=stories_id,
            episode_metadata=episode_metadata,
            bcp47_language_code=bcp47_language_code,
        )

        await Workflow.sleep(int(episode_metadata.duration * 1.1))

        # FIXME get the retries right here
        await self.activities.fetch_store_raw_transcript_json(
            stories_id=stories_id,
            speech_operation_id=speech_operation_id,
        )

        await self.activities.fetch_store_transcript(stories_id=stories_id)
