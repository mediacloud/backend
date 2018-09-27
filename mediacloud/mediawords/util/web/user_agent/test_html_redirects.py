from mediawords.util.url import urls_are_equal
from mediawords.util.web.user_agent.html_redirects import (
    target_request_from_meta_refresh_url,
    target_request_from_archive_is_url,
    target_request_from_archive_org_url,
    target_request_from_linkis_com_url,
    target_request_from_alarabiya_url,
)


def test_target_request_from_meta_refresh_url():
    # <meta> refresh
    assert urls_are_equal(
        url1=target_request_from_meta_refresh_url(
            content="""
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
            """,
            archive_site_url='http://example2.com/'
        ).url(),
        url2='http://example.com/',
    )


def test_target_request_from_archive_is_url():
    # archive.is
    assert urls_are_equal(
        url1=target_request_from_archive_is_url(
            content="""
                <link rel="canonical" href="https://archive.is/20170201/https://bar.com/foo/bar">
            """,
            archive_site_url='https://archive.is/20170201/https://bar.com/foo/bar'
        ).url(),
        url2='https://bar.com/foo/bar',
    )

    # archive.is with non-matching URL
    assert target_request_from_archive_is_url(
        content="""
            <link rel="canonical" href="https://archive.is/20170201/https://bar.com/foo/bar">
        """,
        archive_site_url='https://bar.com/foo/bar'
    ) is None


def test_target_request_from_archive_org_url():
    # archive.org
    assert urls_are_equal(
        url1=target_request_from_archive_org_url(
            content=None,
            archive_site_url='https://web.archive.org/web/20150204024130/http://www.john-daly.com/hockey/hockey.htm'
        ).url(),
        url2='http://www.john-daly.com/hockey/hockey.htm',
    )

    # archive.org with non-matching URL
    assert target_request_from_archive_org_url(
        content=None,
        archive_site_url='http://www.john-daly.com/hockey/hockey.htm'
    ) is None


def test_target_request_from_linkis_com_url():
    # linkis.com <meta>
    assert urls_are_equal(
        url1=target_request_from_linkis_com_url(
            content='<meta property="og:url" content="http://og.url/test"',
            archive_site_url='https://linkis.com/foo.com/ASDF'
        ).url(),
        url2='http://og.url/test',
    )

    # linkis.com YouTube
    assert urls_are_equal(
        url1=target_request_from_linkis_com_url(
            content='<a class="js-youtube-ln-event" href="http://you.tube/test"',
            archive_site_url='https://linkis.com/foo.com/ASDF'
        ).url(),
        url2='http://you.tube/test',
    )

    # 'linkis.com <iframe>'
    assert urls_are_equal(
        url1=target_request_from_linkis_com_url(
            content='<iframe id="source_site" src="http://source.site/test"',
            archive_site_url='https://linkis.com/foo.com/ASDF'
        ).url(),
        url2='http://source.site/test',
    )

    # linkis.com JavaScript
    assert urls_are_equal(
        url1=target_request_from_linkis_com_url(
            content=r'"longUrl":"http:\/\/java.script\/test"',
            archive_site_url='https://linkis.com/foo.com/ASDF'
        ).url(),
        url2='http://java.script/test',
    )

    # linkis.com with non-matching URL
    assert target_request_from_linkis_com_url(
        content='<meta property="og:url" content="http://og.url/test"',
        archive_site_url='https://bar.com/foo/bar'
    ) is None


def test_target_request_from_alarabiya_url():
    # Alarabiya URL
    test_cookie_name = 'YPF8827340282Jdskjhfiw_928937459182JAX666'
    test_cookie_value = '78.60.231.222'
    test_content = """

        <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
        <html>
        <head>
        <meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">
        <meta http-equiv="Content-Script-Type" content="text/javascript">
        <script type="text/javascript">

        // ...

        setCookie('%(cookie_name)s', '%(cookie_value)s', 10);

        // ...

        </script>
        </head>
        <body>
        <noscript>This site requires JavaScript and Cookies to be enabled. Please change your browser settings or
        upgrade your browser.</noscript>
        </body>
        </html>

    """ % {'cookie_name': test_cookie_name, 'cookie_value': test_cookie_value}

    test_url = ('https://english.alarabiya.net/en/News/middle-east/2017/07/21/Israel-bars-Muslim-men-under-50-from-'
                'entering-Al-Aqsa-for-Friday-prayers.html')

    test_target_request = target_request_from_alarabiya_url(content=test_content, archive_site_url=test_url)

    assert urls_are_equal(url1=test_target_request.url(), url2=test_url)
    assert test_target_request.header('Cookie') == "%s=%s" % (test_cookie_name, test_cookie_value,)

    # Non-Alarabiya URL
    assert target_request_from_alarabiya_url(
        content=test_content,
        archive_site_url='http://some-other-url.com/'
    ) is None
