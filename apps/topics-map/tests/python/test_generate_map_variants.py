import re

from mediawords.util.log import create_logger

log = create_logger(__name__)

from topics_map.map import generate_map_variants

from .setup_test_map import TestMap


class TestGenerateMapVariants(TestMap):

    def test_generate_and_store_maps(self):
        db = self.db

        formats = ['svg', 'gexf']
        colors = ['community', 'twitter_partisanship']
        sizes = ['author_count', 'post_count']

        maps = generate_map_variants(
            db=db, 
            timespans_id=self.timespan['timespans_id'], 
            memory_limit_mb=512,
            size_bys=sizes,
            color_bys=colors)

        maps = list(maps)

        # stupid sanity test to make sure some content is being generated
        for map in maps:
            log.warning(f"{map['color_by']} {map['size_by']} {map['format']}")
            assert len(map['content']) > 1024

        expected_num_maps = len(colors) * len(sizes) * len(formats)

        assert len(maps) == expected_num_maps

        assert len(set([m['format'] + m['color_by'] + m['size_by'] for m in maps])) == expected_num_maps
