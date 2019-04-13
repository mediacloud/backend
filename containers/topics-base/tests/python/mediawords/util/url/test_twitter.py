from mediawords.util.url.twitter import parse_status_id_from_url, parse_screen_name_from_user_url


def test_parse_status_id_from_url() -> None:
    """Test parse_status_id_from_url()."""
    assert parse_status_id_from_url('https://twitter.com/jwood/status/557722370597978115') == '557722370597978115'
    assert parse_status_id_from_url('http://twitter.com/srhbus/status/586418382515208192') == '586418382515208192'
    assert parse_status_id_from_url('http://twitter.com/srhbus/status/12345?foo=bar') == '12345'
    assert parse_status_id_from_url('http://google.com') is None
    assert parse_status_id_from_url('http://twitter.com/jeneps') is None


def test_parse_screen_name_from_user_url() -> None:
    """Test parse_screen_name_from_user_url()."""
    assert parse_screen_name_from_user_url('https://twitter.com/jwoodham/status/557722370597978115') is None
    assert parse_screen_name_from_user_url('http://twitter.com/BookTaster') == 'BookTaster'
    assert parse_screen_name_from_user_url('https://twitter.com/tarantallegra') == 'tarantallegra'
    assert parse_screen_name_from_user_url('https://twitter.com/tarantallegra?foo=bar') == 'tarantallegra'
    assert parse_screen_name_from_user_url('https://twitter.com/search?q=foo') is None
    assert parse_screen_name_from_user_url('https://twitter.com/login?q=foo') is None
    assert parse_screen_name_from_user_url('http://google.com') is None
