# noinspection PyProtectedMember
from podcast_transcribe_episode.bcp47_lang import _country_tld_from_url, iso_639_1_code_to_bcp_47_identifier


def test_country_tld_from_url():
    assert _country_tld_from_url("https://www.bbc.co.uk/news/politics/eu-regions/vote2014_sitemap.xml") == "uk"


def test_iso_639_1_code_to_bcp_47_identifier():
    assert iso_639_1_code_to_bcp_47_identifier('') is None
    # noinspection PyTypeChecker
    assert iso_639_1_code_to_bcp_47_identifier(None) is None
    assert iso_639_1_code_to_bcp_47_identifier('lt') == 'lt-LT'
    assert iso_639_1_code_to_bcp_47_identifier('en') == 'en-US'
    assert iso_639_1_code_to_bcp_47_identifier('en', url_hint='https://WWW.BBC.CO.UK:443/test.html') == 'en-GB'
