"""Test csv_generic.py"""

from topics_mine.posts.csv_generic import CSVStaticPostFetcher

def test_fetch_posts() -> None:
    """Test fetch_posts."""
    CSVStaticPostFetcher().test_mock_data()
