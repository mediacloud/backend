from nose.tools import assert_raises

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


def test_is_shortened_url():
    assert not is_shortened_url(None)
    assert not is_shortened_url('http://bit.ly')
    assert not is_shortened_url('http://bit.ly/')

    assert is_shortened_url('http://bit.ly/abc')


def test_normalize_url():
    # Bad URLs
    assert_raises(NormalizeURLException, normalize_url, None)
    assert_raises(NormalizeURLException, normalize_url, 'gopher://gopher.floodgap.com/0/v2/vstat')

    # Basic
    assert normalize_url('HTTP://CYBER.LAW.HARVARD.EDU:80/node/9244') == 'http://cyber.law.harvard.edu/node/9244'
    assert normalize_url(
        'HTTP://WWW.GOCRICKET.COM/news/sourav-ganguly/Sourav-Ganguly-exclusive-MS-Dhoni-must-reinvent-himself'
        + '-to-survive/articleshow_sg/40421328.cms?utm_source=facebook.com&utm_medium=referral'
    ) == 'http://www.gocricket.com/news/sourav-ganguly/Sourav-Ganguly-exclusive-MS-Dhoni-must-reinvent-himself-to-' \
         + 'survive/articleshow_sg/40421328.cms'

    # Multiple fragments
    assert normalize_url('HTTP://CYBER.LAW.HARVARD.EDU/node/9244#foo#bar') == 'http://cyber.law.harvard.edu/node/9244'

    # URL in query
    assert normalize_url('http://bash.org/?244321') == 'http://bash.org/?244321'

    # Broken URL
    assert normalize_url('http://http://www.al-monitor.com/pulse') == 'http://www.al-monitor.com/pulse'

    # Empty parameter
    assert normalize_url(
        'http://www-nc.nytimes.com/2011/06/29/us/politics/29marriage.html?=_r%3D6'
    ) == 'http://www-nc.nytimes.com/2011/06/29/us/politics/29marriage.html'

    # Remove whitespace
    assert normalize_url(
        '  http://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html  '
    ) == 'http://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html'
    assert normalize_url(
        "\t\thttp://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html\t\t"
    ) == 'http://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html'

    # NYTimes
    assert normalize_url(
        'http://boss.blogs.nytimes.com/2014/08/19/why-i-do-all-of-my-recruiting-through-linkedin/'
        + '?smid=fb-nytimes&WT.z_sma=BU_WID_20140819&bicmp=AD&bicmlukp=WT.mc_id&bicmst=1388552400000'
        + '&bicmet=1420088400000&_'
    ) == 'http://boss.blogs.nytimes.com/2014/08/19/why-i-do-all-of-my-recruiting-through-linkedin/'
    assert normalize_url(
        'http://www.nytimes.com/2014/08/19/upshot/inequality-and-web-search-trends.html?smid=fb-nytimes&'
        + 'WT.z_sma=UP_IOA_20140819&bicmp=AD&bicmlukp=WT.mc_id&bicmst=1388552400000&bicmet=1420088400000&_r=1&'
        + 'abt=0002&abg=1'
    ) == 'http://www.nytimes.com/2014/08/19/upshot/inequality-and-web-search-trends.html'
    assert normalize_url(
        'http://www.nytimes.com/2014/08/20/upshot/data-on-transfer-of-military-gear-to-police-departments.html'
        + '?smid=fb-nytimes&WT.z_sma=UP_DOT_20140819&bicmp=AD&bicmlukp=WT.mc_id&bicmst=1388552400000&'
        + 'bicmet=1420088400000&_r=1&abt=0002&abg=1'
    ) == 'http://www.nytimes.com/2014/08/20/upshot/data-on-transfer-of-military-gear-to-police-departments.html'

    # Facebook
    assert normalize_url('https://www.facebook.com/BerkmanCenter?ref=br_tf') == 'https://www.facebook.com/BerkmanCenter'

    # LiveJournal
    assert normalize_url(
        'http://zyalt.livejournal.com/1178735.html?thread=396696687#t396696687'
    ) == 'http://zyalt.livejournal.com/1178735.html'

    # "nk" parameter
    assert normalize_url(
        'http://www.adelaidenow.com.au/news/south-australia/sa-court-told-prominent-adelaide-businessman-yasser'
        + '-shahin-was-assaulted-by-police-officer-norman-hoy-in-september-2010-traffic-stop/story-fni6uo1m-'
        + '1227184460050?nk=440cd48fd95a4e1f1c23bcd15df36da7'
    ) == 'http://www.adelaidenow.com.au/news/south-australia/sa-court-told-prominent-adelaide-businessman-yasser-' + \
         'shahin-was-assaulted-by-police-officer-norman-hoy-in-september-2010-traffic-stop/story-fni6uo1m-' + \
         '1227184460050'
