import networkx as nx

from topics_map.map import get_media_network, get_media_graph

from .setup_test_map import TestMap


class TestGetMediaGraph(TestMap):

    def test_get_media_graph(self):
        db = self.db

        media = get_media_network(db=db, timespans_id=self.timespan['timespans_id'])
        graph = get_media_graph(media=media)

        assert len(graph.nodes) == len(self.all_media)
        assert len(graph.edges) == len(self.connected_media) - 1

        media_id_attributes = nx.get_node_attributes(graph, 'media_id').items()
        assert len(media_id_attributes) == len(self.all_media)
        for (node, media_id) in media_id_attributes:
            assert node == media_id

        name_attributes = nx.get_node_attributes(graph, 'name').items()
        assert len(name_attributes) == len(self.all_media)
        for (node, name) in name_attributes:
            assert len(name) > 0

        media_inlink_count_attributes = nx.get_node_attributes(graph, 'media_inlink_count').items()
        assert len(media_inlink_count_attributes) == len(self.all_media)
        for (node, count) in media_inlink_count_attributes:
            assert count > 0
