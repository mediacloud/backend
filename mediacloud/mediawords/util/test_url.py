from mediawords.util.url import *


def test_fix_common_url_mistakes():
    urls = {
        # "http://http://"
        'http://http://www.al-monitor.com/pulse': 'http://www.al-monitor.com/pulse',

        # With only one slash ("http:/www.")
        'http:/www.theinquirer.net/inquirer/news/2322928/net-neutrality-rules-lie-in-tatters-as-fcc-overruled':
            'http://www.theinquirer.net/inquirer/news/2322928/net-neutrality-rules-lie-in-tatters-as-fcc-overruled',

        # missing / before ?
        'http://foo.bar?baz=bat': 'http://foo.bar/?baz=bat',
    }

    for orig_url, fixed_url in urls.items():
        # Fix once
        assert fix_common_url_mistakes(orig_url) == fixed_url

        # Try fixing the same URL twice, see what happens
        assert fix_common_url_mistakes(fix_common_url_mistakes(orig_url)) == fixed_url


def test_is_http_url():
    assert not is_http_url(None)
    assert not is_http_url('')

    assert not is_http_url('abc')

    assert not is_http_url('gopher://gopher.floodgap.com/0/v2/vstat')
    assert not is_http_url('ftp://ftp.freebsd.org/pub/FreeBSD/')

    assert is_http_url('http://cyber.law.harvard.edu/about')
    assert is_http_url('https://github.com/berkmancenter/mediacloud')

    # URLs with mistakes fixable by fix_common_url_mistakes()
    assert not is_http_url(
        'http:/www.theinquirer.net/inquirer/news/2322928/net-neutrality-rules-lie-in-tatters-as-fcc-overruled'
    )
