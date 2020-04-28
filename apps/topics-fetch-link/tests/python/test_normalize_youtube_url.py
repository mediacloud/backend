#/usr/bin/env python3

from mediawords.util.url import normalize_youtube_url, normalize_url_lossy

def test_youtube_urls():
    nyu = normalize_youtube_url 

    assert nyu('http://foo.bar') == 'http://foo.bar'
    assert nyu('http://youtube.com/foo/bar') == 'https://www.youtube.com/foo/bar'
    assert nyu('https://youtube.com/foo/bar') == 'https://www.youtube.com/foo/bar'
    assert nyu('https://www.youtube.com/watch?v=123456') == 'https://www.youtube.com/watch?v=123456'
    assert nyu('https://www.youtube.com/watch?v=123456&foo=bar&share=bat') == 'https://www.youtube.com/watch?v=123456'
    assert nyu('https://www.youtube.com/channel/123456') == 'https://www.youtube.com/channel/123456'
    assert nyu('https://www.youtube.com/channel/123456?foo=bar') == 'https://www.youtube.com/channel/123456'
    assert nyu('https://www.youtube.com/user/123456') == 'https://www.youtube.com/user/123456'
    assert nyu('https://www.youtube.com/user/123456?foo=bar') == 'https://www.youtube.com/user/123456'
    assert nyu('https://www.youtube.com/embed/123456?foo=bar&share=bat') == 'https://www.youtube.com/watch?v=123456'

    assert normalize_url_lossy('https://www.youtube.com/embed/123456?f=b') == 'http://youtube.com/watch?v=123456'
