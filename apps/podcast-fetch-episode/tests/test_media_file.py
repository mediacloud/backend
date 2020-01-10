import hashlib
import os

import pytest

from podcast_fetch_episode.audio_codecs import AbstractAudioCodec
from podcast_fetch_episode.exceptions import McPodcastFileIsInvalidException
from podcast_fetch_episode.media_file import (
    MediaFileInfo,
    media_file_info,
    TranscodeTempDirAndFile,
    transcode_media_file_if_needed,
)

MEDIA_SAMPLES_PATH = '/opt/mediacloud/tests/data/media-samples/samples/'
assert os.path.isdir(MEDIA_SAMPLES_PATH), f"Directory with media samples '{MEDIA_SAMPLES_PATH}' should exist."

SAMPLE_FILENAMES = [f for f in os.listdir(MEDIA_SAMPLES_PATH) if os.path.isfile(os.path.join(MEDIA_SAMPLES_PATH, f))]
assert SAMPLE_FILENAMES, f"There should be some sample files available in {MEDIA_SAMPLES_PATH}."
assert [f for f in SAMPLE_FILENAMES if '.mp3' in f], f"There should be at least one .mp3 file in {MEDIA_SAMPLES_PATH}."
assert not [f for f in SAMPLE_FILENAMES if '/' in f], f"There can't be any paths in {SAMPLE_FILENAMES}."


def test_media_file_info():
    for filename in SAMPLE_FILENAMES:
        input_file_path = os.path.join(MEDIA_SAMPLES_PATH, filename)
        media_info = media_file_info(media_file_path=input_file_path)
        assert isinstance(media_info, MediaFileInfo)
        if '.mp3' in filename:
            assert not media_info.has_video_streams, f"MP3 file '{filename}' is not expected to have video streams."
        if '.mkv' in filename:
            assert media_info.has_video_streams, f"MKV file '{filename}' is expected to have video streams."
        if 'noaudio' in filename:
            assert not media_info.audio_streams, f"File '{filename}' is not expected to have any audio streams."
        else:
            assert media_info.audio_streams, f"File '{filename}' is expected to have audio streams."

        if media_info.audio_streams:
            for stream in media_info.audio_streams:
                assert stream.duration > 0, f"File's '{filename}' stream's {stream} duration should be positive."


def _file_sha1_hash(file_path: str) -> str:
    """Return file's SHA1 hash."""

    sha1 = hashlib.sha1()

    with open(file_path, 'rb') as f:
        while True:
            data = f.read(65536)
            if not data:
                break
            sha1.update(data)

    return sha1.hexdigest()


def test_transcode_media_file_if_needed():
    """Test transcode_media_if_needed()."""

    for filename in SAMPLE_FILENAMES:
        input_file_path = os.path.join(MEDIA_SAMPLES_PATH, filename)
        assert os.path.isfile(input_file_path), f"Input file '{filename}' exists."

        before_sha1_hash = _file_sha1_hash(input_file_path)

        input_media_file = TranscodeTempDirAndFile(temp_dir=MEDIA_SAMPLES_PATH, filename=filename)

        if 'noaudio' in filename:
            with pytest.raises(McPodcastFileIsInvalidException):
                transcode_media_file_if_needed(input_media_file=input_media_file)

        else:
            output_media_file = transcode_media_file_if_needed(input_media_file=input_media_file)

            after_sha1_hash = _file_sha1_hash(input_file_path)

            assert before_sha1_hash == after_sha1_hash, f"Input file '{filename}' shouldn't have been modified."

            assert output_media_file, "Output media file was set."

            output_file_info = media_file_info(media_file_path=output_media_file.temp_full_path)

            assert not output_file_info.has_video_streams, f"There should be no video streams in '{filename}'."
            assert len(output_file_info.audio_streams) == 1, f"There should be only one audio stream in '{filename}'."
            assert issubclass(
                output_file_info.audio_streams[0].audio_codec_class,
                AbstractAudioCodec,
            ), f"Processed '{filename}' should be in one of the supported codecs."
