from lxml import etree
from unittest import TestCase

import networkx as nx

import mediawords.db
import topics_map.map
from topics_map.map import *
from mediawords.test.db.create import create_test_medium, create_test_topic, create_test_timespan

NUM_CONNECTED_MEDIA = 100
NUM_DISCONNECTED_MEDIA = 10

class TestMap(TestCase):

    def setUp(self):
        self.db = mediawords.db.connect_to_db()

        db = self.db

        db.query("delete from media")
        db.query("delete from topics")

        self.connected_media = []
        for i in range(NUM_CONNECTED_MEDIA):
            self.connected_media.append(create_test_medium(db, 'connected %d' % i))
            
        self.disconnected_media = []
        for i in range(NUM_DISCONNECTED_MEDIA):
            self.disconnected_media.append(create_test_medium(db, 'disconnected %d' %i))

        self.all_media = self.connected_media + self.disconnected_media

        self.topic = create_test_topic(db, 'foo')
        self.timespan = create_test_timespan(db, self.topic)

        center_medium = self.connected_media[0]
        for medium in self.connected_media[1:]:
            db.query(
                """
                insert into snap.medium_links (timespans_id, source_media_id, ref_media_id, link_count)
                    values(%(a)s, %(b)s, %(c)s, 1)
                """,
                {'a': self.timespan['timespans_id'], 'b': medium['media_id'], 'c': center_medium['media_id']}
            )

        db.query(
            """
            insert into snap.medium_link_counts
                (timespans_id, media_id,
                    media_inlink_count, outlink_count, story_count, inlink_count, sum_media_inlink_count)
                select timespans_id, media_id, media_id, 1, 1, 1, 1
                    from timespans t
                        cross join media m
            """
        )

        tag_set = db.find_or_create('tag_sets', {'name': 'retweet_partisanship_2016_count_10'})
        tag = db.find_or_create('tags', {'tag_sets_id': tag_set['tag_sets_id'], 'tag': 'right'})
        db.find_or_create('color_sets', {'color': 'bb0404', 'color_set': 'partisan_retweet', 'id': 'right'})
        db.find_or_create('color_sets', {'color': '', 'color_set': 'partisan_retweet', 'id': 'right'})

        db.query(
            "insert into media_tags_map (media_id, tags_id) select media_id, %(a)s from media",
            {'a': tag['tags_id']}
        )

    def test_get_media_network(self):
        db = self.db

        got_media = get_media_network(db, self.timespan['timespans_id'])

        assert len(got_media) == len(self.all_media)

        for m in got_media:
            assert m['media_id'] in [m['media_id'] for m in self.all_media]

    def test_get_media_graph(self):
        db = self.db

        media = get_media_network(db, self.timespan['timespans_id'])
        graph = get_media_graph(db, media)

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

    def test_remoove_platforms_from_graph(self):
        db = self.db

        media = get_media_network(db, self.timespan['timespans_id'])
        graph = get_media_graph(db, media)

        topics_map.map.PLATFORM_MEDIA_IDS = [self.disconnected_media[0]['media_id'],]

        graph = remove_platforms_from_graph(graph)

        assert len(graph.nodes) == len(self.all_media) - 1

        assert self.disconnected_media[0]['media_id'] not in graph.nodes

    def test_get_giant_component(self):
        db = self.db

        media = get_media_network(db, self.timespan['timespans_id'])
        graph = get_media_graph(db, media)

        assert len(graph.nodes) == len(self.all_media)

        graph = get_giant_component(graph)

        assert len(graph.nodes) == len(self.connected_media)

    def test_run_fa2_layout(self):
        db = self.db

        graph = generate_graph(db, self.timespan['timespans_id'])

        run_fa2_layout(graph)

        positions = nx.get_node_attributes(graph, 'position')

        for n in graph.nodes:
            assert len(positions[n]) == 2

    def test_get_display_subgraph_by_attribute(self):
        db = self.db

        graph = generate_graph(db, self.timespan['timespans_id'])

        num_display_nodes = 10

        graph = get_display_subgraph_by_attribute(graph, 'media_inlink_count', num_display_nodes)

        assert len(graph.nodes) == num_display_nodes


    def test_prune_graph_by_distance(self):
        db = self.db

        media = get_media_network(db, self.timespan['timespans_id'])
        graph = get_media_graph(db, media)

        assert len(graph.nodes) == len(self.all_media)

        run_fa2_layout(graph)

        graph = prune_graph_by_distance(graph)

        assert len(graph.nodes) == len(self.connected_media)


    def test_generate_and_draw_graph(self):
        db = self.db

        svg = generate_and_draw_graph(db, self.timespan['timespans_id']).decode('UTF-8')

        assert len(svg) > 100 * len(self.connected_media)

        assert '<svg' in svg


    def test_write_gexf(self):
        db = self.db

        graph = generate_and_layout_graph(db, self.timespan['timespans_id'])

        gexf = write_gexf(graph)

        assert len(gexf) > 100 * len(self.connected_media)

    def test_generate_and_store_maps(self):
        db = self.db

        generate_and_store_maps(db, self.timespan['timespans_id'])

        timespan_maps = db.query(
            "select * from timespan_maps where timespans_id = %(a)s",
            {'a': self.timespan['timespans_id']}
        ).hashes()

        formats = ('gexf', 'svg')

        assert len(timespan_maps) == 2 * len(formats)

        for map in timespan_maps:
            assert map['format'] in formats
            assert len(map['content']) > 100 * len(self.connected_media)
