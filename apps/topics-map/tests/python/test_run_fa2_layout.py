import networkx as nx

from topics_map.map import generate_graph, run_fa2_layout

from .setup_test_map import TestMap


class TestRunFa2Layout(TestMap):

    def test_run_fa2_layout(self):
        db = self.db

        graph = generate_graph(db=db, timespans_id=self.timespan['timespans_id'])

        run_fa2_layout(graph=graph)

        positions = nx.get_node_attributes(graph, 'position')

        for n in graph.nodes:
            assert len(positions[n]) == 2
