# FIXME remove unused tables (including migrations)
# FIXME post-init validation of dataclasses (https://docs.python.org/3/library/dataclasses.html#post-init-processing)
# FIXME workflow logger
# FIXME if something's wrong (e.g. the episode doesn't look valid), should the workflow succeed or fail?
# FIXME remove "Podcast(Transcribe)..." prefix from everywhere
# FIXME transient vs non-transient errors
# FIXME increase retries and timeouts
# FIXME what if one or more configuration environment variables are unset?
# FIXME clean up exceptions

import dataclasses
from datetime import timedelta
from typing import Optional

# noinspection PyPackageRequirements
from temporal.activity_method import activity_method, RetryParameters
# noinspection PyPackageRequirements
from temporal.workflow import workflow_method

from .exceptions import HardException
from .enclosure import StoryEnclosure
from .media_info import MediaFileInfoAudioStream

TASK_QUEUE = "podcast-transcribe-episode"
"""Temporal task queue."""

NAMESPACE = "default"
"""Temporal namespace."""

DEFAULT_RETRY_PARAMETERS = RetryParameters(

    # InitialInterval is a delay before the first retry.
    initial_interval=timedelta(seconds=1),

    # BackoffCoefficient. Retry policies are exponential. The coefficient specifies how fast the retry interval is
    # growing. The coefficient of 1 means that the retry interval is always equal to the InitialInterval.
    backoff_coefficient=2,

    # MaximumInterval specifies the maximum interval between retries. Useful for coefficients more than 1.
    maximum_interval=timedelta(hours=2),

    # MaximumAttempts specifies how many times to attempt to execute an Activity in the presence of failures. If this
    # limit is exceeded, the error is returned back to the Workflow that invoked the Activity.
    maximum_attempts=50,

    # NonRetryableErrorReasons allows you to specify errors that shouldn't be retried. For example retrying invalid
    # arguments error doesn't make sense in some scenarios.
    # FIXME test if it actually works
    non_retryable_error_types=[HardException.__name__],

)
"""
Retry parameters.

https://docs.temporal.io/docs/concept-activities/
"""


class AbstractPodcastTranscribeActivities(object):
    """Activities interface."""

    # FIXME timeouts and retries of every action

    @activity_method(
        task_queue=TASK_QUEUE,

        # ScheduleToStart is the maximum time from a Workflow requesting Activity execution to a worker starting its
        # execution. The usual reason for this timeout to fire is all workers being down or not being able to keep up
        # with the request rate. We recommend setting this timeout to the maximum time a Workflow is willing to wait for
        # an Activity execution in the presence of all possible worker outages.
        # schedule_to_start_timeout=None,

        # StartToClose is the maximum time an Activity can execute after it was picked by a worker.
        start_to_close_timeout=timedelta(seconds=60),

        # ScheduleToClose is the maximum time from the Workflow requesting an Activity execution to its completion.
        # schedule_to_close_timeout=None,

        # Heartbeat is the maximum time between heartbeat requests. See Long Running Activities.
        # (https://docs.temporal.io/docs/concept-activities/#long-running-activities)
        # heartbeat_timeout=None,

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

    @activity_method(
        task_queue=TASK_QUEUE,
        # schedule_to_start_timeout=None,
        start_to_close_timeout=timedelta(seconds=60),
        # schedule_to_close_timeout=None,
        # heartbeat_timeout=None,
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def determine_best_enclosure(self, stories_id: int) -> Optional[StoryEnclosure]:
        """
        Fetch a list of story enclosures, determine which one looks like a podcast episode the most.

        Uses <enclosure /> or similar tag.

        :param stories_id: Story to fetch the enclosures for.
        :return: Best enclosure metadata object, or None if no best enclosure could be determined.
        """
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        # schedule_to_start_timeout=None,

        # With a super-slow server, it's probably reasonable to expect that it might take a few hours to fetch a single
        # episode
        start_to_close_timeout=timedelta(hours=2),

        # schedule_to_close_timeout=None,

        # FIXME add heartbeats for such a long running process
        # heartbeat_timeout=None,

        retry_parameters=dataclasses.replace(
            DEFAULT_RETRY_PARAMETERS,

            # Wait for a minute before trying again
            initial_interval=timedelta(minutes=1),

            # Hope for the server to resurrect in a week
            maximum_interval=timedelta(weeks=1),

            # Don't kill ourselves trying to hit a permanently dead server
            maximum_attempts=50,
        ),
    )
    async def fetch_enclosure_to_gcs(self, stories_id: int, enclosure: StoryEnclosure) -> None:
        """
        Fetch enclosure and store it to GCS as an episode.

        Doesn't do transcoding or anything because transcoding or any subsequent steps might fail, and if they do, we
        want to have the raw episode fetched and safely stored somewhere.

        :param stories_id: Story to fetch the enclosure for.
        :param enclosure: Enclosure to fetch.
        """
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        # schedule_to_start_timeout=None,

        # Let's expect super long episodes or super slow servers
        start_to_close_timeout=timedelta(hours=2),

        # schedule_to_close_timeout=None,

        # FIXME transcoding could use a timeout as well
        # heartbeat_timeout=None,

        retry_parameters=dataclasses.replace(
            DEFAULT_RETRY_PARAMETERS,

            # Wait for a minute before trying again (GCS might be down)
            initial_interval=timedelta(minutes=1),

            # Hope for GCS to resurrect in a day
            maximum_interval=timedelta(days=1),

            # Limit attempts because transcoding itself might be broken, and we don't want to be fetching huge objects
            # from GCS periodically
            maximum_attempts=20,
        ),
    )
    async def fetch_transcode_store_episode(self, stories_id: int) -> MediaFileInfoAudioStream:
        """
        Fetch episode from GCS, transcode it if needed and store it to GCS again in a separate bucket.

        Now that the raw episode file is safely located in GCS, we can try transcoding it.

        :param stories_id: Story ID the episode of which should be transcoded.
        :return: Metadata of the best audio stream determined as part of the transcoding.
        """
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        # schedule_to_start_timeout=None,

        # Give a bit more time as the implementation is likely to do some non-Temporal retries on weird Speech API
        # errors
        start_to_close_timeout=timedelta(minutes=5),

        # schedule_to_close_timeout=None,
        # heartbeat_timeout=None,

        retry_parameters=dataclasses.replace(
            DEFAULT_RETRY_PARAMETERS,

            # Given that the thing is costly, wait a whole hour before retrying anything
            initial_interval=timedelta(hours=1),

            # Hope for the Speech API to resurrect in a week
            maximum_interval=timedelta(weeks=1),

            # Don't retry too much as each try is potentially very costly
            maximum_attempts=10,
        ),
    )
    async def submit_transcribe_operation(self,
                                          stories_id: int,
                                          episode_metadata: MediaFileInfoAudioStream,
                                          bcp47_language_code: str) -> str:
        """
        Submit a long-running transcription operation to the Speech API.

        :param stories_id: Story ID of the episode which should be submitted for transcribing.
        :param episode_metadata: Metadata of transcoded episode.
        :param bcp47_language_code: BCP 47 language code of the story.
        :return: Speech API operation ID for the transcription operation.
        """
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        # schedule_to_start_timeout=None,
        start_to_close_timeout=timedelta(seconds=60),
        # schedule_to_close_timeout=None,
        # heartbeat_timeout=None,
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def fetch_store_raw_transcript_json(self, stories_id: int, speech_operation_id: str) -> None:
        """
        Fetch a finished transcription and store the raw JSON of it into a GCS bucket.

        Raises an exception if the transcription operation is not finished yet.

        :param stories_id: Story ID the episode of which should be submitted for transcribing.
        :param speech_operation_id: Speech API operation ID.
        """
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        # schedule_to_start_timeout=None,
        start_to_close_timeout=timedelta(seconds=60),
        # schedule_to_close_timeout=None,
        # heartbeat_timeout=None,
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def fetch_store_transcript(self, stories_id: int) -> None:
        """
        Fetch a raw JSON transcript from a GCS bucket, store it to "download_texts".

        :param stories_id: Story ID the transcript of which should be stored into the database.
        """
        raise NotImplementedError

    @activity_method(
        task_queue=TASK_QUEUE,
        # schedule_to_start_timeout=None,

        # FIXME add timeout to add_to_queue() otherwise it will wait indefinitely
        start_to_close_timeout=timedelta(minutes=2),

        # schedule_to_close_timeout=None,
        # heartbeat_timeout=None,
        retry_parameters=DEFAULT_RETRY_PARAMETERS,
    )
    async def add_to_extraction_queue(self, stories_id: int) -> None:
        """
        Add a story to the extraction queue.

        :param stories_id: Story ID to be added to the extraction queue.
        """
        raise NotImplementedError


class AbstractPodcastTranscribeWorkflow(object):
    """Workflow interface."""

    @workflow_method(task_queue=TASK_QUEUE)
    async def transcribe_episode(self, stories_id: int) -> None:
        raise NotImplementedError