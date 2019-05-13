from topics_base.fetch_link_utils import content_matches_topic


def test_content_matches_topic():
    """Test content_matches_topic()."""
    assert content_matches_topic('foo', {'pattern': 'foo'})
    assert content_matches_topic('FOO', {'pattern': 'foo'})
    assert content_matches_topic('FOO', {'pattern': ' foo '})
    assert not content_matches_topic('foo', {'pattern': 'bar'})
    assert content_matches_topic('foo', {'pattern': 'bar'}, assume_match=True)
