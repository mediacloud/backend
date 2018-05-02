#!/usr/bin/env python

import sys

from fa2l import force_atlas2_layout
import networkx as nx
import matplotlib.pyplot as pyplot

import mediawords.util.log

log = mediawords.util.log.create_logger(__name__)


def main():
    if len(sys.argv) < 3:
        sys.exit('usage: %s < input gexf > < output gexf >' % sys.argv[0])

    infile = sys.argv[1]

    G = nx.read_gexf(infile)

    print(G.nodes(data=True))

    G = max(nx.weakly_connected_component_subgraphs(G), key=len)

    log.info("drawing layout...")
    pos = force_atlas2_layout(
        G,
        iterations=50,
        pos_list=None,
        node_masses=None,
        outbound_attraction_distribution=False,
        lin_log_mode=False,
        prevent_overlapping=False,
        edge_weight_influence=1.0,

        jitter_tolerance=1.0,
        barnes_hut_optimize=True,
        barnes_hut_theta=0.5,

        scaling_ratio=20,
        strong_gravity_mode=False,
        multithread=False,
        gravity=1.0)

    nodes = G.nodes()

    data_nodes = G.nodes(data=True)
    node_colors = ['#FF0000' if n[1]['partisan_retweet'] == 'right' else '#999999' for n in data_nodes]

    size_field = 'simple_tweet_count'
    max_node_size = 3000
    max_node_val = max([n[1][size_field] for n in data_nodes])
    node_sizes = [max_node_size * (n[1][size_field] / max_node_val) for n in data_nodes]

    node_labels = dict((n[0], n[1]['label']) for n in data_nodes)

    pyplot.figure(1, figsize=(24, 16))
    nx.draw_networkx_nodes(G, pos, nodelist=nodes, node_color=node_colors, node_size=node_sizes)
    nx.draw_networkx_labels(G, pos, nodelist=nodes, labels=node_labels)

    pyplot.show()


main()
