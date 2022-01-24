import xmltodict

from topics_map.map import generate_and_layout_graph, write_gexf

from .setup_test_map import TestMap

from mediawords.util.log import create_logger

log = create_logger(__name__)

class TestWriteGEXF(TestMap):

    def test_write_gexf(self):
        db = self.db

        graph = generate_and_layout_graph(
            db=db,
            topics_id=self.timespan['topics_id'],
            timespans_id=self.timespan['timespans_id'],
            memory_limit_mb=512,
        )

        gexf = write_gexf(graph)

        assert len(gexf) > 100 * len(self.connected_media)

        data = xmltodict.parse(gexf)

        nodes = data['gexf']['graph']['nodes']['node']
        assert len(nodes) == len(nodes)

        attributes = data['gexf']['graph']['attributes']['attribute']
        attribute_titles = [a['@title'] for a in attributes]

        fields = 'media_id media_inlink_count post_count author_count channel_count'.split()
        for field in fields:
            assert field in attribute_titles, field
