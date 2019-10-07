# noinspection PyProtectedMember
from topics_fetch_twitter_urls.fetch_twitter_urls import _split_urls_into_users_and_statuses


def test_split_urls_into_users_and_statuses() -> None:
    """Test split_urls_into_users_and_statuses()."""
    user_urls = [{'url': u} for u in ['http://twitter.com/foo', 'http://twitter.com/bar']]
    status_urls = [{'url': u} for u in ['https://twitter.com/foo/status/123', 'https://twitter.com/bar/status/456']]
    assert _split_urls_into_users_and_statuses(user_urls + status_urls) == (user_urls, status_urls)
