"""Test graph_layout functions."""

from webapp.tm.snapshot.gexf import py_giant_component


def test_giant_component() -> None:
    """Test giant_component()."""
    edges = [[1, 2], [2, 3], [3, 4], [3, 1], [5, 4], [3, 6], [7, 8], [8, 9]]

    assert set(py_giant_component(edges)) == set(((1, 2), (2, 3), (3, 4), (3, 1), (3, 6), (5, 4)))
