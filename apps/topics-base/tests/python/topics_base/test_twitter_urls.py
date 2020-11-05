from topics_base.twitter_url import (
    parse_status_id_from_url,
    parse_screen_name_from_user_url,
    get_tweet_urls,
)


def test_parse_status_id_from_url() -> None:
    """Test parse_status_id_from_url()."""
    assert parse_status_id_from_url('https://twitter.com/jwood/status/557722370597978115') == '557722370597978115'
    assert parse_status_id_from_url('http://twitter.com/srhbus/status/586418382515208192') == '586418382515208192'
    assert parse_status_id_from_url('http://twitter.com/srhbus/status/12345?foo=bar') == '12345'
    assert parse_status_id_from_url('http://mobile.twitter.com/srhbus/status/12345?foo=bar') == '12345'
    assert parse_status_id_from_url('http://google.com') is None
    assert parse_status_id_from_url('http://twitter.com/jeneps') is None


def test_parse_screen_name_from_user_url() -> None:
    """Test parse_screen_name_from_user_url()."""
    assert parse_screen_name_from_user_url('https://twitter.com/jwoodham/status/557722370597978115') is None
    assert parse_screen_name_from_user_url('http://twitter.com/BookTaster') == 'BookTaster'
    assert parse_screen_name_from_user_url('https://twitter.com/tarantallegra') == 'tarantallegra'
    assert parse_screen_name_from_user_url('https://mobile.twitter.com/tarantallegra') == 'tarantallegra'
    assert parse_screen_name_from_user_url('https://twitter.com/tarantallegra?foo=bar') == 'tarantallegra'
    assert parse_screen_name_from_user_url('https://twitter.com/search?q=foo') is None
    assert parse_screen_name_from_user_url('https://twitter.com/login?q=foo') is None
    assert parse_screen_name_from_user_url('http://google.com') is None


def test_get_tweet_urls() -> None:
    """Test get_tweet_urls()."""
    tweet = {'entities': {'urls': [{'expanded_url': 'foo'}, {'expanded_url': 'bar'}]}}
    urls = get_tweet_urls(tweet)
    assert sorted(urls) == ['bar', 'foo']

    tweet = \
        {
            'entities':
                {
                    'urls': [{'expanded_url': 'url foo'}, {'expanded_url': 'url bar'}],
                },
            'retweeted_status':
                {
                    'entities':
                        {
                            'urls': [{'expanded_url': 'rt url foo'}, {'expanded_url': 'rt url bar'}],
                        }
                }
        }
    urls = get_tweet_urls(tweet)
    expected_urls = ['url bar', 'url foo', 'rt url foo', 'rt url bar']
    assert sorted(urls) == sorted(expected_urls)
