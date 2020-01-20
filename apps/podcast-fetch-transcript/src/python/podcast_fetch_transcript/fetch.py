import dataclasses
from typing import List, Optional

# noinspection PyPackageRequirements
from google.api_core.exceptions import InvalidArgument, NotFound, GoogleAPICallError
# noinspection PyPackageRequirements
from google.api_core.operation import from_gapic
# noinspection PyPackageRequirements
from google.api_core.operations_v1 import OperationsClient
# noinspection PyPackageRequirements
from google.cloud.speech_v1p1beta1 import SpeechClient
# noinspection PyPackageRequirements
from google.cloud.speech_v1p1beta1.proto import cloud_speech_pb2

from mediawords.util.log import create_logger

from podcast_fetch_transcript.config import PodcastFetchTranscriptConfig

from podcast_fetch_transcript.exceptions import (
    McMisconfiguredSpeechAPIException,
    McOperationNotFoundException,
    McTranscriptionReturnedErrorException,
)

log = create_logger(__name__)


@dataclasses.dataclass
class UtteranceAlternative(object):
    """One of the alternatives of what might have been said in an utterance."""

    text: str
    """Utterance text."""

    confidence: float
    """How confident Speech API is that it got it right."""


@dataclasses.dataclass
class Utterance(object):
    """A single transcribed utterance (often but not always a single sentence)."""

    alternatives: List[UtteranceAlternative]
    """Alternatives of what might have been said in an utterance, ordered from the best to the worst guess."""

    bcp47_language_code: str
    """BCP 47 language code; might be different from what we've passed as the input."""

    @property
    def best_alternative(self) -> UtteranceAlternative:
        """Return best alternative for what might have been said in an utterance."""
        return self.alternatives[0]


@dataclasses.dataclass
class Transcript(object):
    """A single transcript."""

    utterances: List[Utterance]
    """List of ordered utterances in a transcript."""


def fetch_transcript(speech_operation_id: str) -> Optional[Transcript]:
    """
    Attempt fetching a Speech API transcript for a given operation ID.

    :param speech_operation_id: Speech API operation ID.
    :return: None if transcript is not finished yet, a Transcript object otherwise.
    """
    try:
        config = PodcastFetchTranscriptConfig()
        client = SpeechClient.from_service_account_json(config.gc_auth_json_file())
        operations_client = OperationsClient(channel=client.transport.channel)
    except Exception as ex:
        raise McMisconfiguredSpeechAPIException(f"Unable to initialize Speech API operations client: {ex}")

    try:
        operation = operations_client.get_operation(name=speech_operation_id)
    except InvalidArgument as ex:
        raise McMisconfiguredSpeechAPIException(f"Invalid operation ID '{speech_operation_id}': {ex}")
    except NotFound as ex:
        raise McOperationNotFoundException(f"Operation ID '{speech_operation_id}' was not found: {ex}")
    except Exception as ex:
        # On any other errors, raise a hard exception
        raise McMisconfiguredSpeechAPIException(f"Error while fetching operation ID '{speech_operation_id}': {ex}")

    if not operation:
        raise McMisconfiguredSpeechAPIException(f"Operation is unset.")

    try:
        gapic_operation = from_gapic(
            operation,
            operations_client,
            cloud_speech_pb2.LongRunningRecognizeResponse,
            metadata_type=cloud_speech_pb2.LongRunningRecognizeMetadata,
        )
    except Exception as ex:
        raise McMisconfiguredSpeechAPIException(f"Unable to create GAPIC operation: {ex}")

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
        raise McTranscriptionReturnedErrorException(
            f"Unable to read transcript for operation '{speech_operation_id}': {ex}"
        )

    except Exception as ex:
        raise McMisconfiguredSpeechAPIException(
            f"Unable to read transcript for operation '{speech_operation_id}': {ex}"
        )

    return Transcript(utterances=utterances)
