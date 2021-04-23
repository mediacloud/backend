# FIXME upload transcriptions directly to GCS once that's no longer a demo feature:
# https://cloud.google.com/speech-to-text/docs/async-recognize#speech_transcribe_async_gcs-python

from typing import Optional

# noinspection PyPackageRequirements
from google.api_core.exceptions import InvalidArgument, NotFound
# noinspection PyPackageRequirements
from google.api_core.operation import from_gapic, Operation
# noinspection PyPackageRequirements
from google.api_core.retry import Retry
# noinspection PyPackageRequirements
from google.cloud.speech_v1p1beta1 import (
    SpeechClient, RecognitionConfig, RecognitionAudio, LongRunningRecognizeResponse, LongRunningRecognizeMetadata,
)

from mediawords.util.log import create_logger

from .transcript import Transcript, UtteranceAlternative, Utterance
from .config import GCAuthConfig
from .exceptions import (
    McPodcastMisconfiguredSpeechAPIException,
    McPodcastSpeechAPIRequestFailedException,
    McMisconfiguredSpeechAPIException,
    HardException,
)
from .media_info import MediaFileInfoAudioStream

log = create_logger(__name__)

# Speech API sometimes throws:
#
#   google.api_core.exceptions.ServiceUnavailable: 503 failed to connect to all addresses
#
# so let it retry for 10 minutes or so.
_GOOGLE_API_RETRIES = Retry(initial=5, maximum=60, multiplier=2, deadline=60 * 10)
"""Google Cloud API's own retry policy."""


def submit_transcribe_operation(gs_uri: str,
                                episode_metadata: MediaFileInfoAudioStream,
                                bcp47_language_code: str) -> str:
    """
    Submit a Speech API long running operation to transcribe a podcast episode.

    :param gs_uri: Google Cloud Storage URI to a transcoded episode.
    :param episode_metadata: Metadata derived from the episode while transcoding it.
    :param bcp47_language_code: Episode's BCP 47 language code guessed from story's title + description.
    :return Google Speech API operation ID by which the transcription operation can be referred to.
    """

    auth_config = GCAuthConfig()

    try:
        client = SpeechClient.from_service_account_json(auth_config.gc_auth_json_file())
    except Exception as ex:
        raise McPodcastMisconfiguredSpeechAPIException(f"Unable to create Speech API client: {ex}")

    try:
        # noinspection PyTypeChecker
        config = RecognitionConfig(
            encoding=RecognitionConfig.AudioEncoding(episode_metadata.audio_codec_class.speech_api_codec()),
            sample_rate_hertz=episode_metadata.sample_rate,
            # We always set the channel count to 1 and disable separate recognition per channel as our inputs are all
            # mono audio files and do not have separate speakers per audio channel.
            audio_channel_count=1,
            enable_separate_recognition_per_channel=False,
            language_code=bcp47_language_code,
            alternative_language_codes=[
                # FIXME add all Chinese variants
                # FIXME add Mexican Spanish variants
            ],

            speech_contexts=[
                # Speech API works pretty well without custom contexts
            ],
            # Don't care that much about word confidence
            enable_word_confidence=False,
            # Punctuation doesn't work that well but we still enable it here
            enable_automatic_punctuation=True,
            # Not setting 'model' as 'use_enhanced' will then choose the best model for us
            # Using enhanced (more expensive) model, where available
            use_enhanced=True,
        )
    except Exception as ex:
        raise McPodcastMisconfiguredSpeechAPIException(f"Unable to initialize Speech API configuration: {ex}")

    log.info(f"Submitting a Speech API operation for URI {gs_uri}...")

    try:

        # noinspection PyTypeChecker
        audio = RecognitionAudio(uri=gs_uri)

        speech_operation = client.long_running_recognize(config=config, audio=audio, retry=_GOOGLE_API_RETRIES)

    except Exception as ex:
        raise McPodcastSpeechAPIRequestFailedException(f"Unable to submit a Speech API operation: {ex}")

    try:
        # We get the operation name in a try-except block because accessing it is not that well documented, so Google
        # might change the property names whenever they please and we wouldn't necessarily notice otherwise
        operation_id = speech_operation.operation.name
        if not operation_id:
            raise McPodcastMisconfiguredSpeechAPIException(f"Operation name is empty.")
    except Exception as ex:
        raise McPodcastMisconfiguredSpeechAPIException(f"Unable to get operation name: {ex}")

    log.info(f"Submitted Speech API operation for URI {gs_uri}")

    return operation_id


def fetch_transcript(speech_operation_id: str) -> Optional[Transcript]:
    """
    Try to fetch a transcript for a given speech operation ID.

    :param speech_operation_id: Speech operation ID.
    :return: Transcript, or None if the transcript hasn't been prepared yet.
    """
    if not speech_operation_id:
        raise McMisconfiguredSpeechAPIException(f"Speech operation ID is unset.")

    auth_config = GCAuthConfig()

    try:
        client = SpeechClient.from_service_account_json(auth_config.gc_auth_json_file())
    except Exception as ex:
        raise McMisconfiguredSpeechAPIException(f"Unable to initialize Speech API operations client: {ex}")

    try:
        operation = client.transport.operations_client.get_operation(
            name=speech_operation_id,
            retry=_GOOGLE_API_RETRIES,
        )
    except InvalidArgument as ex:
        raise McMisconfiguredSpeechAPIException(f"Invalid operation ID '{speech_operation_id}': {ex}")
    except NotFound as ex:
        # FIXME we should be resubmitting the media file for a new transcript when that happens
        raise HardException(f"Operation ID '{speech_operation_id}' was not found: {ex}")
    except Exception as ex:
        # On any other errors, raise a hard exception
        raise McMisconfiguredSpeechAPIException(f"Error while fetching operation ID '{speech_operation_id}': {ex}")

    if not operation:
        raise McMisconfiguredSpeechAPIException(f"Operation is unset.")

    try:
        gapic_operation: Operation = from_gapic(
            operation=operation,
            operations_client=client.transport.operations_client,
            result_type=LongRunningRecognizeResponse,
            metadata_type=LongRunningRecognizeMetadata,
            retry=_GOOGLE_API_RETRIES,
        )
    except Exception as ex:
        raise McMisconfiguredSpeechAPIException(f"Unable to create GAPIC operation: {ex}")

    log.debug(f"GAPIC operation: {gapic_operation}")
    log.debug(f"Operation metadata: {gapic_operation.metadata}")
    log.debug(f"Operation is done: {gapic_operation.done()}")
    log.debug(f"Operation error: {gapic_operation.done()}")

    try:
        operation_is_done = gapic_operation.done(retry=_GOOGLE_API_RETRIES)
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
        for result in gapic_operation.result(retry=_GOOGLE_API_RETRIES).results:

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

    except Exception as ex:
        raise HardException(
            f"Unable to read transcript for operation '{speech_operation_id}' due to other error: {ex}"
        )

    return Transcript(utterances=utterances)
