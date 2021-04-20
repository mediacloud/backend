import subprocess
import os

from mediawords.util.log import create_logger

from ..exceptions import McPodcastMisconfiguredTranscoderException, McPodcastFileIsInvalidException
from .media_info import media_file_info

log = create_logger(__name__)


def maybe_transcode_file(input_file: str, maybe_output_file: str) -> bool:
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

    :param input_file: Input media file to consider for transcoding.
    :param maybe_output_file: If we decide to transcode, output media file to transcode to.
    :return: True if file had to be transcoded into "maybe_output_file", or False if input file can be used as it is.
    """

    if not os.path.isfile(input_file):
        raise McPodcastMisconfiguredTranscoderException(f"File '{input_file}' does not exist.")

    # Independently from what <enclosure /> has told us, identify the file type again ourselves
    media_info = media_file_info(media_file_path=input_file)

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

    if not ffmpeg_args:
        # No need to transcode -- caller should use the input file as-is
        return False

    log.info(f"Transcoding '{input_file}' to '{maybe_output_file}'...")

    # I wasn't sure how to map outputs in "ffmpeg-python" library so here we call ffmpeg directly
    ffmpeg_command = ['ffmpeg', '-nostdin', '-hide_banner', '-i', input_file] + ffmpeg_args + [maybe_output_file]
    log.debug(f"FFmpeg command: {ffmpeg_command}")
    subprocess.check_call(ffmpeg_command)

    log.info(f"Done transcoding '{input_file}' to '{maybe_output_file}'")

    return True
