from topics_map.map import generate_and_store_maps

from .setup_test_map import TestMap


class TestGenerateAndStoreMaps(TestMap):

    def test_generate_and_store_maps(self):
        db = self.db

        generate_and_store_maps(db=db, timespans_id=self.timespan['timespans_id'], memory_limit_mb=512)

        timespan_maps = db.query(
            "SELECT * FROM timespan_maps WHERE timespans_id = %(a)s",
            {'a': self.timespan['timespans_id']}
        ).hashes()

        formats = ('gexf', 'svg')

        assert len(timespan_maps) == 2 * len(formats)

        for ts_map in timespan_maps:
            assert ts_map['format'] in formats
            assert len(ts_map['content']) > 100 * len(self.connected_media)
