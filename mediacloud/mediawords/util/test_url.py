from nose.tools import assert_raises

from mediawords.util.url import *


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
    }

    for orig_url, fixed_url in urls.items():
        # Fix once
        assert fix_common_url_mistakes(orig_url) == fixed_url

        # Try fixing the same URL twice, see what happens
        assert fix_common_url_mistakes(fix_common_url_mistakes(orig_url)) == fixed_url


# noinspection SpellCheckingInspection
def test_is_http_url():
    # noinspection PyTypeChecker
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


# noinspection SpellCheckingInspection
def test_normalize_url():
    # Bad URLs
    assert_raises(McNormalizeURLException, normalize_url, None)
    assert_raises(McNormalizeURLException, normalize_url, 'gopher://gopher.floodgap.com/0/v2/vstat')

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


# noinspection SpellCheckingInspection
def test_normalize_url_lossy():
    # FIXME - some resulting URLs look funny, not sure if I can change them easily though
    assert normalize_url_lossy(
        'HTTP://WWW.nytimes.COM/ARTICLE/12345/?ab=cd#def#ghi/'
    ) == 'http://nytimes.com/article/12345/?ab=cd'
    assert normalize_url_lossy(
        'http://HTTP://WWW.nytimes.COM/ARTICLE/12345/?ab=cd#def#ghi/'
    ) == 'http://nytimes.com/article/12345/?ab=cd'
    assert normalize_url_lossy('http://http://www.al-monitor.com/pulse') == 'http://al-monitor.com/pulse'
    assert normalize_url_lossy('http://m.delfi.lt/foo') == 'http://delfi.lt/foo'
    assert normalize_url_lossy('http://blog.yesmeck.com/jquery-jsonview/') == 'http://yesmeck.com/jquery-jsonview/'
    assert normalize_url_lossy('http://cdn.com.do/noticias/nacionales') == 'http://com.do/noticias/nacionales'
    assert normalize_url_lossy('http://543.r2.ly') == 'http://543.r2.ly/'

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
    ]

    for test in tests:
        input_url, expected_output_url = test
        assert normalize_url_lossy(input_url) == expected_output_url


# noinspection SpellCheckingInspection
def test_is_homepage_url():
    # Bad input
    # noinspection PyTypeChecker
    assert not is_homepage_url(None)
    assert not is_homepage_url('')

    # No scheme
    assert not is_homepage_url('abc')

    # True positives
    assert is_homepage_url('http://www.wired.com')
    assert is_homepage_url('http://www.wired.com/')
    assert is_homepage_url('http://m.wired.com/#abc')

    # False negatives
    assert not is_homepage_url('http://m.wired.com/threatlevel/2011/12/sopa-watered-down-amendment/')

    # DELFI article (article identifier as query parameter)
    assert not is_homepage_url(
        'http://www.delfi.lt/news/daily/world/prancuzijoje-tukstanciai-pareigunu-sukuoja-apylinkes-blokuojami-'
        + 'keliai.d?id=66850094'
    )

    # Bash.org quote (empty path, article identifier as query parameter)
    assert not is_homepage_url('http://bash.org/?244321')

    # YouTube shortened URL (path consists of letters with varying cases)
    assert not is_homepage_url('http://youtu.be/oKyFAMiZMbU')

    # Bit.ly shortened URL (path has a number)
    assert not is_homepage_url('https://bit.ly/1uSjCJp')

    # Bit.ly shortened URL (path does not have a number, but the host is in the URL shorteners list)
    assert not is_homepage_url('https://bit.ly/defghi')

    # Link to JPG
    assert not is_homepage_url('https://i.imgur.com/gbu5YNM.jpg')

    # Technically, server is not required to normalize "///" path into "/", but most of them do anyway
    assert is_homepage_url('http://www.wired.com///')
    assert is_homepage_url('http://m.wired.com///')

    # Smarter homepage identification ("/en/", "/news/", ...)
    assert is_homepage_url('http://www.latimes.com/entertainment/')
    assert is_homepage_url('http://www.scidev.net/global/')
    assert is_homepage_url('http://abcnews.go.com/US')
    assert is_homepage_url('http://www.example.com/news/')
    assert is_homepage_url('http://www.france24.com/en/')
    assert is_homepage_url('http://www.france24.com/en/?altcast_code=0adb03a8a4')
    assert is_homepage_url('http://www.google.com/trends/explore')
    assert is_homepage_url('http://www.google.com/trends/explore#q=Ebola')
    assert is_homepage_url('http://www.nytimes.com/pages/todayspaper/')
    assert is_homepage_url('http://www.politico.com/playbook/')


# noinspection SpellCheckingInspection
def test_get_url_host():
    assert_raises(McGetURLHostException, get_url_host, None)
    assert get_url_host('http://www.nytimes.com/') == 'www.nytimes.com'
    assert get_url_host('http://obama:barack1@WHITEHOUSE.GOV/michelle.html') == 'whitehouse.gov'


# noinspection SpellCheckingInspection
def test_get_url_distinctive_domain():
    # FIXME - some resulting domains look funny, not sure if I can change them easily though
    assert get_url_distinctive_domain('http://www.nytimes.com/') == 'nytimes.com'
    assert get_url_distinctive_domain('http://cyber.law.harvard.edu/') == 'law.harvard'
    assert get_url_distinctive_domain('http://www.gazeta.ru/') == 'gazeta.ru'
    assert get_url_distinctive_domain('http://www.whitehouse.gov/'), 'www.whitehouse'
    assert get_url_distinctive_domain('http://info.info/') == 'info.info'
    assert get_url_distinctive_domain('http://blog.yesmeck.com/jquery-jsonview/') == 'yesmeck.com'
    assert get_url_distinctive_domain('http://status.livejournal.org/') == 'livejournal.org'

    # ".(gov|org|com).XX" exception
    assert get_url_distinctive_domain('http://www.stat.gov.lt/') == 'stat.gov.lt'

    # "wordpress.com|blogspot|..." exception
    assert get_url_distinctive_domain('https://en.blog.wordpress.com/') == 'en.blog.wordpress.com'


# noinspection SpellCheckingInspection
def test_meta_refresh_url_from_html():
    # No <meta http-equiv="refresh" />
    assert meta_refresh_url_from_html(html="""
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
    """, base_url='http://example.com/') is None

    # Basic HTML <meta http-equiv="refresh">
    assert meta_refresh_url_from_html(html="""
        <HTML>
        <HEAD>
            <TITLE>This is a test</TITLE>
            <META HTTP-EQUIV="content-type" CONTENT="text/html; charset=UTF-8">
            <META HTTP-EQUIV="refresh" CONTENT="0; URL=http://example.com/">
        </HEAD>
        <BODY>
            <P>This is a test.</P>
        </BODY>
        </HTML>
    """, base_url='http://example.com/') == 'http://example.com/'

    # Basic XHTML <meta http-equiv="refresh" />
    assert meta_refresh_url_from_html(html="""
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
            <meta http-equiv="refresh" content="0; url=http://example.com/" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
    """, base_url='http://example.com/') == 'http://example.com/'

    # Basic XHTML sans the seconds part
    assert meta_refresh_url_from_html(html="""
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
            <meta http-equiv="refresh" content="url=http://example.com/" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
    """, base_url='http://example.com/') == 'http://example.com/'

    # Basic XHTML with quoted url
    assert meta_refresh_url_from_html(html="""
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
            <meta http-equiv="refresh" content="url='http://example.com/'" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
    """, base_url='http://example.com/') == 'http://example.com/'

    # Basic XHTML with reverse quoted url
    assert meta_refresh_url_from_html(html="""
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
            <meta http-equiv="refresh" content='url="http://example.com/"' />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
    """, base_url='http://example.com/') == 'http://example.com/'

    # Relative path (base URL with trailing slash)
    assert meta_refresh_url_from_html(html="""
        <meta http-equiv="refresh" content="0; url=second/third/" />
    """, base_url='http://example.com/first/') == 'http://example.com/first/second/third/'

    # Relative path (base URL without trailing slash)
    assert meta_refresh_url_from_html(html="""
        <meta http-equiv="refresh" content="0; url=second/third/" />
    """, base_url='http://example.com/first') == 'http://example.com/second/third/'

    # Absolute path
    assert meta_refresh_url_from_html(html="""
        <meta http-equiv="refresh" content="0; url=/first/second/third/" />
    """, base_url='http://example.com/fourth/fifth/') == 'http://example.com/first/second/third/'

    # Invalid URL without base URL
    assert meta_refresh_url_from_html("""
        <meta http-equiv="refresh" content="0; url=/first/second/third/" />
    """) is None


# noinspection SpellCheckingInspection
def test_http_urls_in_string():
    # Basic test
    assert set(http_urls_in_string("""
        These are my favourite websites:
        * http://www.mediacloud.org/
        * http://cyber.law.harvard.edu/
        * about:blank
    """)) == {'http://www.mediacloud.org/', 'http://cyber.law.harvard.edu/'}

    # Duplicate URLs
    assert set(http_urls_in_string("""
        These are my favourite (duplicate) websites:
        * http://www.mediacloud.org/
        * http://www.mediacloud.org/
        * http://cyber.law.harvard.edu/
        * http://cyber.law.harvard.edu/
        * http://www.mediacloud.org/
        * http://www.mediacloud.org/
    """)) == {'http://www.mediacloud.org/', 'http://cyber.law.harvard.edu/'}

    # No http:// URLs
    assert set(http_urls_in_string("""
        This test text doesn't have any http:// URLs, only a ftp:// one:
        ftp://ftp.ubuntu.com/ubuntu/
    """)) == set()

    # Erroneous input
    assert_raises(McHTTPURLsInStringException, http_urls_in_string, None)


def test_get_url_path_fast():
    assert get_url_path_fast('http://www.example.com/a/b/c') == '/a/b/c'
    assert get_url_path_fast('not_an_url') == ''
