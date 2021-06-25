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

    npr_feed_url = 'https://npr.pyther.net/podcast/2'

    # Test with URL pointing to a show's homepage (not invidual episode)

    npr_google_show_url = (
        'https://podcasts.google.com/feed/aHR0cHM6Ly9ucHIucHl0aGVyLm5ldC9wb2RjYXN0LzI?'
        'sa=X&ved=2ahUKEwjKm6fimbjuAhWMjoQIHUrSCW0Qjs4CKAl6BAgBEH4'
    )

    assert _get_feed_url_from_google_podcasts_url(npr_google_show_url) == npr_feed_url

    # Test with URL that points to a specific episode
    npr_google_ep_url = (
        'https://podcasts.google.com/feed/aHR0cHM6Ly9ucHIucHl0aGVyLm5ldC9wb2RjYXN0LzI/episode/'
        'MTAwOTk5MjU4MToxMDA5OTkyNTg5?sa=X&ved=0CAUQkfYCahcKEwiA9OOL4rLxAhUAAAAAHQAAAAAQAQ'
    )

    assert _get_feed_url_from_google_podcasts_url(npr_google_ep_url) == npr_feed_url
