# noinspection PyProtectedMember
from topics_base.stories import _url_domain_matches_medium


def test_url_domain_matches_medium():
    """Test story_domain_matches_medium()."""
    medium = dict()

    medium['url'] = 'http://foo.com'
    urls = ['http://foo.com/bar/baz']
    assert _url_domain_matches_medium(medium, urls)

    medium['url'] = 'http://foo.com'
    urls = ['http://bar.com', 'http://foo.com/bar/baz']
    assert _url_domain_matches_medium(medium, urls)

    medium['url'] = 'http://bar.com'
    urls = ['http://foo.com/bar/baz']
    assert not _url_domain_matches_medium(medium, urls)
