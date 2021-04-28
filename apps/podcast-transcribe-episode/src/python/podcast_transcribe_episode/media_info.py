import dataclasses
import math
import os
from typing import Type, Optional, List

# noinspection PyPackageRequirements
import ffmpeg

from mediawords.util.log import create_logger

from .exceptions import McProgrammingError, McPermanentError
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
        raise McProgrammingError(f"Input file {media_file_path} does not exist.")

    try:
        file_info = ffmpeg.probe(media_file_path)
        if not file_info:
            raise Exception("Returned metadata is empty.")
    except Exception as ex:
        raise McPermanentError(f"Unable to read metadata from file {media_file_path}: {ex}")

    if 'streams' not in file_info:
        # FFmpeg should come up with some sort of a stream in any case
        raise McProgrammingError("Returned probe doesn't have 'streams' key.")

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
                        raise McPermanentError(f"Unable to parse 'DURATION': {duration_parts}")

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
                        raise McPermanentError(f"Unable to parse 'DURATION': {duration_parts}")

                    duration = hh * 3600 + mm * 60 + ss + (1 if ms > 0 else 0)

                else:
                    raise McPermanentError(f"Stream doesn't have duration: {stream}")

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
