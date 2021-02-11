# noinspection PyProtectedMember
from crawler_ap.ap import _extract_url_parameters


def test_extract_url_parameters() -> None:
    """Test parameter extraction from url"""
    url = 'https://www.google.com/page?a=5&b=abc'
    assert _extract_url_parameters(url) == {'a': '5', 'b': 'abc'}
