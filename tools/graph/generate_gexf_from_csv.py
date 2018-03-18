#!/usr/bin/env python3

# generate a gexf file from a node csv and an edges csv

import argparse
import csv
import networkx as nx
import re

import mediawords.util.log

logger = mediawords.util.log.create_logger(__name__)


def main():

    parser = argparse.ArgumentParser(description='generate a gexf file from nodes and edges csvs')
    parser.add_argument('--nodesfile', type=str, help="csv with nodes", required=True)
    parser.add_argument('--edgesfile', type=str, help="csv with edges", required=True)
    parser.add_argument('--gexffile', type=str, help="gexf output file", required=True)
    parser.add_argument('--dropedges', action="store_true", help="drop edges with missing nodes")
    parser.add_argument('--noprune', action="store_true", help="drop nodes not in giant component")

    args = parser.parse_args()

    with open(args.nodesfile) as f:
        csv_nodes = []
        for i, node in enumerate(csv.DictReader(f)):
            try:
                csv_nodes.append(node)
            except Exception as e:
                raise(ValueError("error importing node line %d: %s" % (i, e)))

    with open(args.edgesfile) as f:
        csv_edges = []
        for i, edge in enumerate(csv.DictReader(f)):
            try:
                csv_edges.append(edge)
            except Exception as e:
                raise(ValueError("error importing edge line %d: %s" % (i, e)))

    g = nx.DiGraph()

    node_lookup = {}

    for csv_node in csv_nodes:
        if 'stories_id' in csv_node and 'id' not in csv_node:
            csv_node['id'] = csv_node['stories_id']
            del(csv_node['stories_id'])

        if 'title' in csv_node and 'label' not in csv_node:
            csv_node['label'] = csv_node['title']
            del(csv_node['title'])

        for key in csv_node:
            if re.search('count$', key):
                try:
                    csv_node[key] = int(csv_node[key])
                except(ValueError):
                    csv_node[key] = 0

        if 'id' not in csv_node:
            raise(ValueError('node does not include valid id field: ' + str(csv_node)))

        g.add_node(csv_node['id'], csv_node)
        node_lookup[csv_node['id']] = csv_node

    for csv_edge in csv_edges:
        source = csv_edge['source'] or csv_edge['stories_id_a']
        target = csv_edge['target'] or csv_edge['stories_id_b']

        if source not in node_lookup or target not in node_lookup:
            if not args.dropedges:
                raise(ValueError('nodes list does not include source or target: ' + str(csv_edge)))
            else:
                continue

        g.add_edge(source, target)

    # g = max(nx.weakly_connected_component_subgraphs(g), key=len)
    component_graphs = sorted(nx.weakly_connected_component_subgraphs(g), key=len, reverse=True)
    giant_g = component_graphs.pop(0)

    dropped_nodes = []
    [dropped_nodes.extend(dropped_graph.nodes(data=True)) for dropped_graph in component_graphs]
    num_dropped_nodes = len(dropped_nodes)

    if args.noprune:
        logger.info("keeping %d nodes outside giant component" % num_dropped_nodes)
    else:
        g = giant_g

        if num_dropped_nodes > 0:
            logger.info("dropped %d nodes pruning to giant component" % num_dropped_nodes)
            [logger.debug("dropped node: %s" % str(n)) for n in dropped_nodes]

    nx.write_gexf(g, args.gexffile)


main()
