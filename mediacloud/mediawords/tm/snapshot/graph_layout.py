from scipy.sparse import spdiags, coo_matrix

import forceatlas2
import io
import networkx as nx
import numpy as np
import scipy as sp
import typing

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

l = create_logger(__name__)

# forceatlas2_layout function copied from https://github.com/tpoisot/nxfa2
def forceatlas2_layout(G, iterations=10, linlog=False, pos=None, nohubs=False,
                       kr=0.001, k=None, dim=2):
    """
    Options values are
    g                The graph to layout
    iterations       Number of iterations to do
    linlog           Whether to use linear or log repulsion
    random_init      Start with a random position
                     If false, start with FR
    avoidoverlap     Whether to avoid overlap of points
    degreebased      Degree based repulsion
    """
    # We add attributes to store the current and previous convergence speed
    for n in G:
        G.node[n]['prevcs'] = 0
        G.node[n]['currcs'] = 0
        # To numpy matrix
    # This comes from the spares FR layout in nx
    A = nx.to_scipy_sparse_matrix(G, dtype='f')
    nnodes, _ = A.shape

    try:
        A = A.tolil()
    except Exception as e:
        A = (coo_matrix(A)).tolil()
    if pos is None:
        pos = np.asarray(np.random.random((nnodes, dim)), dtype=A.dtype)
    else:
        pos = pos.astype(A.dtype)
    if k is None:
        k = np.sqrt(1.0 / nnodes)
        # Iterations
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
        for i in range(A.shape[0]):
            # difference between this row's node position and all others
            delta = (pos[i] - pos).T
            # distance between points
            distance = np.sqrt((delta ** 2).sum(axis=0))
            # enforce minimum distance of 0.01
            distance = np.where(distance < 0.01, 0.01, distance)
            # the adjacency matrix row
            Ai = np.asarray(A.getrowview(i).toarray())
            # displacement "force"
            Dist = k * k / distance ** 2
            if nohubs:
                Dist = Dist / float(Ai.sum(axis=1) + 1)
            if linlog:
                Dist = np.log(Dist + 1)
            displacement[:, i] += \
                (delta * (Dist - Ai * distance / k)).sum(axis=1)
            # update positions
        length = np.sqrt((displacement ** 2).sum(axis=0))
        length = np.where(length < 0.01, 0.01, length)
        pos += (displacement * t / length).T
        # cool temperature
        t -= dt
        # Return the layout
    return dict(zip(G, pos))

#def postgres_regex_match(db: DatabaseHandler, strings: List[str], regex: str) -> bool:
def layout_gexf(gexf: str) -> typing.Dict:
    """Accept a gexg graph, run force atlas on it, return the resulting laid out graph."""

    in_fh = io.StringIO(gexf)
    graph = nx.read_gexf(in_fh)

    print("START LAYOUT")
    layout = forceatlas2_layout(G=graph, iterations=500 )
    print("END LAYOUT")

    print(layout)
    #
    # out_fh = io.StringIO()
    # fa_gexf = networkx.write_gexf(fa_graph, io)

    scale = 10000

    int_layout = dict()
    for id in layout:
        pos = layout[id]
        int_layout[id] = (int(pos[0] * scale), int(pos[1] * scale))

    print(int_layout)

    return int_layout
