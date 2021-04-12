import abc
from typing import Optional

# noinspection PyPackageRequirements
from google.api_core.exceptions import InvalidArgument, NotFound, GoogleAPICallError
# noinspection PyPackageRequirements
from google.api_core.operation import from_gapic, Operation
# noinspection PyPackageRequirements
from google.api_core.operations_v1 import OperationsClient
# noinspection PyPackageRequirements
from google.cloud.speech_v1p1beta1 import SpeechClient, LongRunningRecognizeResponse, LongRunningRecognizeMetadata

from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads import create_download_for_new_story
from mediawords.dbi.downloads.store import store_content
from mediawords.util.log import create_logger

from ..config import PodcastTranscribeEpisodeConfig
from ..exceptions import (
    McDatabaseNotFoundException,
    McMisconfiguredSpeechAPIException,
    HardException, SoftException,
)
from .transcript import UtteranceAlternative, Utterance, Transcript

log = create_logger(__name__)


class AbstractHandler(object, metaclass=abc.ABCMeta):
    """
    Abstract class that fetches and stores a transcript.

    Useful for testing as we can create a mock class which pretends to do it.
    """

    @classmethod
    @abc.abstractmethod
    def fetch_transcript(cls, db: DatabaseHandler, podcast_episode_transcript_fetches_id: int) -> Optional[Transcript]:
        """
        Attempt fetching a Speech API transcript for a given operation ID.

        :param db: Database handler.
        :param podcast_episode_transcript_fetches_id: Transcript fetch attempt ID.
        :return: None if transcript is not finished yet, a Transcript object otherwise.
        """
        raise NotImplemented("Abstract method")

    @classmethod
    @abc.abstractmethod
    def store_transcript(cls, db: DatabaseHandler, transcript: Transcript) -> int:
        """
        Store transcript to raw download store.

        We could write this directly to "download_texts", but if we decide to reextract everything (after, say, updating
        an extractor), that "download_texts" row might disappear, so it's safer to just store a raw download on the
        key-value store as if it was a HTML file or something.

        :param db: Database handler.
        :param transcript: Transcript object.
        :return: Download ID for a download that was created.
        """
        raise NotImplemented("Abstract method")


class DefaultHandler(AbstractHandler):

    @classmethod
    def fetch_transcript(cls, db: DatabaseHandler, podcast_episode_transcript_fetches_id: int) -> Optional[Transcript]:
        transcript_fetch = db.find_by_id(
            table='podcast_episode_transcript_fetches',
            object_id=podcast_episode_transcript_fetches_id,
        )
        if not transcript_fetch:
            raise McDatabaseNotFoundException(
                f"Unable to find transcript fetch with ID {podcast_episode_transcript_fetches_id}"
            )
        podcast_episodes_id = transcript_fetch['podcast_episodes_id']

        episode = db.find_by_id(table='podcast_episodes', object_id=podcast_episodes_id)
        if not episode:
            raise McDatabaseNotFoundException(
                f"Unable to find podcast episode with ID {podcast_episodes_id}"
            )

        stories_id = episode['stories_id']
        speech_operation_id = episode['speech_operation_id']

        if not speech_operation_id:
            raise McMisconfiguredSpeechAPIException(f"Speech ID for podcast episode {podcast_episodes_id} is unset.")

        try:
            config = PodcastTranscribeEpisodeConfig()
            client = SpeechClient.from_service_account_json(config.gc_auth_json_file())
            operations_client = OperationsClient(channel=client._transport._grpc_channel)
        except Exception as ex:
            raise McMisconfiguredSpeechAPIException(f"Unable to initialize Speech API operations client: {ex}")

        try:
            operation = operations_client.get_operation(name=speech_operation_id)
        except InvalidArgument as ex:
            raise McMisconfiguredSpeechAPIException(f"Invalid operation ID '{speech_operation_id}': {ex}")
        except NotFound as ex:
            # Not a "hard" failure as sometimes these operations expire
            # FIXME although we should be resubmitting the media file for a new transcript when that happens
            raise SoftException(f"Operation ID '{speech_operation_id}' was not found: {ex}")
        except Exception as ex:
            # On any other errors, raise a hard exception
            raise McMisconfiguredSpeechAPIException(f"Error while fetching operation ID '{speech_operation_id}': {ex}")

        if not operation:
            raise McMisconfiguredSpeechAPIException(f"Operation is unset.")

        try:
            gapic_operation: Operation = from_gapic(
                operation,
                operations_client,
                LongRunningRecognizeResponse,
                metadata_type=LongRunningRecognizeMetadata,
            )
        except Exception as ex:
            raise McMisconfiguredSpeechAPIException(f"Unable to create GAPIC operation: {ex}")

        log.debug(f"GAPIC operation: {gapic_operation}")
        log.debug(f"Operation metadata: {gapic_operation.metadata}")
        log.debug(f"Operation is done: {gapic_operation.done()}")
        log.debug(f"Operation error: {gapic_operation.done()}")

        try:
            operation_is_done = gapic_operation.done()
        except Exception as ex:
            # 'done' attribute might be gone in a newer version of the Speech API client
            raise McMisconfiguredSpeechAPIException(
                f"Unable to test whether operation '{speech_operation_id}' is done: {ex}"
            )

        if not operation_is_done:
            log.info(f"Operation '{speech_operation_id}' is still not done.")
            return None

        utterances = []

        try:
            for result in gapic_operation.result().results:

                alternatives = []
                for alternative in result.alternatives:
                    alternatives.append(
                        UtteranceAlternative(
                            text=alternative.transcript.strip(),
                            confidence=alternative.confidence,
                        )
                    )

                utterances.append(
                    Utterance(
                        alternatives=alternatives,
                        bcp47_language_code=result.language_code,
                    )
                )

        except GoogleAPICallError as ex:
            # When Speech API returns with an error, it's unclear whether it was us who have messed up or something is
            # (temporarily) wrong on their end, so on the safe side we throw a "hard" exception.
            raise HardException(
                f"Unable to read transcript for operation '{speech_operation_id}' due to API error: {ex}"
            )

        except Exception as ex:
            raise HardException(
                f"Unable to read transcript for operation '{speech_operation_id}' due to other error: {ex}"
            )

        return Transcript(stories_id=stories_id, utterances=utterances)

    @classmethod
    def _download_text_from_transcript(cls, transcript: Transcript) -> str:
        best_utterance_alternatives = []
        for utterance in transcript.utterances:
            best_utterance_alternatives.append(utterance.best_alternative.text)
        text = "\n\n".join(best_utterance_alternatives)
        return text

    @classmethod
    def store_transcript(cls, db: DatabaseHandler, transcript: Transcript) -> int:
        story = db.find_by_id(table='stories', object_id=transcript.stories_id)

        feed = db.query("""
            SELECT *
            FROM feeds
            WHERE feeds_id = (
                SELECT feeds_id
                FROM feeds_stories_map
                WHERE stories_id = %(stories_id)s
            )
        """, {
            'stories_id': transcript.stories_id,
        }).hash()

        download = create_download_for_new_story(db=db, story=story, feed=feed)

        text = cls._download_text_from_transcript(transcript=transcript)

        # Store as a raw download and then let "extract-and-vector" app "extract" the stored text later
        store_content(db=db, download=download, content=text)

        return download['downloads_id']
