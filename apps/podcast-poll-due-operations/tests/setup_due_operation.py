import abc
from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story


class SetupTestOperation(TestCase, metaclass=abc.ABCMeta):
    __slots__ = [
        'db',
        'test_medium',
        'test_feed',
        'story',
        'stories_id',
    ]

    def setUp(self):
        self.db = connect_to_db()

        self.test_medium = create_test_medium(db=self.db, label='test')
        self.test_feed = create_test_feed(db=self.db, label='test', medium=self.test_medium)
        self.story = create_test_story(db=self.db, label='test', feed=self.test_feed)

        stories_id = self.story['stories_id']

        enclosure = self.db.insert(table='story_enclosures', insert_hash={
            'stories_id': stories_id,
            # URL doesn't really matter as we won't be fetching it
            'url': 'http://example.com/',
            'mime_type': 'audio/mpeg',
            'length': 100000,
        })

        episode = self.db.insert(table='podcast_episodes', insert_hash={
            'stories_id': stories_id,
            'story_enclosures_id': enclosure['story_enclosures_id'],
            'gcs_uri': 'gs://whatever',
            'duration': 1,
            'codec': 'MP3',
            'audio_channel_count': 2,
            'sample_rate': 44100,
            'bcp47_language_code': 'en-US',
        })

        self.db.query("""
            INSERT INTO podcast_episode_operations (
                stories_id,
                podcast_episodes_id,
                speech_operation_id,
                fetch_results_at
            ) VALUES (
                %(stories_id)s,
                %(podcast_episodes_id)s,
                'foo',
                NOW()
            )
        """, {
            'stories_id': stories_id,
            'podcast_episodes_id': episode['podcast_episodes_id'],
        })
