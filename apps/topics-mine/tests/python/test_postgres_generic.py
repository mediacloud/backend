"""Test postgres_generic.py"""

from topics_mine.posts.postgres_generic import PostgresPostFetcher

def test_fetch_posts() -> None:
    """Test fetch_posts."""
    PostgresPostFetcher().test_mock_data()
