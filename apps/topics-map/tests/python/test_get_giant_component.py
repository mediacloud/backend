from topics_map.map import get_media_network, get_media_graph, get_giant_component

from .setup_test_map import TestMap


class TestGetGiantComponent(TestMap):

    def test_get_giant_component(self):
        db = self.db

        media = get_media_network(db=db, timespans_id=self.timespan['timespans_id'])
        graph = get_media_graph(media=media)

        assert len(graph.nodes) == len(self.all_media)

        graph = get_giant_component(graph=graph)

        assert len(graph.nodes) == len(self.connected_media)
