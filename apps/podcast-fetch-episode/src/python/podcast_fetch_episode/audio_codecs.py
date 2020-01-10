"""
Audio codecs supported by the Speech API.

https://cloud.google.com/speech-to-text/docs/reference/rpc/google.cloud.speech.v1p1beta1
"""

import abc
from typing import Dict, Any


class AbstractAudioCodec(object, metaclass=abc.ABCMeta):

    @classmethod
    @abc.abstractmethod
    def postgresql_enum_value(cls) -> str:
        """Return value from 'podcast_episodes_audio_codec' PostgreSQL enum."""
        raise NotImplemented("Abstract method")

    @classmethod
    @abc.abstractmethod
    def ffmpeg_stream_is_this_codec(cls, ffmpeg_stream: Dict[str, Any]) -> bool:
        """Return True if ffmpeg.probe()'s one of the streams ('streams' key) is of this codec."""
        raise NotImplemented("Abstract method")

    @classmethod
    @abc.abstractmethod
    def ffmpeg_container_format(cls) -> str:
        """Return FFmpeg container format (-f argument)."""
        raise NotImplemented("Abstract method")

    @classmethod
    @abc.abstractmethod
    def mime_type(cls) -> str:
        """Return MIME type to store as GCS object metadata."""
        raise NotImplemented("Abstract method")


class Linear16AudioCodec(AbstractAudioCodec):

    @classmethod
    def postgresql_enum_value(cls) -> str:
        return 'LINEAR16'

    @classmethod
    def ffmpeg_stream_is_this_codec(cls, ffmpeg_stream: Dict[str, Any]) -> bool:
        return ffmpeg_stream['codec_name'] == 'pcm_s16le'

    @classmethod
    def ffmpeg_container_format(cls) -> str:
        return 'wav'

    @classmethod
    def mime_type(cls) -> str:
        return 'audio/wav'


class FLAC16AudioCodec(AbstractAudioCodec):

    @classmethod
    def postgresql_enum_value(cls) -> str:
        return 'FLAC16'

    @classmethod
    def ffmpeg_stream_is_this_codec(cls, ffmpeg_stream: Dict[str, Any]) -> bool:
        return ffmpeg_stream['codec_name'] == 'flac' and ffmpeg_stream['sample_fmt'] == 's16'

    @classmethod
    def ffmpeg_container_format(cls) -> str:
        return 'flac'

    @classmethod
    def mime_type(cls) -> str:
        return 'audio/flac'


class FLAC24AudioCodec(AbstractAudioCodec):

    @classmethod
    def postgresql_enum_value(cls) -> str:
        return 'FLAC24'

    @classmethod
    def ffmpeg_stream_is_this_codec(cls, ffmpeg_stream: Dict[str, Any]) -> bool:
        # "ffmpeg -i" says "s32 (24 bit)"
        return ffmpeg_stream['codec_name'] == 'flac' and ffmpeg_stream['sample_fmt'] == 's32'

    @classmethod
    def ffmpeg_container_format(cls) -> str:
        return 'flac'

    @classmethod
    def mime_type(cls) -> str:
        return 'audio/flac'


class MULAWAudioCodec(AbstractAudioCodec):

    @classmethod
    def postgresql_enum_value(cls) -> str:
        return 'MULAW'

    @classmethod
    def ffmpeg_stream_is_this_codec(cls, ffmpeg_stream: Dict[str, Any]) -> bool:
        return ffmpeg_stream['codec_name'] == 'pcm_mulaw'

    @classmethod
    def ffmpeg_container_format(cls) -> str:
        return 'wav'

    @classmethod
    def mime_type(cls) -> str:
        return 'audio/basic'


class OggOpusAudioCodec(AbstractAudioCodec):

    @classmethod
    def postgresql_enum_value(cls) -> str:
        return 'OGG_OPUS'

    @classmethod
    def ffmpeg_stream_is_this_codec(cls, ffmpeg_stream: Dict[str, Any]) -> bool:
        return ffmpeg_stream['codec_name'] == 'opus'

    @classmethod
    def ffmpeg_container_format(cls) -> str:
        return 'ogg'

    @classmethod
    def mime_type(cls) -> str:
        return 'audio/ogg'


class MP3AudioCodec(AbstractAudioCodec):

    @classmethod
    def postgresql_enum_value(cls) -> str:
        return 'MP3'

    @classmethod
    def ffmpeg_stream_is_this_codec(cls, ffmpeg_stream: Dict[str, Any]) -> bool:
        return ffmpeg_stream['codec_name'] == 'mp3'

    @classmethod
    def ffmpeg_container_format(cls) -> str:
        return 'mp3'

    @classmethod
    def mime_type(cls) -> str:
        return 'audio/mpeg'
