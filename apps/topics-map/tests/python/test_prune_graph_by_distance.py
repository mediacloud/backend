from topics_map.map import get_media_network, get_media_graph, run_fa2_layout, prune_graph_by_distance

from .setup_test_map import TestMap


class TestPruneGraphByDistance(TestMap):

    def test_prune_graph_by_distance(self):
        db = self.db

        media = get_media_network(db=db, timespans_id=self.timespan['timespans_id'])
        graph = get_media_graph(media=media)

        assert len(graph.nodes) == len(self.all_media)

        run_fa2_layout(graph=graph)

        graph = prune_graph_by_distance(graph=graph)

        assert len(graph.nodes) == len(self.connected_media)
