# noinspection PyProtectedMember
from crawler_fetcher.handlers.feed_podcast import (
    _get_feed_url_from_itunes_podcasts_url,
    _get_feed_url_from_google_podcasts_url,
)


def test_get_feed_url_from_itunes_podcasts_url():
    # noinspection PyTypeChecker
    assert _get_feed_url_from_itunes_podcasts_url(None) is None
    assert _get_feed_url_from_itunes_podcasts_url('') == ''
    assert _get_feed_url_from_itunes_podcasts_url('http://www.example.com/') == 'http://www.example.com/'
    assert _get_feed_url_from_itunes_podcasts_url('totally not an URL') == 'totally not an URL'

    # Let's just kind of hope RA doesn't change their underlying feed URL
    ra_feed_url = 'https://ra.co/xml/podcast.xml'

    ra_itunes_url = 'https://podcasts.apple.com/lt/podcast/ra-podcast/id129673441'
    assert _get_feed_url_from_itunes_podcasts_url(ra_itunes_url) == ra_feed_url

    # Try uppercase host
    ra_itunes_url = 'https://PODCASTS.APPLE.COM/lt/podcast/ra-podcast/id129673441'
    assert _get_feed_url_from_itunes_podcasts_url(ra_itunes_url) == ra_feed_url

    # Try old style URL
    ra_itunes_url = 'https://itunes.apple.com/lt/podcast/ra-podcast/id129673441'
    assert _get_feed_url_from_itunes_podcasts_url(ra_itunes_url) == ra_feed_url


def test_get_feed_url_from_google_podcasts_url():
    # noinspection PyTypeChecker
    assert _get_feed_url_from_google_podcasts_url(None) is None
    assert _get_feed_url_from_google_podcasts_url('') == ''
    assert _get_feed_url_from_google_podcasts_url('http://www.example.com/') == 'http://www.example.com/'
    assert _get_feed_url_from_google_podcasts_url('totally not an URL') == 'totally not an URL'

    ft_feed_url = 'https://rss.acast.com/ftnewsbriefing'

    # Test with URL pointing to a show's homepage (not invidual episode)

    ft_google_show_url = (
        'https://podcasts.google.com/feed/aHR0cHM6Ly9yc3MuYWNhc3QuY29tL2Z0bmV3c2JyaWVmaW5n?sa=X'
        '&ved=0CH4Qjs4CKARqFwoTCIjZ5ZTNwvECFQAAAAAdAAAAABAL'
    )

    assert _get_feed_url_from_google_podcasts_url(ft_google_show_url) == ft_feed_url

    # Test with URL that points to a specific episode
    ft_google_ep_url = (
        'https://podcasts.google.com/feed/aHR0cHM6Ly9yc3MuYWNhc3QuY29tL2Z0bmV3c2JyaWVmaW5n/episode/'
        'NzM4Y2Q2NWEtMWM5Ni00Y2FjLWI5NDYtN2ExNGVmYThhOWRm?sa=X&ved=0CAUQkfYCahcKEwiI2eWUzcLxAhUAAAAAHQAAAAAQDg'
    )

    assert _get_feed_url_from_google_podcasts_url(ft_google_ep_url) == ft_feed_url
