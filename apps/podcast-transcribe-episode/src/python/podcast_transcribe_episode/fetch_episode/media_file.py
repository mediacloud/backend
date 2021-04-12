import dataclasses
import subprocess
import math
import os
import shutil
import tempfile
from typing import Type, Optional, List

# noinspection PyPackageRequirements
import ffmpeg

from mediawords.util.log import create_logger

from ..exceptions import (
    McPodcastMisconfiguredTranscoderException,
    McPodcastFileIsInvalidException,
    McPodcastFileStoreFailureException,
)
from .audio_codecs import (
    AbstractAudioCodec,
    Linear16AudioCodec,
    FLACAudioCodec,
    MULAWAudioCodec,
    OggOpusAudioCodec,
    MP3AudioCodec,
)

log = create_logger(__name__)

_SUPPORTED_CODEC_CLASSES = {
    Linear16AudioCodec,
    FLACAudioCodec,
    MULAWAudioCodec,
    OggOpusAudioCodec,
    MP3AudioCodec,
}
"""Supported native audio codec classes."""


@dataclasses.dataclass
class MediaFileInfoAudioStream(object):
    """Information about a single audio stream in a media file."""

    ffmpeg_stream_index: int
    """FFmpeg internal stream index."""

    audio_codec_class: Optional[Type[AbstractAudioCodec]]
    """Audio codec class if the stream is one of the supported types and has single (mono) channel, None otherwise."""

    duration: int
    """Duration (in seconds)."""

    audio_channel_count: int
    """Audio channel count."""

    sample_rate: int
    """Audio sample rate."""


@dataclasses.dataclass
class MediaFileInfo(object):
    """Information about media file."""

    audio_streams: List[MediaFileInfoAudioStream]
    """List of audio streams found in the media file."""

    has_video_streams: bool
    """True if the media file has video streams."""

    def best_supported_audio_stream(self) -> Optional[MediaFileInfoAudioStream]:
        """Return the first supported audio stream, if any."""
        for stream in self.audio_streams:
            if stream.audio_codec_class:
                return stream
        return None


def media_file_info(media_file_path: str) -> MediaFileInfo:
    """
    Read audio / video media file information, or raise if it can't be read.

    :param media_file_path: Full path to media file.
    :return: MediaFileInfo object.
    """
    if not os.path.isfile(media_file_path):
        # Input file should exist at this point; it it doesn't, we have probably messed up something in the code
        raise McPodcastMisconfiguredTranscoderException(f"Input file {media_file_path} does not exist.")

    try:
        file_info = ffmpeg.probe(media_file_path)
        if not file_info:
            raise Exception("Returned metadata is empty.")
    except Exception as ex:
        raise McPodcastFileIsInvalidException(
            f"Unable to read metadata from file {media_file_path}: {ex}"
        )

    if 'streams' not in file_info:
        # FFmpeg should come up with some sort of a stream in any case
        raise McPodcastMisconfiguredTranscoderException("Returned probe doesn't have 'streams' key.")

    # Test if one of the audio streams is of one of the supported codecs
    audio_streams = []
    has_video_streams = False
    for stream in file_info['streams']:
        if stream['codec_type'] == 'audio':

            try:
                audio_channel_count = int(stream['channels'])
                if audio_channel_count == 0:
                    raise Exception("Audio channel count is 0")
            except Exception as ex:
                log.warning(f"Unable to read audio channel count from stream {stream}: {ex}")
                # Just skip this stream if we can't figure it out
                continue

            audio_codec_class = None

            # We'll need to transcode audio files with more than one channel count anyway
            if audio_channel_count == 1:
                for codec in _SUPPORTED_CODEC_CLASSES:
                    if codec.ffmpeg_stream_is_this_codec(ffmpeg_stream=stream):
                        audio_codec_class = codec
                        break

            try:

                if 'duration' in stream:
                    # 'duration': '3.766621'
                    duration = math.floor(float(stream['duration']))

                elif 'DURATION' in stream.get('tags', {}):
                    # 'DURATION': '00:00:03.824000000'
                    duration_parts = stream['tags']['DURATION'].split(':')
                    if len(duration_parts) != 3:
                        raise McPodcastFileIsInvalidException(f"Unable to parse 'DURATION': {duration_parts}")

                    hh = int(duration_parts[0])
                    mm = int(duration_parts[1])
                    ss_ms = duration_parts[2].split('.')

                    if len(ss_ms) == 1:
                        ss = int(ss_ms[0])
                        ms = 0
                    elif len(ss_ms) == 2:
                        ss = int(ss_ms[0])
                        ms = int(ss_ms[1])
                    else:
                        raise McPodcastFileIsInvalidException(f"Unable to parse 'DURATION': {duration_parts}")

                    duration = hh * 3600 + mm * 60 + ss + (1 if ms > 0 else 0)

                else:
                    raise McPodcastFileIsInvalidException(f"Stream doesn't have duration: {stream}")

                audio_stream = MediaFileInfoAudioStream(
                    ffmpeg_stream_index=stream['index'],
                    audio_codec_class=audio_codec_class,
                    duration=duration,
                    audio_channel_count=audio_channel_count,
                    sample_rate=int(stream['sample_rate']),
                )
                audio_streams.append(audio_stream)

            except Exception as ex:
                # Just skip this stream if we can't figure it out
                log.warning(f"Unable to read audio stream data for stream {stream}: {ex}")

        elif stream['codec_type'] == 'video':
            has_video_streams = True

    return MediaFileInfo(
        audio_streams=audio_streams,
        has_video_streams=has_video_streams,
    )


@dataclasses.dataclass
class TranscodeTempDirAndFile(object):
    """
    Temporary directory and filename for transcoding.

    It is assumed that caller is free to recursively remove 'temp_directory' after making use of the transcoded file.
    """
    temp_dir: str
    filename: str

    @property
    def temp_full_path(self) -> str:
        """Return full path to file."""
        return os.path.join(self.temp_dir, self.filename)


def transcode_media_file_if_needed(input_media_file: TranscodeTempDirAndFile) -> TranscodeTempDirAndFile:
    """
    Transcode file (if needed) to something that Speech API will support.

    * If input has a video stream, it will be discarded;
    * If input has more than one audio stream, others will be discarded leaving only one (preferably the one that Speech
      API can support);
    * If input doesn't have an audio stream in Speech API-supported codec, it will be transcoded to lossless
      FLAC 16 bit in order to preserve quality;
    * If the chosen audio stream has multiple channels (e.g. stereo or 5.1), it will be mixed into a single (mono)
      channel as Speech API supports multi-channel recognition only when different voices speak into each of the
      channels.

    :param input_media_file: Temporary directory and input media file to consider transcoding.
    :return: Either the same 'input_media_file' if file wasn't transcoded, or new TranscodeTempDirAndFile() if it was.
    """

    if not os.path.isdir(input_media_file.temp_dir):
        # Directory should exist; if it doesn't, it's a critical problem either in the filesystem or the code
        raise McPodcastMisconfiguredTranscoderException(f"Directory '{input_media_file.temp_dir}' does not exist.")

    if not os.path.isfile(input_media_file.temp_full_path):
        raise McPodcastMisconfiguredTranscoderException(f"File '{input_media_file}' does not exist.")

    # Independently from what <enclosure /> has told us, identify the file type again ourselves
    media_info = media_file_info(media_file_path=input_media_file.temp_full_path)

    if not media_info.audio_streams:
        raise McPodcastFileIsInvalidException("Downloaded file doesn't appear to have any audio streams.")

    ffmpeg_args = []

    supported_audio_stream = media_info.best_supported_audio_stream()
    if supported_audio_stream:
        log.info(f"Found a supported audio stream")

        # Test if there is more than one audio stream
        if len(media_info.audio_streams) > 1:
            log.info(f"Found other audio streams besides the supported one, will discard those")

            ffmpeg_args.extend(['-f', supported_audio_stream.audio_codec_class.ffmpeg_container_format()])

            # Select all audio streams
            ffmpeg_args.extend(['-map', '0:a'])

            for stream in media_info.audio_streams:
                # Deselect the unsupported streams
                if stream != supported_audio_stream:
                    ffmpeg_args.extend(['-map', f'-0:a:{stream.ffmpeg_stream_index}'])

    # If a stream of a supported codec was not found, transcode it to FLAC 16 bit in order to not lose any quality
    else:
        log.info(f"None of the audio streams are supported by the Speech API, will transcode to FLAC")

        # Map first audio stream to input 0
        ffmpeg_args.extend(['-map', '0:a:0'])

        # Transcode to FLAC (16 bit) in order to not lose any quality
        ffmpeg_args.extend(['-acodec', 'flac'])
        ffmpeg_args.extend(['-f', 'flac'])
        ffmpeg_args.extend(['-sample_fmt', 's16'])

        # Ensure that we end up with mono audio
        ffmpeg_args.extend(['-ac', '1'])

    # If there's video in the file (e.g. video), remove it
    if media_info.has_video_streams:
        # Discard all video streams
        ffmpeg_args.extend(['-map', '-0:v'])

    if ffmpeg_args:

        temp_filename = 'transcoded_file'

        try:
            temp_dir = tempfile.mkdtemp('media_file')
        except Exception as ex:
            raise McPodcastFileStoreFailureException(f"Unable to create temporary directory: {ex}")

        temp_file_path = os.path.join(temp_dir, temp_filename)

        try:
            log.info(f"Transcoding {input_media_file.temp_full_path} to {temp_file_path}...")

            # I wasn't sure how to map outputs in "ffmpeg-python" library so here we call ffmpeg directly
            ffmpeg_command = ['ffmpeg', '-nostdin', '-hide_banner',
                              '-i', input_media_file.temp_full_path] + ffmpeg_args + [temp_file_path]
            log.debug(f"FFmpeg command: {ffmpeg_command}")
            subprocess.check_call(ffmpeg_command)

            log.info(f"Done transcoding {input_media_file.temp_full_path} to {temp_file_path}")

        except Exception as ex:

            shutil.rmtree(temp_dir)

            raise McPodcastFileIsInvalidException(f"Unable to transcode {input_media_file.temp_full_path}: {ex}")

        result_media_file = TranscodeTempDirAndFile(temp_dir=temp_dir, filename=temp_filename)

    else:

        # Return the same file as it wasn't touched
        result_media_file = input_media_file

    return result_media_file
