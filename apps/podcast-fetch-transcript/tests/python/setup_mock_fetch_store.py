import abc
from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story
from mediawords.util.log import create_logger

log = create_logger(__name__)


class AbstractMockFetchStoreTestCase(TestCase, metaclass=abc.ABCMeta):
    MOCK_SPEECH_OPERATION_ID = 'foo'

    __slots__ = [
        'db',
        'enclosure',
        'episode',
        'transcript_fetch',
        'podcast_episode_transcript_fetches_id',
    ]

    def setUp(self) -> None:
        super().setUp()

        self.db = connect_to_db()

        test_medium = create_test_medium(db=self.db, label='test')
        test_feed = create_test_feed(db=self.db, label='test', medium=test_medium)
        test_story = create_test_story(db=self.db, feed=test_feed, label='test')

        self.enclosure = self.db.insert(table='story_enclosures', insert_hash={
            'stories_id': test_story['stories_id'],
            'url': 'foo',
            'mime_type': 'foo',
            'length': 3,
        })

        self.episode = self.db.insert(table='podcast_episodes', insert_hash={
            'stories_id': test_story['stories_id'],
            'story_enclosures_id': self.enclosure['story_enclosures_id'],
            'gcs_uri': 'gs://test',
            'duration': 3,
            'codec': 'FLAC',
            'sample_rate': 44100,
            'bcp47_language_code': 'en-US',
            'speech_operation_id': self.MOCK_SPEECH_OPERATION_ID,
        })

        self.transcript_fetch = self.db.query("""
            INSERT INTO podcast_episode_transcript_fetches (podcast_episodes_id, add_to_queue_at)
            VALUES (%(podcast_episodes_id)s, NOW())
            RETURNING *
        """, {
            'podcast_episodes_id': self.episode['podcast_episodes_id'],
        }).hash()

        self.podcast_episode_transcript_fetches_id = self.transcript_fetch['podcast_episode_transcript_fetches_id']
