from topics_map.map import generate_and_draw_graph

from .setup_test_map import TestMap


class TestGenerateAndDrawGraph(TestMap):

    def test_generate_and_draw_graph(self):
        db = self.db

        svg = generate_and_draw_graph(
            db=db,
            topics_id=self.timespan['topics_id'],
            timespans_id=self.timespan['timespans_id'],
            memory_limit_mb=512,
        ).decode('UTF-8')

        assert len(svg) > 100 * len(self.connected_media)

        assert '<svg' in svg
