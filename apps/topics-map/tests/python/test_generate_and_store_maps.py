import re

from mediawords.util.log import create_logger

log = create_logger(__name__)

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
            log.warning(ts_map['url'])
            assert ts_map['format'] in formats
            assert re.match(r'https://.*.s3.amazonaws.com/test/[0-9]+/.*/[0-9]+', ts_map['url'])
