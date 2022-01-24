from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_topic, create_test_timespan


class TestMap(TestCase):
    __NUM_CONNECTED_MEDIA = 100
    __NUM_DISCONNECTED_MEDIA = 10

    def setUp(self):
        self.db = connect_to_db()

        db = self.db

        self.connected_media = []
        for i in range(self.__NUM_CONNECTED_MEDIA):
            self.connected_media.append(create_test_medium(db, 'connected %d' % i))

        self.disconnected_media = []
        for i in range(self.__NUM_DISCONNECTED_MEDIA):
            self.disconnected_media.append(create_test_medium(db, 'disconnected %d' % i))

        self.all_media = self.connected_media + self.disconnected_media

        self.topic = create_test_topic(db, 'foo')
        self.timespan = create_test_timespan(db, self.topic)

        center_medium = self.connected_media[0]
        for medium in self.connected_media[1:]:
            db.query(
                """
                    INSERT INTO snap.medium_links (
                        topics_id,
                        timespans_id,
                        source_media_id,
                        ref_media_id,
                        link_count
                    ) VALUES (
                        %(topics_id)s,
                        %(timespans_id)s,
                        %(source_media_id)s,
                        %(ref_media_id)s,
                        1
                    )
                """,
                {
                    'topics_id': self.topic['topics_id'],
                    'timespans_id': self.timespan['timespans_id'],
                    'source_media_id': medium['media_id'],
                    'ref_media_id': center_medium['media_id'],
                }
            )

        db.query(
            """
                INSERT INTO snap.medium_link_counts (
                    topics_id,
                    timespans_id,
                    media_id,
                    media_inlink_count,
                    outlink_count,
                    story_count,
                    inlink_count,
                    sum_media_inlink_count
                )
                    SELECT
                        topics_id,
                        timespans_id,
                        media_id,
                        media_id,
                        1,
                        1,
                        1,
                        1
                    FROM timespans AS t
                        CROSS JOIN media AS m
            """
        )

        tag_set = db.find_or_create('tag_sets', {'name': 'retweet_partisanship_2016_count_10'})
        tag = db.find_or_create('tags', {'tag_sets_id': tag_set['tag_sets_id'], 'tag': 'right'})
        db.find_or_create('color_sets', {'color': 'bb0404', 'color_set': 'partisan_retweet', 'id': 'right'})
        db.find_or_create('color_sets', {'color': '', 'color_set': 'partisan_retweet', 'id': 'right'})

        db.query(
            "INSERT INTO media_tags_map (media_id, tags_id) SELECT media_id, %(a)s FROM media",
            {'a': tag['tags_id']}
        )
