from topics_base.fetch_link_utils import content_matches_topic


def test_content_matches_topic():
    """Test content_matches_topic()."""
    assert content_matches_topic('foo', {'topics_id': 1, 'pattern': 'foo'})
    assert content_matches_topic('FOO', {'topics_id': 1, 'pattern': 'foo'})
    assert content_matches_topic('FOO', {'topics_id': 1, 'pattern': ' foo '})
    assert not content_matches_topic('foo', {'topics_id': 1, 'pattern': 'bar'})
    assert content_matches_topic('foo', {'topics_id': 1, 'pattern': 'bar'}, assume_match=True)
