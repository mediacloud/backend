import pytest

import mediawords.util.url as mc_url


# noinspection SpellCheckingInspection
def test_fix_common_url_mistakes():
    urls = {
        # "http://http://"
        'http://http://www.al-monitor.com/pulse': 'http://www.al-monitor.com/pulse',

        # With only one slash ("http:/www.")
        'http:/www.theinquirer.net/inquirer/news/2322928/net-neutrality-rules-lie-in-tatters-as-fcc-overruled':
            'http://www.theinquirer.net/inquirer/news/2322928/net-neutrality-rules-lie-in-tatters-as-fcc-overruled',

        # missing / before ?
        'http://foo.bar?baz=bat': 'http://foo.bar/?baz=bat',

        # Whitespace
        '  http://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html  ':
            'http://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html',

        # Missing port
        'https://www.gpo.gov:/fdsys/pkg/PLAW-107publ289/pdf/PLAW-107publ289.pdf':
            'https://www.gpo.gov/fdsys/pkg/PLAW-107publ289/pdf/PLAW-107publ289.pdf',

        # Non-URLencoded space
        'http://www.ldeo.columbia.edu/~peter/ site/Home.html': 'http://www.ldeo.columbia.edu/~peter/%20site/Home.html',
    }

    for orig_url, fixed_url in urls.items():
        # Fix once
        assert mc_url.urls_are_equal(url1=mc_url.fix_common_url_mistakes(orig_url), url2=fixed_url)

        # Try fixing the same URL twice, see what happens
        assert mc_url.urls_are_equal(
            url1=mc_url.fix_common_url_mistakes(mc_url.fix_common_url_mistakes(orig_url)),
            url2=fixed_url,
        )


# noinspection SpellCheckingInspection
def test_is_http_url():
    # noinspection PyTypeChecker
    assert not mc_url.is_http_url(None)
    assert not mc_url.is_http_url('')

    assert not mc_url.is_http_url('abc')
    assert not mc_url.is_http_url('/abc')
    assert not mc_url.is_http_url('//abc')
    assert not mc_url.is_http_url('///abc')

    assert not mc_url.is_http_url('gopher://gopher.floodgap.com/0/v2/vstat')
    assert not mc_url.is_http_url('ftp://ftp.freebsd.org/pub/FreeBSD/')

    assert mc_url.is_http_url('http://cyber.law.harvard.edu/about')
    assert mc_url.is_http_url('https://github.com/berkmancenter/mediacloud')

    funky_url = ('http://Las%20Vegas%20mass%20shooting%20raises'
                 '%20new%20doubts%20about%20safety%20of%20live%20entertainment')
    assert mc_url.is_http_url(funky_url) is False

    # URLs with port, HTTP auth, localhost
    assert mc_url.is_http_url('https://username:password@domain.com:12345/path?query=string#fragment')
    assert mc_url.is_http_url('http://localhost:9998/feed')
    assert mc_url.is_http_url('http://127.0.0.1:12345/456789')
    assert mc_url.is_http_url('http://127.0.00000000.1:8899/tweet_url?id=47')

    # Invalid IDNA
    assert not mc_url.is_http_url('http://michigan-state-football-sexual-assault-charges-arrest-players-names')
    assert not mc_url.is_http_url('http://michigan-state-football-sexual-assault-charges-arrest-players-names/')

    # Travis URL
    assert mc_url.is_http_url('http://testing-gce-286b4005-b1ae-4b1a-a0d8-faf85e39ca92:37873/gv/test.rss')

    # URLs with mistakes fixable by fix_common_url_mistakes()
    assert not mc_url.is_http_url(
        'http:/www.theinquirer.net/inquirer/news/2322928/net-neutrality-rules-lie-in-tatters-as-fcc-overruled'
    )

    # UTF-8 in paths
    assert mc_url.is_http_url('http://www.example.com/šiaurė.html')

    # IDN
    assert mc_url.is_http_url('http://www.šiaurė.lt/šiaurė.html')
    assert mc_url.is_http_url('http://www.xn--iaur-yva35b.lt/šiaurė.html')
    assert mc_url.is_http_url('http://.xn--iaur-yva35b.lt') is False  # Invalid Punycode
    assert mc_url.is_http_url('http://ebola-search-expands-ohio-nurse-amber-vinson-visit-cleveland-akron/') is False

    # Some weirdo
    assert mc_url.is_http_url('http://thomas.brown@') is False


def test_canonical_url():
    # Bad input
    with pytest.raises(mc_url.McCanonicalURLException):
        # noinspection PyTypeChecker
        mc_url.canonical_url(None)

    with pytest.raises(mc_url.McCanonicalURLException):
        # noinspection PyTypeChecker
        mc_url.canonical_url('')

    # Invalid URL
    with pytest.raises(mc_url.McCanonicalURLException):
        funky_url = ('http://Las%20Vegas%20mass%20shooting%20raises%20new%20'
                     'doubts%20about%20safety%20of%20live%20entertainment')
        mc_url.canonical_url(funky_url)

    # No urls_are_equal() because we want to compare them as strings here
    assert mc_url.canonical_url('HTTP://CYBER.LAW.HARVARD.EDU:80/node/9244') == 'http://cyber.law.harvard.edu/node/9244'


# noinspection SpellCheckingInspection
def test_normalize_url():
    # Bad URLs
    with pytest.raises(mc_url.McNormalizeURLException):
        # noinspection PyTypeChecker
        mc_url.normalize_url(None)
    with pytest.raises(mc_url.McNormalizeURLException):
        mc_url.normalize_url('gopher://gopher.floodgap.com/0/v2/vstat')

    # Basic
    # (No urls_are_equal() because we want to compare them as strings here)
    assert mc_url.normalize_url('HTTP://CYBER.LAW.HARVARD.EDU:80/node/9244') == 'http://cyber.law.harvard.edu/node/9244'
    assert mc_url.normalize_url(
        'HTTP://WWW.GOCRICKET.COM/news/sourav-ganguly/Sourav-Ganguly-exclusive-MS-Dhoni-must-reinvent-himself'
        '-to-survive/articleshow_sg/40421328.cms?utm_source=facebook.com&utm_medium=referral'
    ) == 'http://www.gocricket.com/news/sourav-ganguly/Sourav-Ganguly-exclusive-MS-Dhoni-must-reinvent-himself-to-' \
         'survive/articleshow_sg/40421328.cms'

    # Multiple fragments
    assert mc_url.normalize_url(
        'HTTP://CYBER.LAW.HARVARD.EDU/node/9244#foo#bar'
    ) == 'http://cyber.law.harvard.edu/node/9244'

    # URL in query
    assert mc_url.normalize_url('http://bash.org/?244321') == 'http://bash.org/?244321'

    # Broken URL
    assert mc_url.normalize_url('http://http://www.al-monitor.com/pulse') == 'http://www.al-monitor.com/pulse'

    # Empty parameter
    assert mc_url.normalize_url(
        'http://www-nc.nytimes.com/2011/06/29/us/politics/29marriage.html?=_r%3D6'
    ) == 'http://www-nc.nytimes.com/2011/06/29/us/politics/29marriage.html'

    # Remove whitespace
    assert mc_url.normalize_url(
        '  http://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html  '
    ) == 'http://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html'
    assert mc_url.normalize_url(
        "\t\thttp://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html\t\t"
    ) == 'http://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html'

    # NYTimes
    assert mc_url.normalize_url(
        'http://boss.blogs.nytimes.com/2014/08/19/why-i-do-all-of-my-recruiting-through-linkedin/'
        '?smid=fb-nytimes&WT.z_sma=BU_WID_20140819&bicmp=AD&bicmlukp=WT.mc_id&bicmst=1388552400000'
        '&bicmet=1420088400000&_'
    ) == 'http://boss.blogs.nytimes.com/2014/08/19/why-i-do-all-of-my-recruiting-through-linkedin/'
    assert mc_url.normalize_url(
        'http://www.nytimes.com/2014/08/19/upshot/inequality-and-web-search-trends.html?smid=fb-nytimes&'
        'WT.z_sma=UP_IOA_20140819&bicmp=AD&bicmlukp=WT.mc_id&bicmst=1388552400000&bicmet=1420088400000&_r=1&'
        'abt=0002&abg=1'
    ) == 'http://www.nytimes.com/2014/08/19/upshot/inequality-and-web-search-trends.html'
    assert mc_url.normalize_url(
        'http://www.nytimes.com/2014/08/20/upshot/data-on-transfer-of-military-gear-to-police-departments.html'
        '?smid=fb-nytimes&WT.z_sma=UP_DOT_20140819&bicmp=AD&bicmlukp=WT.mc_id&bicmst=1388552400000&'
        'bicmet=1420088400000&_r=1&abt=0002&abg=1'
    ) == 'http://www.nytimes.com/2014/08/20/upshot/data-on-transfer-of-military-gear-to-police-departments.html'

    # Facebook
    assert mc_url.normalize_url(
        'https://www.facebook.com/BerkmanCenter?ref=br_tf') == 'https://www.facebook.com/BerkmanCenter'

    # LiveJournal
    assert mc_url.normalize_url(
        'http://zyalt.livejournal.com/1178735.html?thread=396696687#t396696687'
    ) == 'http://zyalt.livejournal.com/1178735.html'

    # "nk" parameter
    assert mc_url.normalize_url(
        'http://www.adelaidenow.com.au/news/south-australia/sa-court-told-prominent-adelaide-businessman-yasser'
        '-shahin-was-assaulted-by-police-officer-norman-hoy-in-september-2010-traffic-stop/story-fni6uo1m-'
        '1227184460050?nk=440cd48fd95a4e1f1c23bcd15df36da7'
    ) == ('http://www.adelaidenow.com.au/news/south-australia/sa-court-told-prominent-adelaide-businessman-yasser-'
          'shahin-was-assaulted-by-police-officer-norman-hoy-in-september-2010-traffic-stop/story-fni6uo1m-'
          '1227184460050')


# noinspection SpellCheckingInspection
def test_normalize_url_lossy():
    # FIXME - some resulting URLs look funny, not sure if I can change them easily though
    # (No urls_are_equal() because we want to compare them as strings here)
    assert mc_url.normalize_url_lossy(
        'HTTP://WWW.nytimes.COM/ARTICLE/12345/?ab=cd#def#ghi/'
    ) == 'http://nytimes.com/article/12345/?ab=cd'
    assert mc_url.normalize_url_lossy(
        'http://HTTP://WWW.nytimes.COM/ARTICLE/12345/?ab=cd#def#ghi/'
    ) == 'http://nytimes.com/article/12345/?ab=cd'
    assert mc_url.normalize_url_lossy('http://http://www.al-monitor.com/pulse') == 'http://al-monitor.com/pulse'
    assert mc_url.normalize_url_lossy('http://m.delfi.lt/foo') == 'http://delfi.lt/foo'
    assert mc_url.normalize_url_lossy(
        'http://blog.yesmeck.com/jquery-jsonview/') == 'http://yesmeck.com/jquery-jsonview/'
    assert mc_url.normalize_url_lossy('http://cdn.com.do/noticias/nacionales') == 'http://com.do/noticias/nacionales'
    assert mc_url.normalize_url_lossy('http://543.r2.ly') == 'http://543.r2.ly/'

    tests = [
        ['http://nytimes.com', 'http://nytimes.com/'],
        ['http://http://nytimes.com', 'http://nytimes.com/'],
        ['HTTP://nytimes.COM', 'http://nytimes.com/'],
        ['http://beta.foo.com/bar', 'http://foo.com/bar'],
        ['http://archive.org/bar', 'http://archive.org/bar'],
        ['http://m.archive.org/bar', 'http://archive.org/bar'],
        ['http://archive.foo.com/bar', 'http://foo.com/bar'],
        ['http://foo.com/bar#baz', 'http://foo.com/bar'],
        ['http://foo.com/bar/baz//foo', 'http://foo.com/bar/baz/foo'],
        ['https://archive.is/o/vWkgm/www.huffingtonpost.com/lisa-bloom/why-the-new-child-rape-ca_b_10619944.html',
         'http://huffingtonpost.com/lisa-bloom/why-the-new-child-rape-ca_b_10619944.html'],
        ['https://archive.is/o/m1k2A/https://en.wikipedia.org/wiki/Gamergate_controversy%23cite_note-right_wing-130',
         'http://en.wikipedia.org/wiki/gamergate_controversy#cite_note-right_wing-130']
    ]

    for test in tests:
        input_url, expected_output_url = test
        assert mc_url.normalize_url_lossy(input_url) == expected_output_url


def test_is_shortened_url() -> None:
    """Test is_shortened_url."""
    assert not mc_url.is_shortened_url('http://google.com/')
    assert not mc_url.is_shortened_url('http://nytimes.com/2014/03/01/foo.html')
    assert mc_url.is_shortened_url('http://bit.ly/2eYIj4g')
    assert mc_url.is_shortened_url('https://t.co/mtaVvZ8mYF')
    assert mc_url.is_shortened_url('http://dlvr.it/NN7ZQS')
    assert mc_url.is_shortened_url('http://fb.me/8SXPGB68Z')
    assert mc_url.is_shortened_url('http://hill.cm/Dg9qAUD')
    assert mc_url.is_shortened_url('http://ift.tt/2fQKXoA')
    assert mc_url.is_shortened_url('https://goo.gl/fb/abZexj')
    assert mc_url.is_shortened_url('https://youtu.be/GFeRyRA7FPE')
    assert mc_url.is_shortened_url('http://wapo.st/2iBGdb9')
    assert mc_url.is_shortened_url('http://ln.is/DN0QN')
    assert mc_url.is_shortened_url(
        'http://feeds.feedburner.com/~ff/businessinsider?a=AAU_77_kuWM:T_8wA0qh0C4:gIN9vFwOqvQ'
    )
    assert mc_url.is_shortened_url('https://archive.is/o/m1k2A/https://foo.com')


# noinspection SpellCheckingInspection
def test_is_homepage_url():
    # Bad input
    # noinspection PyTypeChecker
    assert not mc_url.is_homepage_url(None)
    assert not mc_url.is_homepage_url('')

    # No scheme
    assert not mc_url.is_homepage_url('abc')

    # True positives
    assert mc_url.is_homepage_url('http://www.wired.com')
    assert mc_url.is_homepage_url('http://www.wired.com/')
    assert mc_url.is_homepage_url('http://m.wired.com/#abc')

    # False negatives
    assert not mc_url.is_homepage_url('http://m.wired.com/threatlevel/2011/12/sopa-watered-down-amendment/')

    # DELFI article (article identifier as query parameter)
    assert not mc_url.is_homepage_url(
        'http://www.delfi.lt/news/daily/world/prancuzijoje-tukstanciai-pareigunu-sukuoja-apylinkes-blokuojami-'
        'keliai.d?id=66850094'
    )

    # Bash.org quote (empty path, article identifier as query parameter)
    assert not mc_url.is_homepage_url('http://bash.org/?244321')

    # YouTube shortened URL (path consists of letters with varying cases)
    assert not mc_url.is_homepage_url('http://youtu.be/oKyFAMiZMbU')

    # Bit.ly shortened URL (path has a number)
    assert not mc_url.is_homepage_url('https://bit.ly/1uSjCJp')

    # Bit.ly shortened URL (path does not have a number, but the host is in the URL shorteners list)
    assert not mc_url.is_homepage_url('https://bit.ly/defghi')

    # Link to JPG
    assert not mc_url.is_homepage_url('https://i.imgur.com/gbu5YNM.jpg')

    # Technically, server is not required to normalize "///" path into "/", but most of them do anyway
    assert mc_url.is_homepage_url('http://www.wired.com///')
    assert mc_url.is_homepage_url('http://m.wired.com///')

    # Smarter homepage identification ("/en/", "/news/", ...)
    assert mc_url.is_homepage_url('http://www.latimes.com/entertainment/')
    assert mc_url.is_homepage_url('http://www.scidev.net/global/')
    assert mc_url.is_homepage_url('http://abcnews.go.com/US')
    assert mc_url.is_homepage_url('http://www.example.com/news/')
    assert mc_url.is_homepage_url('http://www.france24.com/en/')
    assert mc_url.is_homepage_url('http://www.france24.com/en/?altcast_code=0adb03a8a4')
    assert mc_url.is_homepage_url('http://www.google.com/trends/explore')
    assert mc_url.is_homepage_url('http://www.google.com/trends/explore#q=Ebola')
    assert mc_url.is_homepage_url('http://www.nytimes.com/pages/todayspaper/')
    assert mc_url.is_homepage_url('http://www.politico.com/playbook/')


# noinspection SpellCheckingInspection
def test_get_url_host():
    with pytest.raises(mc_url.McGetURLHostException):
        # noinspection PyTypeChecker
        mc_url.get_url_host(None)
    assert mc_url.get_url_host('http://www.nytimes.com/') == 'www.nytimes.com'
    assert mc_url.get_url_host('http://obama:barack1@WHITEHOUSE.GOV/michelle.html') == 'whitehouse.gov'


# noinspection SpellCheckingInspection
def test_get_url_distinctive_domain():
    # FIXME - some resulting domains look funny, not sure if I can change them easily though
    assert mc_url.get_url_distinctive_domain('http://www.nytimes.com/') == 'nytimes.com'
    assert mc_url.get_url_distinctive_domain('http://cyber.law.harvard.edu/') == 'law.harvard.edu'
    assert mc_url.get_url_distinctive_domain('http://www.gazeta.ru/') == 'gazeta.ru'
    assert mc_url.get_url_distinctive_domain('http://www.whitehouse.gov/'), 'www.whitehouse.gov'
    assert mc_url.get_url_distinctive_domain('http://info.info/') == 'info.info'
    assert mc_url.get_url_distinctive_domain('http://blog.yesmeck.com/jquery-jsonview/') == 'yesmeck.com'
    assert mc_url.get_url_distinctive_domain('http://status.livejournal.org/') == 'livejournal.org'

    # ".(gov|org|com).XX" exception
    assert mc_url.get_url_distinctive_domain('http://www.stat.gov.lt/') == 'stat.gov.lt'

    # "wordpress.com|blogspot|..." exception
    assert mc_url.get_url_distinctive_domain('https://en.blog.wordpress.com/') == 'en.blog.wordpress.com'


# noinspection SpellCheckingInspection
def test_http_urls_in_string():
    # Basic test
    assert set(mc_url.http_urls_in_string("""
        These are my favourite websites:
        * http://www.mediacloud.org/
        * http://cyber.law.harvard.edu/
        * about:blank
    """)) == {'http://www.mediacloud.org/', 'http://cyber.law.harvard.edu/'}

    # Duplicate URLs
    assert set(mc_url.http_urls_in_string("""
        These are my favourite (duplicate) websites:
        * http://www.mediacloud.org/
        * http://www.mediacloud.org/
        * http://cyber.law.harvard.edu/
        * http://cyber.law.harvard.edu/
        * http://www.mediacloud.org/
        * http://www.mediacloud.org/
    """)) == {'http://www.mediacloud.org/', 'http://cyber.law.harvard.edu/'}

    # No http:// URLs
    assert set(mc_url.http_urls_in_string("""
        This test text doesn't have any http:// URLs, only a ftp:// one:
        ftp://ftp.ubuntu.com/ubuntu/
    """)) == set()

    # Erroneous input
    with pytest.raises(mc_url.McHTTPURLsInStringException):
        # noinspection PyTypeChecker
        mc_url.http_urls_in_string(None)


def test_get_url_path_fast():
    assert mc_url.get_url_path_fast('http://www.example.com/a/b/c') == '/a/b/c'
    assert mc_url.get_url_path_fast('not_an_url') == ''
    assert mc_url.get_url_path_fast('http://ebola-search-expands-ohio-nurse-amber-vinson-visit-cleveland-akron/') == ''


def test_get_base_url():
    with pytest.raises(mc_url.McGetBaseURLException):
        # noinspection PyTypeChecker
        mc_url.get_base_url(None)

    with pytest.raises(mc_url.McGetBaseURLException):
        mc_url.get_base_url('')

    with pytest.raises(mc_url.McGetBaseURLException):
        mc_url.get_base_url('not_an_url')

    assert mc_url.get_base_url('http://example.com/') == 'http://example.com/'
    assert mc_url.get_base_url('http://example.com/base/') == 'http://example.com/base/'
    assert mc_url.get_base_url('http://example.com/base/index.html') == 'http://example.com/base/'


def test_urls_are_equal():
    # Invalid input
    with pytest.raises(mc_url.McURLsAreEqualException):
        # noinspection PyTypeChecker
        mc_url.urls_are_equal(url1=None, url2=None)
    with pytest.raises(mc_url.McURLsAreEqualException):
        # noinspection PyTypeChecker
        mc_url.urls_are_equal(url1=None, url2='https://web.mit.edu/')
    with pytest.raises(mc_url.McURLsAreEqualException):
        # noinspection PyTypeChecker
        mc_url.urls_are_equal(url1='https://web.mit.edu/', url2=None)

    # Not URLs
    assert mc_url.urls_are_equal(url1='Not an URL.', url2='Not an URL.') is False

    funky_url = ('http://Las%20Vegas%20mass%20shooting%20raises%20new%20'
                 'doubts%20about%20safety%20of%20live%20entertainment')
    assert mc_url.urls_are_equal(url1=funky_url, url2=funky_url) is False

    assert mc_url.urls_are_equal(url1='https://web.mit.edu/', url2='https://web.mit.edu/') is True
    assert mc_url.urls_are_equal(url1='https://web.mit.edu/', url2='https://WEB.MIT.EDU/') is True
    assert mc_url.urls_are_equal(url1='https://web.mit.edu/', url2='https://WEB.MIT.EDU//') is True
    assert mc_url.urls_are_equal(url1='https://web.mit.edu/', url2='https://WEB.MIT.EDU:443') is True
    assert mc_url.urls_are_equal(url1='https://web.mit.edu/', url2='https://WEB.MIT.EDU:443/') is True
    assert mc_url.urls_are_equal(url1='https://web.mit.edu/', url2='https://WEB.MIT.EDU:443//') is True
    assert mc_url.urls_are_equal(url1='http://web.mit.edu/', url2='http://WEB.MIT.EDU:80//') is True

    assert mc_url.urls_are_equal(url1='https://web.mit.edu/', url2='https://WEB.MIT.EDU:443//page') is False
