import dataclasses
from typing import List

# noinspection PyPackageRequirements
from google.api_core.exceptions import InvalidArgument, NotFound
# noinspection PyPackageRequirements
from google.api_core.operation import from_gapic
# noinspection PyPackageRequirements
from google.api_core.operations_v1 import OperationsClient
# noinspection PyPackageRequirements
from google.cloud.speech_v1p1beta1 import SpeechClient
# noinspection PyPackageRequirements
from google.cloud.speech_v1p1beta1.proto import cloud_speech_pb2

from podcast_fetch_transcript.config import PodcastFetchTranscriptConfig

from podcast_fetch_transcript.exceptions import (
    McMisconfiguredSpeechAPIException,
    McOperationNotFoundException,
)


@dataclasses.dataclass
class TranscriptAlternative(object):
    text: str
    """Transcript text."""

    confidence: float
    """How confident Speech API is that it got it right."""


@dataclasses.dataclass
class Transcript(object):
    alternatives: List[TranscriptAlternative]
    """Alternative transcripts, ordered from best to worst."""

    bcp47_language_code: str
    """BCP 47 language code; might be different from what we've passed as the input."""

    @property
    def best_alternative(self) -> TranscriptAlternative:
        return self.alternatives[0]


def fetch_speech_api_transcripts(speech_operation_id: str) -> List[Transcript]:
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

    transcripts = []

    try:
        for result in gapic_operation.result().results:

            alternatives = []
            for alternative in result.alternatives:
                alternatives.append(
                    TranscriptAlternative(
                        text=alternative.transcript,
                        confidence=alternative.confidence,
                    )
                )

            transcripts.append(
                Transcript(
                    alternatives=alternatives,
                    bcp47_language_code=result.language_code,
                )
            )

    except Exception as ex:
        raise McMisconfiguredSpeechAPIException(f"Unable to read transcript: {ex}")

    return transcripts
