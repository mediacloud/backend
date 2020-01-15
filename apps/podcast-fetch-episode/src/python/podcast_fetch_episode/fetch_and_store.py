import os
import shutil
import tempfile
from typing import Optional

from mediawords.db import DatabaseHandler
from mediawords.util.identify_language import language_code_for_text, identification_would_be_reliable
from mediawords.util.log import create_logger
from mediawords.util.parse_html import html_strip

from podcast_fetch_episode.bcp47_lang import iso_639_1_code_to_bcp_47_identifier
from podcast_fetch_episode.config import PodcastFetchEpisodeConfig
from podcast_fetch_episode.enclosure import podcast_viable_enclosure_for_story, MAX_ENCLOSURE_SIZE
from podcast_fetch_episode.exceptions import (
    McStoryNotFoundException,
    McPodcastNoViableStoryEnclosuresException,
    McPodcastEnclosureTooBigException,
    McPodcastFileStoreFailureException,
    McPodcastFileFetchFailureException,
    McPodcastGCSStoreFailureException,
    McPodcastPostgreSQLException,
)
from podcast_fetch_episode.fetch_url import fetch_big_file
from podcast_fetch_episode.gcs_store import GCSStore
from podcast_fetch_episode.media_file import TranscodeTempDirAndFile, transcode_media_file_if_needed, media_file_info

log = create_logger(__name__)


def _cleanup_temp_dir(temp: TranscodeTempDirAndFile) -> None:
    """Clean up temporary directory or raise a hard exception."""
    try:
        shutil.rmtree(temp.temp_dir)
    except Exception as ex:
        # Not being able to clean up after ourselves is a "hard" error as we might run out of disk space that way
        raise McPodcastFileStoreFailureException(f"Unable to remove temporary directory: {ex}")


def fetch_and_store_episode(db: DatabaseHandler,
                            stories_id: int,
                            config: Optional[PodcastFetchEpisodeConfig] = None) -> None:
    """
    Choose a viable story enclosure for podcast, fetch it, transcode if needed, store to GCS, and record to DB.

    1) Determines the episode's likely language by looking into its title and description, converts the language code to
       BCP 47;
    1) Using enclosures from "story_enclosures", chooses the one that looks like a podcast episode the most;
    2) Fetches the chosen enclosure;
    3) Transcodes the file (if needed) by:
        a) converting it to an audio format that the Speech API can support, and / or
        b) discarding video stream from the media file, and / or
        c) discarding other audio streams from the media file;
    5) Reads the various parameters, e.g. sample rate, of the episode audio file;
    4) Uploads the episode audio file to Google Cloud Storage;
    5) Adds a row to "podcast_episodes".

    Adding a job to submit the newly created episode to Speech API (by adding a RabbitMQ job) is up to the caller.

    :param db: Database handler.
    :param stories_id: Story ID for the story to operate on.
    :param config: (optional) Podcast fetcher configuration object (useful for testing).
    """

    if not config:
        config = PodcastFetchEpisodeConfig()

    story = db.find_by_id(table='stories', object_id=stories_id)
    if not story:
        raise McStoryNotFoundException(f"Story {stories_id} was not found.")

    # Try to determine language of the story
    story_title = story['title']
    story_description = html_strip(story['description'])
    sample_text = f"{story_title}\n{story_description}"

    iso_639_1_language_code = None
    if identification_would_be_reliable(text=sample_text):
        iso_639_1_language_code = language_code_for_text(text=sample_text)

    if not iso_639_1_language_code:
        iso_639_1_language_code = 'en'

    # Convert to BCP 47 identifier
    bcp_47_language_code = iso_639_1_code_to_bcp_47_identifier(
        iso_639_1_code=iso_639_1_language_code,
        url_hint=story['url'],
    )

    # Find the enclosure that might work the best
    best_enclosure = podcast_viable_enclosure_for_story(db=db, stories_id=stories_id)
    if not best_enclosure:
        raise McPodcastNoViableStoryEnclosuresException(f"There were no viable enclosures found for story {stories_id}")

    if best_enclosure.length > MAX_ENCLOSURE_SIZE:
        raise McPodcastEnclosureTooBigException(f"Chosen enclosure {best_enclosure} is too big.")

    try:
        temp_dir = tempfile.mkdtemp()
    except Exception as ex:
        raise McPodcastFileStoreFailureException(f"Unable to create temporary directory: {ex}")

    # Fetch enclosure
    input_filename = 'input_file'
    input_file_path = os.path.join(temp_dir, input_filename)
    log.info(f"Fetching enclosure {best_enclosure} to {input_file_path}...")
    fetch_big_file(url=best_enclosure.url, dest_file=input_file_path, max_size=MAX_ENCLOSURE_SIZE)
    log.info(f"Done fetching enclosure {best_enclosure} to {input_file_path}")

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
        gcs = GCSStore(config=config)
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

    # Insert everything to the database
    try:
        db.query("""
            INSERT INTO podcast_episodes (
                stories_id,
                story_enclosures_id,
                gcs_uri,
                duration,
                codec,
                audio_channel_count,
                sample_rate,
                bcp47_language_code
            ) VALUES (
                %(stories_id)s,
                %(story_enclosures_id)s,
                %(gcs_uri)s,
                %(duration)s,
                %(codec)s,
                %(audio_channel_count)s,
                %(sample_rate)s,
                %(bcp47_language_code)s            
            ) ON CONFLICT (stories_id) DO UPDATE SET
                story_enclosures_id = %(story_enclosures_id)s,
                gcs_uri = %(gcs_uri)s,
                duration = %(duration)s,
                codec = %(codec)s,
                audio_channel_count = %(audio_channel_count)s,
                sample_rate = %(sample_rate)s,
                bcp47_language_code = %(bcp47_language_code)s
        """, {
            'stories_id': stories_id,
            'story_enclosures_id': best_enclosure.story_enclosures_id,
            'gcs_uri': gcs_uri,
            'duration': best_audio_stream.duration,
            'codec': best_audio_stream.audio_codec_class.postgresql_enum_value(),
            'audio_channel_count': best_audio_stream.audio_channel_count,
            'sample_rate': best_audio_stream.sample_rate,
            'bcp47_language_code': bcp_47_language_code,
        })

    except Exception as ex_db:

        # Try to delete object on GCS first
        try:
            gcs.delete_object(object_id=str(stories_id))
        except Exception as ex_gcs:
            # We should be able to delete it as we've just uploaded it
            raise McPodcastGCSStoreFailureException((
                f"Unable to clean up story's {stories_id} audio file from GCS after database insert failure; "
                f"database insert exception: {ex_db}; "
                f"GCS exception: {ex_gcs}")
            )

        raise McPodcastPostgreSQLException(f"Failed inserting episode for story {stories_id}: {ex_db}")
