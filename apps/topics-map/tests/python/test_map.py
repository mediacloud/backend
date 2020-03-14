from unittest import TestCase

import mediawords.db
from topics_map.map import *
from mediawords.test.db.create import create_test_medium, create_test_topic, create_test_timespan

NUM_CONNECTED_MEDIA = 100
NUM_DISCONNECTED_MEDIA = 10

class TestMap(TestCase):

    def setUp(self):
        self.db = mediawords.db.connect_to_db()

        db = self.db

        db.query("delete from media")

        self.connected_media = []
        for i in range(NUM_CONNECTED_MEDIA):
            self.connected_media.append(create_test_medium(db, 'connected %d' % i))
            
        self.disconnected_media = []
        for i in range(NUM_DISCONNECTED_MEDIA):
            self.disconnected_media.append(create_test_medium(db, 'disconnected %d' %i))

        self.topic = create_test_topic(db, 'foo')
        self.timespan = create_test_timespan(db, self.topic)

        center_medium = self.connected_media[0]
        for medium in self.connected_media[1:]:
            db.query(
                """
                insert into snap.medium_links (timespans_id, source_media_id, ref_media_id, link_count)
                    values(%(a)s, %(b)s, %(c)s, 1)
                """,
                {'a': self.timespan['timespans_id'], 'b': medium['media_id'], 'c': center_medium['media_id']}
            )

        db.query(
            """
            insert into snap.medium_link_counts
                (timespans_id, media_id,
                    inlink_count, outlink_count, story_count, media_inlink_count, sum_media_inlink_count)
                select timespans_id, media_id, 1, 1, 1, 1, 1
                    from timespans t
                        cross join media m
            """
        )

    def test_get_media_network(self):
        db = self.db

        media = get_media_network(db, self.timespan['timespans_id'])

        assert len(media) == len(self.connected_media + self.disconnected_media)

        for m in self.connected_media:
            assert m['media_id'] in [m['media_id'] for m in self.connected_media]

