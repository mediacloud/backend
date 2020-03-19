from topics_map.map import get_media_network, get_media_graph, remove_platforms_from_graph

from .setup_test_map import TestMap


class TestRemovePlatformsFromGraph(TestMap):

    def test_remove_platforms_from_graph(self):
        db = self.db

        media = get_media_network(db=db, timespans_id=self.timespan['timespans_id'])
        graph = get_media_graph(db=db, media=media)

        graph = remove_platforms_from_graph(graph=graph, platform_media_ids=[self.disconnected_media[0]['media_id'], ])

        assert len(graph.nodes) == len(self.all_media) - 1

        assert self.disconnected_media[0]['media_id'] not in graph.nodes
