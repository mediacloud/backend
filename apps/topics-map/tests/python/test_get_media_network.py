from topics_map.map import get_media_network

from .setup_test_map import TestMap


class TestGetMediaNetwork(TestMap):

    def test_get_media_network(self):
        db = self.db

        got_media = get_media_network(
            db=db,
            topics_id=self.timespan['topics_id'],
            timespans_id=self.timespan['timespans_id'],
        )

        assert len(got_media) == len(self.all_media)

        for m in got_media:
            assert m['media_id'] in [m['media_id'] for m in self.all_media]
