import os
import shutil
import tempfile

from mediawords.util.log import create_logger

from ..exceptions import McPodcastFileStoreFailureException, McPodcastFileFetchFailureException
from .enclosure import MAX_ENCLOSURE_SIZE, StoryEnclosure
from .fetch_url import fetch_big_file
from .gcs_store import GCSStore
from .media_file import TranscodeTempDirAndFile, transcode_media_file_if_needed, media_file_info

log = create_logger(__name__)


def _cleanup_temp_dir(temp: TranscodeTempDirAndFile) -> None:
    """Clean up temporary directory or raise a hard exception."""
    try:
        shutil.rmtree(temp.temp_dir)
    except Exception as ex:
        # Not being able to clean up after ourselves is a "hard" error as we might run out of disk space that way
        raise McPodcastFileStoreFailureException(f"Unable to remove temporary directory: {ex}")


def fetch_and_store_episode(stories_id: int, enclosure: StoryEnclosure) -> None:
    """
    Choose a viable story enclosure for podcast, fetch it, transcode if needed, and store to GCS.

    2) Fetches the chosen enclosure;
    3) Transcodes the file (if needed) by:
        a) converting it to an audio format that the Speech API can support, and / or
        b) discarding video stream from the media file, and / or
        c) discarding other audio streams from the media file;
    5) Reads the various parameters, e.g. sample rate, of the episode audio file;
    4) Uploads the episode audio file to Google Cloud Storage.

    :param stories_id: Story ID for the story to operate on.
    :param enclosure: Enclosure to fetch.
    """

    try:
        temp_dir = tempfile.mkdtemp('fetch_and_store')
    except Exception as ex:
        raise McPodcastFileStoreFailureException(f"Unable to create temporary directory: {ex}")

    # Fetch enclosure
    input_filename = 'input_file'
    input_file_path = os.path.join(temp_dir, input_filename)
    log.info(f"Fetching enclosure {enclosure} to {input_file_path}...")
    fetch_big_file(url=enclosure.url, dest_file=input_file_path, max_size=MAX_ENCLOSURE_SIZE)
    log.info(f"Done fetching enclosure {enclosure} to {input_file_path}")

    if os.stat(input_file_path).st_size == 0:
        # Might happen with misconfigured webservers
        raise McPodcastFileFetchFailureException(f"Fetched file {input_file_path} is empty.")

    # Transcode if needed
    input_file_obj = TranscodeTempDirAndFile(temp_dir=temp_dir, filename=input_filename)
    transcoded_file_obj = transcode_media_file_if_needed(input_media_file=input_file_obj)

    # Unset the variable so that we don't accidentally use it later
    del input_filename, temp_dir

    if input_file_obj != transcoded_file_obj:
        # Function did some transcoding and stored everything in yet another file

        # Remove the input file
        _cleanup_temp_dir(temp=input_file_obj)

        # Consider the transcoded file the new input file
        input_file_obj = transcoded_file_obj

    # (Re)read the properties of either the original or the transcoded file
    media_info = media_file_info(media_file_path=input_file_obj.temp_full_path)
    best_audio_stream = media_info.best_supported_audio_stream()

    # Store input file to GCS
    try:
        gcs = GCSStore()
        gcs_uri = gcs.store_object(
            local_file_path=input_file_obj.temp_full_path,
            object_id=str(stories_id),
            mime_type=best_audio_stream.audio_codec_class.mime_type(),
        )

    except Exception as ex:

        log.error(f"Unable to store episode file '{input_file_obj.temp_full_path}' for story {stories_id}: {ex}")

        # Clean up, then raise further
        _cleanup_temp_dir(temp=input_file_obj)

        raise ex

    # Clean up the locally stored file as we don't need it anymore
    _cleanup_temp_dir(temp=input_file_obj)

    # FIXME
