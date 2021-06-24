from topics_map.map import generate_graph, get_display_subgraph_by_attribute

from .setup_test_map import TestMap


class TestGetDisplaySubgraphByAttribute(TestMap):

    def test_get_display_subgraph_by_attribute(self):
        db = self.db

        graph = generate_graph(db=db, topics_id=self.timespan['topics_id'], timespans_id=self.timespan['timespans_id'])

        num_display_nodes = 10

        graph = get_display_subgraph_by_attribute(
            graph=graph,
            attribute='media_inlink_count',
            num_nodes=num_display_nodes,
        )

        assert len(graph.nodes) == num_display_nodes
