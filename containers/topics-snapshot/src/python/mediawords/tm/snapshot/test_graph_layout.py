"""Test graph_layout functions."""

from mediawords.tm.snapshot.graph_layout import giant_component


def test_giant_component() -> None:
    """Test giant_component()."""
    edges = [[1, 2], [2, 3], [3, 4], [3, 1], [5, 4], [3, 6], [7, 8], [8, 9]]

    assert set(giant_component(edges)) == set(((1, 2), (2, 3), (3, 4), (3, 1), (3, 6), (5, 4)))
