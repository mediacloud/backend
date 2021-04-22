import dataclasses
from typing import Dict, Any, List
from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.test.db.create import (
    create_test_medium,
    create_test_feed,
    create_test_story,
)

from podcast_transcribe_episode.enclosure import podcast_viable_enclosure_for_story, StoryEnclosure


@dataclasses.dataclass
class TestStoryAndEnclosure(object):
    story: Dict[str, Any]
    enclosures: List[Dict[str, Any]] = dataclasses.field(default_factory=list)

    @property
    def stories_id(self) -> int:
        return self.story['stories_id']


class TestPodcastViableEnclosureForStory(TestCase):
    _DB = None
    _TEST_MEDIUM = None
    _TEST_FEED = None

    @classmethod
    def setUpClass(cls) -> None:
        # All tests should be able to use the same database
        cls._DB = connect_to_db()
        cls._TEST_MEDIUM = create_test_medium(db=cls._DB, label='test')
        cls._TEST_FEED = create_test_feed(db=cls._DB, label='test', medium=cls._TEST_MEDIUM)

    def test_no_enclosures(self):
        no_enclosures = TestStoryAndEnclosure(
            story=create_test_story(
                db=self._DB,
                label='no enclosures',
                feed=self._TEST_FEED,
            )
        )

        assert podcast_viable_enclosure_for_story(
            db=self._DB,
            stories_id=no_enclosures.stories_id,
        ) is None, "Story with no enclosures."

    def test_enclosure_with_empty_url(self):
        enclosure_with_empty_url = TestStoryAndEnclosure(
            story=create_test_story(
                db=self._DB,
                label='enclosure with empty URL',
                feed=self._TEST_FEED,
            )
        )

        enclosure_with_empty_url.enclosures.append(
            self._DB.insert(table='story_enclosures', insert_hash={
                'stories_id': enclosure_with_empty_url.stories_id,
                'url': '',
                'mime_type': 'audio/mpeg',
                'length': 100000,
            })
        )

        assert podcast_viable_enclosure_for_story(
            db=self._DB,
            stories_id=enclosure_with_empty_url.stories_id,
        ) is None, "Story with an empty enclosure URL."

    def test_single_mp3_enclosure(self):
        single_mp3_enclosure = TestStoryAndEnclosure(
            story=create_test_story(
                db=self._DB,
                label='single MP3 enclosure',
                feed=self._TEST_FEED,
            )
        )

        single_mp3_enclosure.enclosures.append(
            self._DB.insert(table='story_enclosures', insert_hash={
                'stories_id': single_mp3_enclosure.stories_id,
                'url': 'http://www.example.com/test.mp3',
                'mime_type': 'audio/mpeg',
                'length': 100000,
            })
        )

        assert podcast_viable_enclosure_for_story(
            db=self._DB,
            stories_id=single_mp3_enclosure.stories_id,
        ) == StoryEnclosure.from_db_row(single_mp3_enclosure.enclosures[0]), (
            "Story with a single MP3 enclosure should return that one enclosure."
        )

    def test_single_mp3_without_mime_enclosure(self):
        single_mp3_without_mime_enclosure = TestStoryAndEnclosure(
            story=create_test_story(
                db=self._DB,
                label='single MP3 enclosure without MIME type set',
                feed=self._TEST_FEED,
            )
        )

        single_mp3_without_mime_enclosure.enclosures.append(
            self._DB.insert(table='story_enclosures', insert_hash={
                'stories_id': single_mp3_without_mime_enclosure.stories_id,
                'url': 'http://www.example.com/test.mp3',
                'mime_type': '',
                'length': 100000,
            })
        )

        assert podcast_viable_enclosure_for_story(
            db=self._DB,
            stories_id=single_mp3_without_mime_enclosure.stories_id,
        ) == StoryEnclosure.from_db_row(single_mp3_without_mime_enclosure.enclosures[0]), (
            "Story with a single MP3 enclosure without MIME type set should return that enclosure."
        )

    def test_multiple_audio_enclosures(self):
        multiple_audio_enclosures = TestStoryAndEnclosure(
            story=create_test_story(
                db=self._DB,
                label='multiple audio enclosures',
                feed=self._TEST_FEED,
            )
        )

        multiple_audio_enclosures.enclosures.extend([
            self._DB.insert(table='story_enclosures', insert_hash={
                'stories_id': multiple_audio_enclosures.stories_id,
                'url': 'http://www.example.com/test.aac',
                'mime_type': 'audio/aac',
                'length': 100000,
            }),
            self._DB.insert(table='story_enclosures', insert_hash={
                'stories_id': multiple_audio_enclosures.stories_id,
                'url': 'http://www.example.com/test.mp3',
                'mime_type': 'audio/mpeg',
                'length': 100000,
            }),
        ])

        assert podcast_viable_enclosure_for_story(
            db=self._DB,
            stories_id=multiple_audio_enclosures.stories_id,
        ) == StoryEnclosure.from_db_row(multiple_audio_enclosures.enclosures[1]), (
            "Story with multiple audio enclosures should return a supported audio enclosure."
        )

    def test_multiple_unsupported_audio_enclosures(self):
        multiple_unsupported_audio_enclosures = TestStoryAndEnclosure(
            story=create_test_story(
                db=self._DB,
                label='multiple audio enclosures none of which are supported',
                feed=self._TEST_FEED,
            )
        )

        multiple_unsupported_audio_enclosures.enclosures.extend([
            self._DB.insert(table='story_enclosures', insert_hash={
                'stories_id': multiple_unsupported_audio_enclosures.stories_id,
                'url': 'http://www.example.com/test.aac',
                'mime_type': 'audio/aac',
                'length': 100000,
            }),
            self._DB.insert(table='story_enclosures', insert_hash={
                'stories_id': multiple_unsupported_audio_enclosures.stories_id,
                'url': 'http://www.example.com/test.m4a',
                'mime_type': 'audio/mp4',
                'length': 100000,
            }),
        ])

        assert podcast_viable_enclosure_for_story(
            db=self._DB,
            stories_id=multiple_unsupported_audio_enclosures.stories_id,
        ) == StoryEnclosure.from_db_row(multiple_unsupported_audio_enclosures.enclosures[0]), (
            "Story with multiple unsupported audio enclosures should return a first audio enclosure."
        )

    def test_audio_and_video_enclosures(self):
        audio_and_video_enclosures = TestStoryAndEnclosure(
            story=create_test_story(
                db=self._DB,
                label='audio and video enclosures',
                feed=self._TEST_FEED,
            )
        )

        audio_and_video_enclosures.enclosures.extend([
            self._DB.insert(table='story_enclosures', insert_hash={
                'stories_id': audio_and_video_enclosures.stories_id,
                'url': 'http://www.example.com/test.mkv',
                'mime_type': 'video/x-matroska',
                'length': 100000,
            }),
            self._DB.insert(table='story_enclosures', insert_hash={
                'stories_id': audio_and_video_enclosures.stories_id,
                'url': 'http://www.example.com/test.aac',
                'mime_type': 'audio/aac',
                'length': 100000,
            }),
        ])

        assert podcast_viable_enclosure_for_story(
            db=self._DB,
            stories_id=audio_and_video_enclosures.stories_id,
        ) == StoryEnclosure.from_db_row(audio_and_video_enclosures.enclosures[1]), (
            "Story with audio and video enclosures should return an audio enclosure."
        )

    def test_only_video_enclosures(self):
        only_video_enclosures = TestStoryAndEnclosure(
            story=create_test_story(
                db=self._DB,
                label='only video enclosures',
                feed=self._TEST_FEED,
            )
        )

        only_video_enclosures.enclosures.extend([
            self._DB.insert(table='story_enclosures', insert_hash={
                'stories_id': only_video_enclosures.stories_id,
                'url': 'http://www.example.com/test.mkv',
                'mime_type': 'video/x-matroska',
                'length': 100000,
            }),
            self._DB.insert(table='story_enclosures', insert_hash={
                'stories_id': only_video_enclosures.stories_id,
                'url': 'http://www.example.com/test.mp4',
                'mime_type': 'video/mp4',
                'length': 100000,
            }),
        ])

        assert podcast_viable_enclosure_for_story(
            db=self._DB,
            stories_id=only_video_enclosures.stories_id,
        ) == StoryEnclosure.from_db_row(only_video_enclosures.enclosures[0]), (
            "Story with only video enclosures should return the first video enclosure."
        )
