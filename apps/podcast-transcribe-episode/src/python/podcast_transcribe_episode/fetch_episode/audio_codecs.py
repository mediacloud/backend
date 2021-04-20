"""
Audio codecs supported by the Speech API.

https://cloud.google.com/speech-to-text/docs/reference/rpc/google.cloud.speech.v1p1beta1
"""

import abc
from typing import Dict, Any


class AbstractAudioCodec(object, metaclass=abc.ABCMeta):

    @classmethod
    @abc.abstractmethod
    def ffmpeg_stream_is_this_codec(cls, ffmpeg_stream: Dict[str, Any]) -> bool:
        """Return True if ffmpeg.probe()'s one of the streams ('streams' key) is of this codec."""
        raise NotImplementedError

    @classmethod
    @abc.abstractmethod
    def ffmpeg_container_format(cls) -> str:
        """Return FFmpeg container format (-f argument)."""
        raise NotImplementedError

    @classmethod
    @abc.abstractmethod
    def mime_type(cls) -> str:
        """Return MIME type to store as GCS object metadata."""
        raise NotImplementedError

    @classmethod
    @abc.abstractmethod
    def speech_api_codec(cls) -> str:
        """Return codec enum value to pass to Speech API when submitting the transcription operation."""
        raise NotImplementedError


class Linear16AudioCodec(AbstractAudioCodec):

    @classmethod
    def ffmpeg_stream_is_this_codec(cls, ffmpeg_stream: Dict[str, Any]) -> bool:
        return ffmpeg_stream['codec_name'] == 'pcm_s16le'

    @classmethod
    def ffmpeg_container_format(cls) -> str:
        return 'wav'

    @classmethod
    def mime_type(cls) -> str:
        return 'audio/wav'

    @classmethod
    def speech_api_codec(cls) -> str:
        return 'LINEAR16'


class FLACAudioCodec(AbstractAudioCodec):

    @classmethod
    def ffmpeg_stream_is_this_codec(cls, ffmpeg_stream: Dict[str, Any]) -> bool:
        # FLAC 16 bit gets reported as "s16", and FLAC 24 bit as "s32 (24 bit)"
        return ffmpeg_stream['codec_name'] == 'flac' and ffmpeg_stream['sample_fmt'] in ('s16', 's32')

    @classmethod
    def ffmpeg_container_format(cls) -> str:
        return 'flac'

    @classmethod
    def mime_type(cls) -> str:
        return 'audio/flac'

    @classmethod
    def speech_api_codec(cls) -> str:
        return 'FLAC'


class MULAWAudioCodec(AbstractAudioCodec):

    @classmethod
    def ffmpeg_stream_is_this_codec(cls, ffmpeg_stream: Dict[str, Any]) -> bool:
        return ffmpeg_stream['codec_name'] == 'pcm_mulaw'

    @classmethod
    def ffmpeg_container_format(cls) -> str:
        return 'wav'

    @classmethod
    def mime_type(cls) -> str:
        return 'audio/basic'

    @classmethod
    def speech_api_codec(cls) -> str:
        return 'MULAW'


class OggOpusAudioCodec(AbstractAudioCodec):

    @classmethod
    def ffmpeg_stream_is_this_codec(cls, ffmpeg_stream: Dict[str, Any]) -> bool:
        return ffmpeg_stream['codec_name'] == 'opus'

    @classmethod
    def ffmpeg_container_format(cls) -> str:
        return 'ogg'

    @classmethod
    def mime_type(cls) -> str:
        return 'audio/ogg'

    @classmethod
    def speech_api_codec(cls) -> str:
        return 'OGG_OPUS'


class MP3AudioCodec(AbstractAudioCodec):

    @classmethod
    def ffmpeg_stream_is_this_codec(cls, ffmpeg_stream: Dict[str, Any]) -> bool:
        return ffmpeg_stream['codec_name'] == 'mp3'

    @classmethod
    def ffmpeg_container_format(cls) -> str:
        return 'mp3'

    @classmethod
    def mime_type(cls) -> str:
        return 'audio/mpeg'

    @classmethod
    def speech_api_codec(cls) -> str:
        return 'MP3'
