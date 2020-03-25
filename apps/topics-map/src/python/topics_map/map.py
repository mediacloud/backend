"""
generate network maps for topics
"""

import io
import math
import os
import subprocess
import tempfile
from typing import Optional, List, Dict, Any, Tuple

import community
import matplotlib.pyplot as plt
import networkx as nx

from mediawords.db import DatabaseHandler
from mediawords.util.colors import get_consistent_color, hex_to_rgb
from mediawords.util.log import create_logger
from mediawords.util.parse_json import encode_json

log = create_logger(__name__)

DEFAULT_PLATFORM_MEDIA_IDS = [
    18362, 18346, 18370, 61164, 269331, 73449, 62926, 21936, 5816, 4429, 20448, 67324, 351789, 22299, 135076, 25373,
]
"""list of platform media sources, which are excluded from maps by default"""

PLOT_SIZE = 18
"""create matplotlib figure with figsize(PLOT_SIZE, PLOT_SIZE)"""

PLOT_DPI = 600
"""estimated dpi of plot"""

MAX_NODE_SIZE = 800
"""size of the largest node"""


def add_partisan_retweet_to_snapshot_media(db: DatabaseHandler, timespans_id: int, media: List[Dict[str, Any]]) -> None:
    """Add partisan_retweet field to list of snapshotted media."""
    label = 'partisan_retweet'

    partisan_tags = db.query(
        """
            SELECT
                dmtm.*,
                dt.tag
            FROM snap.media_tags_map AS dmtm
                JOIN tags AS dt ON ( dmtm.tags_id = dt.tags_id )
                JOIN tag_sets AS dts ON ( dts.tag_sets_id = dt.tag_sets_id )
                JOIN timespans AS t USING ( snapshots_id )
            WHERE dts.name = 'retweet_partisanship_2016_count_10'
              AND t.timespans_id = %(a)s
        """,
        {'a': timespans_id}
    ).hashes()

    partisan_map = {pt['media_id']: pt['tag'] for pt in partisan_tags}

    for medium in media:
        medium[label] = partisan_map.get(medium['media_id'], 'null')


def get_media_network(db: DatabaseHandler, timespans_id: int) -> List[Dict[str, Any]]:
    """Get a network of media and edges for the topic."""
    media = db.query(
        """
            SELECT
                m.media_id,
                m.name,
                mlc.media_inlink_count
            FROM media AS m
                JOIN snap.medium_link_counts AS mlc USING ( media_id )
            where
                mlc.timespans_id = %(a)s
        """,
        {'a': timespans_id}
    ).hashes()

    medium_links = db.query(
        "SELECT * FROM snap.medium_links WHERE timespans_id = %(a)s",
        {'a': timespans_id}
    ).hashes()

    media_lookup = {m['media_id']: m for m in media}

    for medium in media:
        media_lookup[medium['media_id']] = medium

    for medium_link in medium_links:
        if medium_link['source_media_id'] in media_lookup:
            medium = media_lookup[medium_link['source_media_id']]
            medium.setdefault('links', [])
            medium['links'].append(medium_link)

    add_partisan_retweet_to_snapshot_media(db=db, timespans_id=timespans_id, media=media)

    return media


def get_media_graph(media: List[Dict[str, Any]]) -> nx.Graph:
    """Get a networkx graph describing the media network of the topic."""
    graph = nx.Graph()

    [graph.add_node(m['media_id']) for m in media]

    media_lookup = {m['media_id']: m for m in media}

    nx.set_node_attributes(graph, media_lookup)

    for medium in media:
        if 'links' in medium:
            for e in medium['links']:
                graph.add_edge(
                    e['source_media_id'],
                    e['ref_media_id'],
                    weight=e['link_count']
                )

    return graph


def remove_platforms_from_graph(graph: nx.Graph, platform_media_ids: Optional[List[int]] = None) -> nx.Graph:
    """Remove nodes in PLATFORM_MEDIA_IDS from the graph.
    
    Return the resulting subgraph.
    """

    if not platform_media_ids:
        platform_media_ids = DEFAULT_PLATFORM_MEDIA_IDS

    platform_lookup = {media_id: True for media_id in platform_media_ids}
    include_nodes = []

    for node in graph.nodes():
        if node not in platform_lookup:
            include_nodes.append(node)

    return graph.subgraph(include_nodes)


def run_fa2_layout(graph: nx.Graph, memory_limit_mb: int) -> None:
    """Generate force atlas 2 layout for the graph.

    Run an external java library on the graph to assign a position to each node.

    Assign a 'position' attribute to each node in the graph that is a [x, y] tuple.
    """

    with tempfile.TemporaryDirectory('topic_map') as temp_dir:

        input_file = os.path.join(temp_dir, 'input.gexf')
        output_template = os.path.join(temp_dir, 'output')
        output_file = output_template + ".txt"

        export_graph = graph.copy()
        for node in export_graph.nodes(data=True):
            for key in list(node[1].keys()):
                del node[1][key]

        nx.write_gexf(export_graph, input_file)

        log.info("running layout...")

        output = subprocess.check_output(
            [
                "java",
                "-Djava.awt.headless=true",
                f"-Xmx{memory_limit_mb}m",
                "-cp", "/opt/fa2l/forceatlas2.jar:/opt/fa2l/gephi-toolkit.jar",
                "kco.forceatlas2.Main",
                "--input", input_file,
                "--targetChangePerNode", "0.5",
                "--output", output_template,
                "--directed",
                # "--scalingRatio", "10",
                # "--gravity", "100",
                "--2d"
            ],
        )

        assert isinstance(output, bytes)
        output = output.decode('utf-8', errors='replace')

        log.info(f"fa2 layout: {str(output)}")

        f = open(output_file)
        lines = f.readlines()

        del lines[0]

        for line in lines:
            (i, x, y) = line.split()

            i = int(i)
            x = float(x)
            y = float(y)

            graph.nodes[i]['position'] = [x, y]


def assign_colors(db: DatabaseHandler, graph: nx.Graph, color_by: str) -> None:
    """Assign a 'color' attribute to each node in the graph.

    Each color will be in '#FFFFFF' format.

    For now, this just assigns a color based on the partisan_retweet categorization, but it should support
    other options, or at least not use partisan_retweet if it is not a U.S. topic.
    """
    log.warning(f'assign colors by {color_by}')
    for n in graph.nodes:
        value = str(graph.nodes[n].get(color_by, 'null'))
        graph.nodes[n]['color'] = get_consistent_color(db, color_by, value)


def assign_sizes(graph: nx.Graph, attribute: str, scale: int = MAX_NODE_SIZE) -> None:
    """Assign a 'size' attribute to each node in the graph, according to the given attribute.

    Assumes that the attribute has only numbers as values.  Assign 'scale' as the size of the node
    with the largest value for that attribute, and assign proportionally smaller sizes for the rest
    of the nodes.
    """
    if len(graph.nodes) < 1:
        return

    node_values = nx.get_node_attributes(graph, attribute).items()

    max_value = max([n[1] for n in node_values]) + 1

    sizes = {n[0]: {'size': (n[1] / max_value) * scale} for n in node_values}

    nx.set_node_attributes(graph, sizes)


def get_display_subgraph_by_attribute(graph: nx.Graph, attribute: str, num_nodes: int) -> nx.Graph:
    """Get a subgraph with only the top num_nodes nodes by attribute."""
    nodes_with_values = nx.get_node_attributes(graph, attribute).items()

    sorted_nodes_with_values = sorted(nodes_with_values, key=lambda n: n[1], reverse=True)

    include_node_ids = [n[0] for n in sorted_nodes_with_values[0:num_nodes]]

    include_nodes = []
    for node in graph.nodes():
        if node in include_node_ids:
            include_nodes.append(node)

    return graph.subgraph(include_nodes)


def prune_graph_by_distance(graph: nx.Graph) -> nx.Graph:
    """Get a subgraph with far flung nodes pruned.
    
    Many graphs end up with a few far flung nodes that distort the whole map.  This
    function computes the mean distances from the center of the graph and removes
    any nodes that are more than 2.5x the average distance.
    """
    if len(graph.nodes) == 0:
        return graph

    positions = nx.get_node_attributes(graph, 'position')
    center_x = sum([positions[n][0] for n in graph.nodes()]) / len(graph.nodes())
    center_y = sum([positions[n][1] for n in graph.nodes()]) / len(graph.nodes())

    distance_map = {}
    for node in graph.nodes():
        node_x = positions[node][0]
        node_y = positions[node][1]
        distance = math.sqrt((node_x - center_x) ** 2 + (node_y - center_y) ** 2)
        distance_map[node] = distance

    mean_distance = sorted(distance_map.values())[int(len(distance_map.values()) / 2)]
    max_distance = mean_distance * 2

<<<<<<< HEAD
=======
    log.warning(f"Mean distance: {mean_distance}")

>>>>>>> master
    include_nodes = []
    for node in graph.nodes():
        if distance_map[node] <= max_distance:
            include_nodes.append(node)

    return graph.subgraph(include_nodes)


def get_labels_by_attribute(graph: nx.Graph,
                            label_attribute: str,
                            rank_attribute: str,
                            iteration: int,
                            num_labels: int) -> Dict[int, str]:
    """Get the num_labels labels according to rank_attribute, starting at the offset iteration * num_labels.
    
    Also truncate each label to a max length of 16.

    Return a dict of {node: label}.
    """
    offset = iteration * num_labels

    ranks = nx.get_node_attributes(graph, rank_attribute)

    nodes = [n[0] for n in sorted(ranks.items(), key=lambda x: x[1], reverse=True)][offset:offset + num_labels]

    labels = nx.get_node_attributes(graph, label_attribute)

    max_label_size = 16
    for k in labels.keys():
        labels[k] = labels[k][0:max_label_size] + '..' if len(labels[k]) > max_label_size else labels[k]

    return {n: labels[n] for n in nodes}


def assign_labels(graph: nx.Graph, attribute: str = 'name'):
    """Assign a 'label' attribute to each node as the value of the given attribute.

    Truncate all labels at 16 characters.
    """
    labels = nx.get_node_attributes(graph, attribute)

    max_label_size = 16
    for k in labels.keys():
        labels[k] = labels[k][0:max_label_size] + '..' if len(labels[k]) > max_label_size else labels[k]

    nx.set_node_attributes(graph, {n: {'label': labels[n]} for n in graph.nodes})


def rotate(x: int, y: int, d: int) -> Tuple[float, float]:
    """Rotate the point around (0,0) by d degrees"""
    r = math.radians(d)

    cosr = math.cos(r)
    sinr = math.sin(r)

    rx = (cosr * x) - (sinr * y)
    ry = (sinr * x) + (cosr * y)

    return rx, ry


def rotate_right_to_right(graph: nx.Graph) -> None:
    """Rotate the graph so that the partisan_retweet:right nodes are to the right.
    
    Assign the rotated positions to the graph nodes.
    """
    partisan = nx.get_node_attributes(graph, 'partisan_retweet')
    right_nodes = list(filter(lambda n: partisan[n] == 'right', graph.nodes()))

    positions = nx.get_node_attributes(graph, 'position')

    best_rotation = 0
    max_sum_x = 0
    for rotation in range(0, 350, 10):
        rotated_positions = {n: rotate(x=positions[n][0], y=positions[n][1], d=rotation) for n in right_nodes}
        sum_x = sum([p[0] for p in rotated_positions.values()])
        if sum_x > max_sum_x:
            max_sum_x = sum_x
            best_rotation = rotation

    for n in graph.nodes:
        graph.nodes[n]['position'] = rotate(x=positions[n][0], y=positions[n][1], d=best_rotation)


def get_pixel_positions(positions: Dict[int, Tuple[float, float]]) -> Dict[int, Tuple[float, float]]:
    """Given graph coordinates, convert to pixels within the matlplotlib figure.

    Positions for matplotlib are relative, so we need to convert to actual pixels to be able
    to determine whether there are overlaps based on node size.
    """
    max_x = max([p[0] for p in positions.values()])
    min_x = min([p[0] for p in positions.values()])
    max_y = max([p[1] for p in positions.values()])
    min_y = min([p[1] for p in positions.values()])

    delta_x = max_x - min_x
    delta_y = max_y - min_y

    total_pixels = PLOT_SIZE * PLOT_DPI

    pixel_positions = {}
    for k in positions.keys():
        (x, y) = positions[k]
        xpix = ((x - min_x) / delta_x) * total_pixels
        ypix = ((y - min_y) / delta_y) * total_pixels
        pixel_positions[k] = (xpix, ypix)

    return pixel_positions


def scale_until_no_overlap(graph: nx.Graph) -> None:
    """Expand the positions until there are no overlaps among the top 50 nodes.
    
    Return sizes with the smallest non-overlap expansion, up to 3x.
    """
    pixels = get_pixel_positions(positions=nx.get_node_attributes(graph, 'position'))
    sizes = nx.get_node_attributes(graph, 'size')

    ranks = nx.get_node_attributes(graph, 'size')
    top_nodes = [n[0] for n in sorted(ranks.items(), key=lambda x: x[1], reverse=True)][0:50]

    expansion = 1
    collision = None
    while expansion < 9:
        nodes_list = top_nodes
        for i in range(len(nodes_list) - 1):
            collision = False
            for j in range(i + 1, len(nodes_list)):
                a = nodes_list[i]
                b = nodes_list[j]
                distance = math.sqrt((pixels[a][0] - pixels[b][0]) ** 2 + (pixels[a][1] - pixels[b][1]) ** 2)
                if distance < (sizes[a] * expansion + sizes[b] * expansion):
                    collision = True
                    break

            if collision:
                break

        if collision:
            break
        else:
            expansion += 0.1

    log.info(f"scale to avoid overlap: {expansion}")

    for n in graph.nodes:
        graph.nodes[n]['size'] = sizes[n] * (expansion - 0.1)


def draw_labels(graph: nx.Graph) -> None:
    """Draw labels, sizing by cohorts."""
    positions = nx.get_node_attributes(graph, 'position')
    num_cohorts = 30
    num_labeled_cohorts = num_cohorts
    cohort_size = int(len(graph.nodes()) / num_cohorts)
    for i in range(num_labeled_cohorts):
        labels = get_labels_by_attribute(
            graph=graph,
            label_attribute='name',
            rank_attribute='media_inlink_count',
            iteration=i,
            num_labels=cohort_size,
        )
        weight = 'bold' if i == 0 else 'normal'
        alpha = 1.0 if i == 0 else 0.5
        font_size = 8 if i == 0 else 2

        nx.draw_networkx_labels(
            G=graph,
            pos=positions,
            labels=labels,
            font_size=font_size,
            font_weight=weight,
            alpha=alpha
        )


def draw_graph(graph: nx.Graph, graph_format: str = 'svg') -> bytes:
    """Draw the graph using matplotlib.

    Use the position, color, size, and label node attributes from the graph.

    Return the data of the resulting svg file.
    """
    positions = nx.get_node_attributes(graph, 'position')
    colors = ['#' + c for c in nx.get_node_attributes(graph, 'color').values()]
    sizes = list(nx.get_node_attributes(graph, 'size').values())

    fig = plt.figure(figsize=(PLOT_SIZE, PLOT_SIZE))
    fig.set_facecolor('#FFFFFF')

    nx.draw_networkx_nodes(
        G=graph,
        pos=positions,
        node_size=sizes,
        with_labels=False,
        node_color=colors,
        alpha=0.7
    )

    draw_labels(graph=graph)

    plt.axis('off')

    if graph_format == 'draw':
        fig.show()
    else:
        buf = io.BytesIO()
        fig.savefig(buf, format=graph_format)
        plt.close(fig)
        buf.seek(0)
        return buf.read()


def get_giant_component(graph: nx.Graph) -> nx.Graph:
    """Return the giant component subgraph of the graph."""
    components = sorted(nx.connected_components(graph), key=len)

    return graph.subgraph(components[-1]) if len(components) > 0 else graph


def generate_graph(db: DatabaseHandler, timespans_id: int) -> nx.Graph:
    """Generate a graph of the network of media for the given timespan, but do not layout."""
    media = get_media_network(db=db, timespans_id=timespans_id)
    graph = get_media_graph(media=media)

    log.info(f"initial graph: {len(graph.nodes())} nodes")

    graph = get_giant_component(graph=graph)

    log.info(f"graph after giant component: {len(graph.nodes())} nodes")

    graph = remove_platforms_from_graph(graph=graph)

    log.info(f"graph after platform removal: {len(graph.nodes())} nodes")

    return graph


def assign_communities(graph: nx.Graph) -> None:
    """Run louvain community detection and assign result to 'community' attribute for each node."""
    resolution = 1.5
    log.warning(f"generating communities with resolution {resolution}...")
    communities = community.best_partition(graph=graph, resolution=resolution)

    for n in graph.nodes:
        graph.nodes[n]['community'] = communities[n]


def generate_and_layout_graph(db: DatabaseHandler,
                              timespans_id: int,
                              memory_limit_mb: int,
                              color_by: str = 'community') -> nx.Graph:
    """Generate and layout a graph of the network of media for the given timespan.
    
    The layout algorithm is force atlas 2, and the resulting is 'position' attribute added to each node.
    """
    graph = generate_graph(db=db, timespans_id=timespans_id)
    # run layout with all nodes in giant component, before reducing to smaler number to display
    run_fa2_layout(graph=graph, memory_limit_mb=memory_limit_mb)

    graph = get_display_subgraph_by_attribute(graph=graph, attribute='media_inlink_count', num_nodes=1000)
    log.info(f"graph after attribute ranking: {len(graph.nodes())} nodes")

    graph = prune_graph_by_distance(graph=graph)
    log.info(f"graph after far flung node pruning: {len(graph.nodes())} nodes")

    assign_communities(graph=graph)

    assign_colors(db=db, graph=graph, color_by=color_by)

    assign_sizes(graph=graph, attribute='media_inlink_count')

    rotate_right_to_right(graph=graph)

    assign_labels(graph=graph)

    return graph


def generate_and_draw_graph(db: DatabaseHandler,
                            timespans_id: int,
                            memory_limit_mb: int,
                            graph_format: str = 'svg') -> bytes:
    """Generate, layout, and draw a graph of the media network for the given timespan."""
    graph = generate_and_layout_graph(db=db, timespans_id=timespans_id, memory_limit_mb=memory_limit_mb)

    return draw_graph(graph=graph, graph_format=graph_format)


def write_gexf(graph: nx.Graph) -> bytes:
    """Return a gexf representation of the graph.

    Convert position, color, and size into viz:position and viz:color as expected for gexf.
    """
    for n in graph.nodes:
        (r, g, b) = hex_to_rgb(graph.nodes[n]['color'])
        graph.nodes[n]['viz'] = {
            'r': r,
            'g': g,
            'b': b,
            'x': graph.nodes[n]['position'][0],
            'y': graph.nodes[n]['position'][1],
            'size': graph.nodes[n]['size']
        }

    export_graph = graph.copy()
    for node in export_graph.nodes(data=True):
        for key in ('position', 'color', 'size', 'links'):
            if key in node[1]:
                del node[1][key]

    buf = io.BytesIO()

    nx.write_gexf(export_graph, buf)

    buf.seek(0)

    return buf.read()


def store_map(db: DatabaseHandler,
        timespans_id: int,
        content: bytes,
        graph_format: str,
        color_by: str) -> None:
    """Create a timespans_map row."""
    db.begin()

    options = {'color_by': color_by}
    options_json = encode_json(options)

    db.query(
        """
            DELETE FROM timespan_maps
            WHERE timespans_id = %(a)s
              AND format = %(b)s
              AND options = %(c)s
        """,
        {'a': timespans_id, 'b': graph_format, 'c': options_json}
    )

    timespan_map = {
        'timespans_id': timespans_id,
        'options': options_json,
        'format': graph_format
    }

    db.create('timespan_maps', timespan_map)

    db.commit()

    content_types = {
        'svg' => 'image/svg+xml',
        'gexf' => 'xml/gexf'
    }
    content_type = content_types[graph_format]

    store_content(db, TIMESPAN_MAPS_TYPE, timespan_map['timespan_maps_id'], content, content_type)

    url = get_content_url(TIMESPAN_MAPS_TYPE, timespan_map['timespan_maps_id'])

    db.update_by_id('timespan_maps', timespan_map['timespan_maps_id'], {'url': url})


def generate_and_store_maps(db: DatabaseHandler, timespans_id: int, memory_limit_mb: int) -> None:
    """Generate and layout graph and store various formats of the graph in timespans_maps."""
    graph = generate_and_layout_graph(db=db, timespans_id=timespans_id, memory_limit_mb=memory_limit_mb)

    for color_by in ('community', 'partisan_retweet'):
        assign_colors(db=db, graph=graph, color_by=color_by)

        image = write_gexf(graph=graph)
        store_map(db=db, timespans_id=timespans_id, content=image, graph_format='gexf', color_by=color_by)

        image = draw_graph(graph=graph, graph_format='svg')
        store_map(db=db, timespans_id=timespans_id, content=image, graph_format='svg', color_by=color_by)
