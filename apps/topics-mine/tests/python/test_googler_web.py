"""Test googler_web.py"""

from topics_mine.posts.googler_web import GooglerWebPostFetcher

def test_fetch_posts() -> None:
    """Test fetch_posts."""
    GooglerWebPostFetcher().test_mock_data()
