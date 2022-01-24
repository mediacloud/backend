import networkx as nx

from mediawords.util.log import create_logger

log = create_logger(__name__)

from topics_map.map import generate_graph, add_attribute_to_graph

from .setup_test_map import TestMap


class TestGenerateMapVariants(TestMap):

    def test_generate_and_store_maps(self):
        db = self.db

        graph = generate_graph(db=db, topics_id=self.timespan['topics_id'], timespans_id=self.timespan['timespans_id'])

        media_names = [{'media_id': m['media_id'], 'value': m['name']} for m in self.all_media]

        attribute = {'name': 'media_name', 'data': media_names}

        add_attribute_to_graph(graph, attribute)

        node_media_names = nx.get_node_attributes(graph, 'media_name')
        node_names = nx.get_node_attributes(graph, 'name')

        log.warning(node_media_names)
        log.warning(node_names)

        for i in node_names:
            assert node_media_names[i] == node_names[i]
