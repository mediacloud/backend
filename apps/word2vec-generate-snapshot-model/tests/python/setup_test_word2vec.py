from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story, create_test_topic


class TestWord2vec(TestCase):
    TEST_STORY_COUNT = 20
    TEST_SENTENCE_PER_STORY_COUNT = 20

    # Use very small stories_id chunk size to test out whether all stories and their sentences are being read
    TEST_STORIES_ID_CHUNK_SIZE = 3

    __slots__ = [
        'db',
        'topics_id',
        'snapshots_id',
    ]

    def setUp(self):
        super().setUp()

        self.db = connect_to_db()

        medium = create_test_medium(db=self.db, label='test')
        feed = create_test_feed(db=self.db, label='feed', medium=medium)

        for story_num in range(self.TEST_STORY_COUNT):
            story = create_test_story(db=self.db, label='story-%d' % story_num, feed=feed)
            for sentence_number in range(1, self.TEST_SENTENCE_PER_STORY_COUNT + 1):
                self.db.create(table='story_sentences', insert_hash={
                    'stories_id': story['stories_id'],
                    'media_id': medium['media_id'],
                    'publish_date': story['publish_date'],
                    'sentence_number': sentence_number,
                    'sentence': 'story {}, sentence {}'.format(story['stories_id'], sentence_number),
                })

        # Test topic
        topic = create_test_topic(db=self.db, label='test')
        self.topics_id = topic['topics_id']

        self.db.query("""
            INSERT INTO topic_stories (topics_id, stories_id)
            SELECT %(topics_id)s, stories_id FROM stories
        """, {'topics_id': self.topics_id})

        # Test snapshot
        self.snapshots_id = self.db.query("""
            INSERT INTO snapshots (topics_id, snapshot_date, start_date, end_date)
            VALUES (%(topics_id)s, NOW(), NOW(), NOW())
            RETURNING snapshots_id
        """, {'topics_id': self.topics_id}).flat()[0]

        self.db.query("""
            INSERT INTO snap.stories (
                topics_id,
                snapshots_id,
                media_id,
                stories_id,
                url,
                guid,
                title,
                publish_date,
                collect_date
            )
                SELECT
                    %(topics_id)s,
                    %(snapshots_id)s,
                    media_id,
                    stories_id,
                    url,
                    guid,
                    title,
                    publish_date,
                    collect_date
                FROM stories
        """, {
            'topics_id': self.topics_id,
            'snapshots_id': self.snapshots_id
        })
