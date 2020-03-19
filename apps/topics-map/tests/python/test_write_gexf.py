from topics_map.map import generate_and_layout_graph, write_gexf

from .setup_test_map import TestMap


class TestWriteGEXF(TestMap):

    def test_write_gexf(self):
        db = self.db

        graph = generate_and_layout_graph(db=db, timespans_id=self.timespan['timespans_id'])

        gexf = write_gexf(graph)

        assert len(gexf) > 100 * len(self.connected_media)
