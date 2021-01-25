import io
import networkx as nx
import numpy as np
from scipy.sparse import coo_matrix
from typing import Dict

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


# forceatlas2_layout function adapted from https://github.com/tpoisot/nxfa2
def __forceatlas2_layout(graph: nx.Graph,
                         iterations: int = 10,
                         linlog: bool = False,
                         pos: np.core.records.ndarray = None,
                         nohubs: bool = False,
                         dim: int = 2,
                         scale: float = 1) -> Dict:
    """
    Options values are
    graph            The graph to layout
    iterations       Number of iterations to do
    linlog           Whether to use linear or log repulsion
    nohubs           Whether to use hub repulsion
    dim              Num of dimensions
    scale            Scaling factor for size of map
    """

    min_length = 0.001

    # We add attributes to store the current and previous convergence speed
    for n in graph:
        graph.node[n]['prevcs'] = 0
        graph.node[n]['currcs'] = 0
        # To numpy matrix
    # This comes from the spares FR layout in nx
    graph_adj_matrix = nx.to_scipy_sparse_matrix(graph, dtype='f')
    nnodes, _ = graph_adj_matrix.shape

    # noinspection PyBroadException
    try:
        graph_adj_matrix = graph_adj_matrix.tolil()
    except Exception:
        graph_adj_matrix = (coo_matrix(graph_adj_matrix)).tolil()

    if pos is None:
        pos = np.asarray(np.random.random((nnodes, dim)), dtype=graph_adj_matrix.dtype)
    else:
        pos = pos.astype(graph_adj_matrix.dtype)

    k = np.sqrt(1.0 / nnodes)

    # the initial "temperature" is about .1 of domain area (=1x1)
    # this is the largest step allowed in the dynamics.
    t = 0.1

    # simple cooling scheme.
    # linearly step down by dt on each iteration so last iteration is size dt.
    dt = t / float(iterations + 1)
    displacement = np.zeros((dim, nnodes))
    for iteration in range(iterations):
        displacement *= 0
        # loop over rows
        for i in range(graph_adj_matrix.shape[0]):
            # difference between this row's node position and all others
            delta = (pos[i] - pos).T
            # distance between points
            distance = np.sqrt((delta ** 2).sum(axis=0))
            # enforce minimum distance
            distance = np.where(distance < min_length, min_length, distance)
            # the adjacency matrix row
            adj_matrix_row = np.asarray(graph_adj_matrix.getrowview(i).toarray())
            # displacement "force"
            displacement_force = (k * k / distance ** 2) * scale
            if nohubs:
                displacement_force = displacement_force / float(adj_matrix_row.sum(axis=1) + 1)
            if linlog:
                displacement_force = np.log(displacement_force + 1)
            displacement[:, i] += \
                (delta * (displacement_force - adj_matrix_row * distance / k)).sum(axis=1)
            # update positions
        length = np.sqrt((displacement ** 2).sum(axis=0))
        length = np.where(length < min_length, min_length, length)
        pos += (displacement * t / length).T
        # cool temperature
        t -= dt

    # Return the layout
    return dict(zip(graph, pos))


def py_layout_gexf(gexf: str) -> Dict:
    """Accept a gexf graph, run force atlas on it, return the resulting laid out graph."""

    gexf = decode_object_from_bytes_if_needed(gexf)

    in_fh = io.StringIO(gexf)
    graph = nx.read_gexf(in_fh)

    layout = __forceatlas2_layout(graph=graph, iterations=100, scale=1)

    scale = 5000

    int_layout = dict()
    for layout_id in layout:
        pos = layout[layout_id]
        int_layout[layout_id] = (int(pos[0] * scale), int(pos[1] * scale))

    return int_layout


def __weakly_connected_component_subgraphs(G, copy=True):
    for c in nx.weakly_connected_components(G):
        if copy:
            yield G.subgraph(c).copy()
        else:
            yield G.subgraph(c)


def py_giant_component(edges: list) -> list:
    """Accept a list of edges as pairs of ids and return only the edges that are within the giant component."""
    ids = []
    for edge in edges:
        ids += edge

    graph = nx.DiGraph()

    [graph.add_node(id) for id in ids]
    [graph.add_edge(edge[0], edge[1]) for edge in edges]

    weak_graphs = list(__weakly_connected_component_subgraphs(graph))

    if len(weak_graphs) < 1:
        return []

    graph = max(weak_graphs, key=len)

    return list(graph.edges())
