use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 91;

use Readonly;
use HTTP::HashServer;
use HTTP::Status qw(:constants);
use URI::Escape;
use Data::Dumper;

use MediaWords::Test::DB;

Readonly my $TEST_HTTP_SERVER_PORT => 9998;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::URL' );
}

sub test_is_http_url()
{
    is( MediaWords::Util::URL::is_http_url( undef ), 0, 'is_http_url() - undef' );
    is( MediaWords::Util::URL::is_http_url( 0 ),     0, 'is_http_url() - 0' );
    is( MediaWords::Util::URL::is_http_url( '' ),    0, 'is_http_url() - empty string' );

    is( MediaWords::Util::URL::is_http_url( 'abc' ), 0, 'is_http_url() - no scheme' );

    is( MediaWords::Util::URL::is_http_url( 'gopher://gopher.floodgap.com/0/v2/vstat' ), 0, 'is_http_url() - Gopher URL' );
    is( MediaWords::Util::URL::is_http_url( 'ftp://ftp.freebsd.org/pub/FreeBSD/' ),      0, 'is_http_url() - FTP URL' );

    is( MediaWords::Util::URL::is_http_url( 'http://cyber.law.harvard.edu/about' ), 1, 'is_http_url() - HTTP URL' );
    is( MediaWords::Util::URL::is_http_url( 'https://github.com/berkmancenter/mediacloud' ), 1,
        'is_http_url() - HTTPS URL' );
}

sub test_is_homepage_url()
{
    is( MediaWords::Util::URL::is_homepage_url( undef ), 0, 'is_homepage_url() - undef' );
    is( MediaWords::Util::URL::is_homepage_url( 0 ),     0, 'is_homepage_url() - 0' );
    is( MediaWords::Util::URL::is_homepage_url( '' ),    0, 'is_homepage_url() - empty string' );

    is( MediaWords::Util::URL::is_homepage_url( 'abc' ), 0, 'is_homepage_url() - no scheme' );

    is( MediaWords::Util::URL::is_homepage_url( 'http://www.wired.com' ),    1, 'is_homepage_url() - Wired' );
    is( MediaWords::Util::URL::is_homepage_url( 'http://www.wired.com/' ),   1, 'is_homepage_url() - Wired "/"' );
    is( MediaWords::Util::URL::is_homepage_url( 'http://m.wired.com/#abc' ), 1, 'is_homepage_url() - Wired "/#abc"' );

    is( MediaWords::Util::URL::is_homepage_url( 'http://m.wired.com/threatlevel/2011/12/sopa-watered-down-amendment/' ),
        0, 'is_homepage_url() - Wired article' );

    # Technically, server is not required to normalize "///" path into "/"
    is( MediaWords::Util::URL::is_homepage_url( 'http://www.wired.com///' ), 0, 'is_homepage_url() - Wired "///"' );
    is( MediaWords::Util::URL::is_homepage_url( 'http://m.wired.com///' ),   0, 'is_homepage_url() - m.Wired "///"' );

    # Treat #fragment as a potential part of the path
    Readonly my $treat_fragment_as_path => 1;
    is(
        MediaWords::Util::URL::is_homepage_url(
            'http://www.nbcnews.com/#/health/health-news/inside-ebola-clinic-doctors-fight-out-control-virus-%20n150391',
            $treat_fragment_as_path
        ),
        0,
        'is_homepage_url() - Treat fragment as path'
    );
}

sub test_normalize_url()
{
    # Bad URLs
    eval { MediaWords::Util::URL::normalize_url( undef ); };
    ok( $@, 'normalize_url() - undefined URL' );
    eval { MediaWords::Util::URL::normalize_url( 'url.com/without/scheme/' ); };
    ok( $@, 'normalize_url() - URL without scheme' );
    eval { MediaWords::Util::URL::normalize_url( 'gopher://gopher.floodgap.com/0/v2/vstat' ); };
    ok( $@, 'normalize_url() - URL is of unsupported scheme' );

    # Basic
    is(
        MediaWords::Util::URL::normalize_url( 'HTTP://CYBER.LAW.HARVARD.EDU/node/9244' ),
        'http://cyber.law.harvard.edu/node/9244',
        'normalize_url() - basic cyber.law.harvard.edu'
    );
    is(
        MediaWords::Util::URL::normalize_url(
'HTTP://WWW.GOCRICKET.COM/news/sourav-ganguly/Sourav-Ganguly-exclusive-MS-Dhoni-must-reinvent-himself-to-survive/articleshow_sg/40421328.cms?utm_source=facebook.com&utm_medium=referral'
        ),
'http://www.gocricket.com/news/sourav-ganguly/Sourav-Ganguly-exclusive-MS-Dhoni-must-reinvent-himself-to-survive/articleshow_sg/40421328.cms',
        'normalize_url() - basic gocricket.com'
    );
    is(
        MediaWords::Util::URL::normalize_url( 'HTTP://CYBER.LAW.HARVARD.EDU/node/9244#foo#bar' ),
        'http://cyber.law.harvard.edu/node/9244',
        'normalize_url() - basic cyber.law.harvard.edu (multiple fragments)'
    );

    # Broken URL
    is(
        MediaWords::Util::URL::normalize_url( 'http://http://www.al-monitor.com/pulse' ),
        'http://www.al-monitor.com/pulse',
        'normalize_url() - broken URL'
    );

    # Empty parameter
    is(
        MediaWords::Util::URL::normalize_url( 'http://www-nc.nytimes.com/2011/06/29/us/politics/29marriage.html?=_r%3D6' ),
        'http://www-nc.nytimes.com/2011/06/29/us/politics/29marriage.html',
        'normalize_url() - empty parameter'
    );

    # Remove whitespace
    is(
        MediaWords::Util::URL::normalize_url(
            '  http://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html  '
        ),
        'http://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html',
        'normalize_url() - remove spaces'
    );
    is(
        MediaWords::Util::URL::normalize_url(
            "\t\thttp://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html\t\t"
        ),
        'http://blogs.perl.org/users/domm/2010/11/posting-utf8-data-using-lwpuseragent.html',
        'normalize_url() - remove tabs'
    );

    # NYTimes
    is(
        MediaWords::Util::URL::normalize_url(
'http://boss.blogs.nytimes.com/2014/08/19/why-i-do-all-of-my-recruiting-through-linkedin/?smid=fb-nytimes&WT.z_sma=BU_WID_20140819&bicmp=AD&bicmlukp=WT.mc_id&bicmst=1388552400000&bicmet=1420088400000&_'
        ),
        'http://boss.blogs.nytimes.com/2014/08/19/why-i-do-all-of-my-recruiting-through-linkedin/',
        'normalize_url() - nytimes.com 1'
    );
    is(
        MediaWords::Util::URL::normalize_url(
'http://www.nytimes.com/2014/08/19/upshot/inequality-and-web-search-trends.html?smid=fb-nytimes&WT.z_sma=UP_IOA_20140819&bicmp=AD&bicmlukp=WT.mc_id&bicmst=1388552400000&bicmet=1420088400000&_r=1&abt=0002&abg=1'
        ),
        'http://www.nytimes.com/2014/08/19/upshot/inequality-and-web-search-trends.html',
        'normalize_url() - nytimes.com 2'
    );
    is(
        MediaWords::Util::URL::normalize_url(
'http://www.nytimes.com/2014/08/20/upshot/data-on-transfer-of-military-gear-to-police-departments.html?smid=fb-nytimes&WT.z_sma=UP_DOT_20140819&bicmp=AD&bicmlukp=WT.mc_id&bicmst=1388552400000&bicmet=1420088400000&_r=1&abt=0002&abg=1'
        ),
        'http://www.nytimes.com/2014/08/20/upshot/data-on-transfer-of-military-gear-to-police-departments.html',
        'normalize_url() - nytimes.com 3'
    );

    # Facebook
    is(
        MediaWords::Util::URL::normalize_url( 'https://www.facebook.com/BerkmanCenter?ref=br_tf' ),
        'https://www.facebook.com/BerkmanCenter',
        'normalize_url() - facebook.com'
    );

    # LiveJournal
    is(
        MediaWords::Util::URL::normalize_url( 'http://zyalt.livejournal.com/1178735.html?thread=396696687#t396696687' ),
        'http://zyalt.livejournal.com/1178735.html',
        'normalize_url() - livejournal.com'
    );
}

sub test_normalize_url_lossy()
{
    # FIXME - some resulting URLs look funny, not sure if I can change them easily though
    is(
        MediaWords::Util::URL::normalize_url_lossy( 'http://HTTP://WWW.nytimes.COM/ARTICLE/12345/?ab=cd#def#ghi/' ),
        'http://www.nytimes.com/article/12345/?ab=cd',
        'normalize_url_lossy() - nytimes.com'
    );
    is(
        MediaWords::Util::URL::normalize_url_lossy( 'http://http://www.al-monitor.com/pulse' ),
        'http://www.al-monitor.com/pulse',
        'normalize_url_lossy() - www.al-monitor.com'
    );
    is( MediaWords::Util::URL::normalize_url_lossy( 'http://m.delfi.lt/foo' ),
        'http://delfi.lt/foo', 'normalize_url_lossy() - m.delfi.lt' );
    is(
        MediaWords::Util::URL::normalize_url_lossy( 'http://blog.yesmeck.com/jquery-jsonview/' ),
        'http://yesmeck.com/jquery-jsonview',
        'normalize_url_lossy() - blog.yesmeck.com'
    );
    is(
        MediaWords::Util::URL::normalize_url_lossy( 'http://cdn.com.do/noticias/nacionales' ),
        'http://com.do/noticias/nacionales',
        'normalize_url_lossy() - cdn.com.do'
    );
    is( MediaWords::Util::URL::normalize_url_lossy( 'http://543.r2.ly' ),
        'http://543.r2.ly/', 'normalize_url_lossy() - r2.ly' );
}

sub test_get_url_domain()
{
    # FIXME - some resulting domains look funny, not sure if I can change them easily though
    is( MediaWords::Util::URL::get_url_domain( 'http://www.nytimes.com/' ), 'nytimes.com',
        'get_url_domain() - nytimes.com' );
    is( MediaWords::Util::URL::get_url_domain( 'http://cyber.law.harvard.edu/' ),
        'law.harvard', 'get_url_domain() - cyber.law.harvard.edu' );
    is( MediaWords::Util::URL::get_url_domain( 'http://www.gazeta.ru/' ), 'gazeta.ru', 'get_url_domain() - gazeta.ru' );
    is( MediaWords::Util::URL::get_url_domain( 'http://www.whitehouse.gov/' ),
        'www.whitehouse', 'get_url_domain() - www.whitehouse' );
    is( MediaWords::Util::URL::get_url_domain( 'http://info.info/' ), 'info.info', 'get_url_domain() - info.info' );
    is( MediaWords::Util::URL::get_url_domain( 'http://blog.yesmeck.com/jquery-jsonview/' ),
        'yesmeck.com', 'get_url_domain() - yesmeck.com' );
    is( MediaWords::Util::URL::get_url_domain( 'http://status.livejournal.org/' ),
        'livejournal.org', 'get_url_domain() - livejournal.org' );

    # ".(gov|org|com).XX" exception
    is( MediaWords::Util::URL::get_url_domain( 'http://www.stat.gov.lt/' ),
        'stat.gov.lt', 'get_url_domain() - www.stat.gov.lt' );

    # "wordpress.com|blogspot|livejournal.com|privet.ru|wikia.com|feedburner.com|24open.ru|patch.com|tumblr.com" exception
    is( MediaWords::Util::URL::get_url_domain( 'https://en.blog.wordpress.com/' ),
        'en.blog.wordpress.com', 'get_url_domain() - en.blog.wordpress.com' );

  # FIXME - invalid URL
  # is(MediaWords::Util::URL::get_url_domain('http:///www.facebook.com/'), undef, 'get_url_domain() - invalid facebook.com');
}

sub test_meta_refresh_url_from_html()
{
    my $html;
    my $base_url;
    my $expected_url;

    # No <meta http-equiv="refresh" />
    $html = <<EOF;
        <html>
        <head>
            <title>This is a test</title>
            <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
EOF
    $base_url     = 'http://example.com/';
    $expected_url = undef;
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'No <meta http-equiv="refresh" />' );

    # Basic HTML <meta http-equiv="refresh">
    $html = <<EOF;
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
EOF
    $base_url     = 'http://example.com/';
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'Basic HTML <meta http-equiv="refresh">' );

    # Basic XHTML <meta http-equiv="refresh" />
    $html = <<EOF;
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
EOF
    $base_url     = 'http://example.com/';
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'Basic XHTML <meta http-equiv="refresh" />' );

    # Basic XHTML sans the seconds part
    $html = <<EOF;
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
EOF
    $base_url     = 'http://example.com/';
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'Basic XHTML sans the seconds part' );

    # Relative path (base URL with trailing slash)
    $html = <<EOF;
        <meta http-equiv="refresh" content="0; url=second/third/" />
EOF
    $base_url     = 'http://example.com/first/';
    $expected_url = 'http://example.com/first/second/third/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'Relative path (with trailing slash)' );

    # Relative path (base URL without trailing slash)
    $html = <<EOF;
        <meta http-equiv="refresh" content="0; url=second/third/" />
EOF
    $base_url     = 'http://example.com/first';
    $expected_url = 'http://example.com/second/third/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ),
        $expected_url, 'Relative path (without trailing slash)' );

    # Absolute path
    $html = <<EOF;
        <meta http-equiv="refresh" content="0; url=/first/second/third/" />
EOF
    $base_url     = 'http://example.com/fourth/fifth/';
    $expected_url = 'http://example.com/first/second/third/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html, $base_url ), $expected_url, 'Absolute path' );

    # Invalid URL without base URL
    $html = <<EOF;
        <meta http-equiv="refresh" content="0; url=/first/second/third/" />
EOF
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html ), undef, 'Invalid URL without base URL' );
}

sub test_link_canonical_url_from_html()
{
    my $html;
    my $base_url;
    my $expected_url;

    # No <link rel="canonical" />
    $html = <<EOF;
        <html>
        <head>
            <title>This is a test</title>
            <link rel="stylesheet" type="text/css" href="theme.css" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
EOF
    $base_url     = 'http://example.com/';
    $expected_url = undef;
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html, $base_url ),
        $expected_url, 'No <link rel="canonical" />' );

    # Basic HTML <link rel="canonical">
    $html = <<EOF;
        <HTML>
        <HEAD>
            <TITLE>This is a test</TITLE>
            <LINK REL="stylesheet" TYPE="text/css" HREF="theme.css">
            <LINK REL="canonical" HREF="http://example.com/">
        </HEAD>
        <BODY>
            <P>This is a test.</P>
        </BODY>
        </HTML>
EOF
    $base_url     = 'http://example.com/';
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html, $base_url ),
        $expected_url, 'Basic HTML <link rel="canonical">' );

    # Basic XHTML <meta http-equiv="refresh" />
    $html = <<EOF;
        <html>
        <head>
            <title>This is a test</title>
            <link rel="stylesheet" type="text/css" href="theme.css" />
            <link rel="canonical" href="http://example.com/" />
        </head>
        <body>
            <p>This is a test.</p>
        </body>
        </html>
EOF
    $base_url     = 'http://example.com/';
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html, $base_url ),
        $expected_url, 'Basic XHTML <link rel="canonical" />' );

    # Relative path (base URL with trailing slash -- valid, but not a good practice)
    $html = <<EOF;
        <link rel="canonical" href="second/third/" />
EOF
    $base_url     = 'http://example.com/first/';
    $expected_url = 'http://example.com/first/second/third/';
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html, $base_url ),
        $expected_url, 'Relative path (with trailing slash)' );

    # Relative path (base URL without trailing slash -- valid, but not a good practice)
    $html = <<EOF;
        <link rel="canonical" href="second/third/" />
EOF
    $base_url     = 'http://example.com/first';
    $expected_url = 'http://example.com/second/third/';
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html, $base_url ),
        $expected_url, 'Relative path (without trailing slash)' );

    # Absolute path (valid, but not a good practice)
    $html = <<EOF;
        <link rel="canonical" href="/first/second/third/" />
EOF
    $base_url     = 'http://example.com/fourth/fifth/';
    $expected_url = 'http://example.com/first/second/third/';
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html, $base_url ), $expected_url, 'Absolute path' );

    # Invalid URL without base URL
    $html = <<EOF;
        <link rel="canonical" href="/first/second/third/" />
EOF
    is( MediaWords::Util::URL::link_canonical_url_from_html( $html ), undef, 'Invalid URL without base URL' );
}

sub test_url_and_data_after_redirects_http()
{
    eval { MediaWords::Util::URL::url_and_data_after_redirects( undef ); };
    ok( $@, 'Undefined URL' );

    eval { MediaWords::Util::URL::url_and_data_after_redirects( 'gopher://gopher.floodgap.com/0/v2/vstat' ); };
    ok( $@, 'Non-HTTP(S) URL' );

    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # HTTP redirects
    my $pages = {
        '/first'  => { redirect => '/second',                        http_status_code => HTTP_MOVED_PERMANENTLY },
        '/second' => { redirect => $TEST_HTTP_SERVER_URL . '/third', http_status_code => HTTP_FOUND },
        '/third'  => { redirect => '/fourth',                        http_status_code => HTTP_SEE_OTHER },
        '/fourth' => { redirect => $TEST_HTTP_SERVER_URL . '/fifth', http_status_code => HTTP_TEMPORARY_REDIRECT },
        '/fifth' => 'Seems to be working.'
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects,  $TEST_HTTP_SERVER_URL . '/fifth', 'URL after HTTP redirects' );
    is( $data_after_redirects, $pages->{ '/fifth' },             'Data after HTTP redirects' );
}

sub test_url_and_data_after_redirects_nonexistent()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # Nonexistent URL ("/first")
    my $pages = {};

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects,  $starting_url, 'URL after unsuccessful HTTP redirects' );
    is( $data_after_redirects, undef,         'Data after unsuccessful HTTP redirects' );
}

sub test_url_and_data_after_redirects_html()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';
    Readonly my $MAX_META_REDIRECTS => 7;    # instead of default 3

    # HTML redirects
    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
        '/second' => '<meta http-equiv="refresh" content="url=third" />',
        '/third'  => '<META HTTP-EQUIV="REFRESH" CONTENT="10; URL=/fourth" />',
        '/fourth' => '< meta content="url=fifth" http-equiv="refresh" >',
        '/fifth'  => 'Seems to be working too.'
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url, undef, $MAX_META_REDIRECTS );

    $hs->stop();

    is( $url_after_redirects,  $TEST_HTTP_SERVER_URL . '/fifth', 'URL after HTML redirects' );
    is( $data_after_redirects, $pages->{ '/fifth' },             'Data after HTML redirects' );
}

sub test_url_and_data_after_redirects_http_loop()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # "http://127.0.0.1:9998/third?url=http%3A%2F%2F127.0.0.1%2Fsecond"
    my $third = '/third?url=' . uri_escape( $TEST_HTTP_SERVER_URL . '/second' );

    # HTTP redirects
    my $pages = {

# e.g. http://rss.nytimes.com/c/34625/f/640350/s/3a08a24a/sc/1/l/0L0Snytimes0N0C20A140C0A50C0A40Cus0Cpolitics0Cobama0Ewhite0Ehouse0Ecorrespondents0Edinner0Bhtml0Dpartner0Frss0Gemc0Frss/story01.htm
        '/first' => { redirect => '/second', http_status_code => HTTP_SEE_OTHER },

        # e.g. http://www.nytimes.com/2014/05/04/us/politics/obama-white-house-correspondents-dinner.html?partner=rss&emc=rss
        '/second' => { redirect => $third, http_status_code => HTTP_SEE_OTHER },

# e.g. http://www.nytimes.com/glogin?URI=http%3A%2F%2Fwww.nytimes.com%2F2014%2F05%2F04%2Fus%2Fpolitics%2Fobama-white-house-correspondents-dinner.html%3Fpartner%3Drss%26emc%3Drss
        '/third' => { redirect => '/second', http_status_code => HTTP_SEE_OTHER }
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects, $TEST_HTTP_SERVER_URL . '/second', 'URL after HTTP redirect loop' );
}

sub test_url_and_data_after_redirects_html_loop()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # HTML redirects
    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/third" />',
        '/third'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects, $TEST_HTTP_SERVER_URL . '/second', 'URL after HTML redirect loop' );
}

# Test if the subroutine acts nicely when the server decides to ensure that the
# client supports cookies (e.g.
# http://www.dailytelegraph.com.au/news/world/charlie-hebdo-attack-police-close-in-on-two-armed-massacre-suspects-as-manhunt-continues-across-france/story-fni0xs63-1227178925700)
sub test_url_and_data_after_redirects_cookies()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';
    Readonly my $TEST_CONTENT => 'This is the content.';

    Readonly my $COOKIE_NAME    => "test_cookie";
    Readonly my $COOKIE_VALUE   => "I'm a cookie and I know it!";
    Readonly my $DEFAULT_HEADER => "Content-Type: text/html; charset=UTF-8";

    # HTTP redirects
    my $pages = {
        '/first' => {
            callback => sub {
                my ( $self, $cgi ) = @_;

                my $received_cookie = $cgi->cookie( $COOKIE_NAME );

                if ( $received_cookie and $received_cookie eq $COOKIE_VALUE )
                {

                    # say STDERR "Cookie was set previously, showing page";

                    print "HTTP/1.0 200 OK\r\n";
                    print "$DEFAULT_HEADER\r\n";
                    print "\r\n";
                    print $TEST_CONTENT;

                }
                else
                {

                    # say STDERR "Setting cookie, redirecting to /check_cookie";

                    print "HTTP/1.0 302 Moved Temporarily\r\n";
                    print "$DEFAULT_HEADER\r\n";
                    print "Location: /check_cookie\r\n";
                    print "Set-Cookie: $COOKIE_NAME=$COOKIE_VALUE\r\n";
                    print "\r\n";
                    print "Redirecting to the cookie check page...";
                }
            }
        },

        '/check_cookie' => {
            callback => sub {

                my ( $self, $cgi ) = @_;

                my $received_cookie = $cgi->cookie( $COOKIE_NAME );

                if ( $received_cookie and $received_cookie eq $COOKIE_VALUE )
                {

                    # say STDERR "Cookie was set previously, redirecting back to the initial page";

                    print "HTTP/1.0 302 Moved Temporarily\r\n";
                    print "$DEFAULT_HEADER\r\n";
                    print "Location: $starting_url\r\n";
                    print "\r\n";
                    print "Cookie looks fine, redirecting you back to the article...";

                }
                else
                {

                    # say STDERR 'Cookie wasn\'t found, redirecting you to the /no_cookies page...';

                    print "HTTP/1.0 302 Moved Temporarily\r\n";
                    print "$DEFAULT_HEADER\r\n";
                    print "Location: /no_cookies\r\n";
                    print "\r\n";
                    print 'Cookie wasn\'t found, redirecting you to the "no cookies" page...';
                }
            }
        },
        '/no_cookies' => "No cookie support, go away, we don\'t like you."
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my ( $url_after_redirects, $data_after_redirects ) =
      MediaWords::Util::URL::url_and_data_after_redirects( $starting_url );

    $hs->stop();

    is( $url_after_redirects,  $starting_url, 'URL after HTTP redirects (cookie)' );
    is( $data_after_redirects, $TEST_CONTENT, 'Data after HTTP redirects (cookie)' );
}

sub test_all_url_variants($)
{
    my ( $db ) = @_;

    my @actual_url_variants;
    my @expected_url_variants;

    # Undefined URL
    eval { MediaWords::Util::URL::all_url_variants( $db, undef ); };
    ok( $@, 'Undefined URL' );

    # Non-HTTP(S) URL
    Readonly my $gopher_url => 'gopher://gopher.floodgap.com/0/v2/vstat';
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $gopher_url );
    @expected_url_variants = ( $gopher_url );
    is_deeply( [ sort @actual_url_variants ], [ sort @expected_url_variants ], 'Non-HTTP(S) URL' );

    # Basic test
    Readonly my $TEST_HTTP_SERVER_URL       => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    Readonly my $starting_url_without_cruft => $TEST_HTTP_SERVER_URL . '/first';
    Readonly my $cruft                      => '?utm_source=A&utm_medium=B&utm_campaign=C';
    Readonly my $starting_url               => $starting_url_without_cruft . $cruft;

    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second' . $cruft . '" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/third' . $cruft . '" />',
        '/third'  => 'This is where the redirect chain should end.',
    };

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $starting_url );
    $hs->stop();

    @expected_url_variants = (
        $starting_url, $starting_url_without_cruft,
        $TEST_HTTP_SERVER_URL . '/third',
        $TEST_HTTP_SERVER_URL . '/third' . $cruft
    );
    is_deeply( [ sort @actual_url_variants ], [ sort @expected_url_variants ], 'Basic all_url_variants() test' );

    # <link rel="canonical" />
    $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second' . $cruft . '" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/third' . $cruft . '" />',
        '/third'  => '<link rel="canonical" href="' . $TEST_HTTP_SERVER_URL . '/fourth" />',
    };

    $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $starting_url );
    $hs->stop();

    @expected_url_variants = (
        $starting_url, $starting_url_without_cruft,
        $TEST_HTTP_SERVER_URL . '/third',
        $TEST_HTTP_SERVER_URL . '/third' . $cruft,
        $TEST_HTTP_SERVER_URL . '/fourth',
    );
    is_deeply(
        [ sort @actual_url_variants ],
        [ sort @expected_url_variants ],
        '<link rel="canonical" /> all_url_variants() test'
    );

    # Redirect to a homepage
    $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second' . $cruft . '" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/',
    };

    $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $starting_url );
    $hs->stop();

    @expected_url_variants = (
        $starting_url_without_cruft, $starting_url,
        $TEST_HTTP_SERVER_URL . '/second',
        $TEST_HTTP_SERVER_URL . '/second' . $cruft
    );
    is_deeply(
        [ sort @actual_url_variants ],
        [ sort @expected_url_variants ],
        '"Redirect to homepage" all_url_variants() test'
    );

    # Another redirect to a homepage
    Readonly my $nbc_url =>
      'http://www.nbcnews.com/#/health/health-news/inside-ebola-clinic-doctors-fight-out-control-virus-%20n150391';
    Readonly my $treat_fragment_as_path => 1;
    @actual_url_variants = MediaWords::Util::URL::all_url_variants( $db, $nbc_url, $treat_fragment_as_path );

    @expected_url_variants = ( $nbc_url );
    is_deeply(
        [ sort @actual_url_variants ],
        [ sort @expected_url_variants ],
        '"Redirect to homepage NBCNews.com" all_url_variants() test'
    );
}

sub test_get_controversy_url_variants
{
    my ( $db ) = @_;

    my $data = {
        A => {
            B => [ 1, 2, 3 ],
            C => [ 4, 5, 6 ]
        },
        D => { E => [ 7, 8, 9 ] }
    };

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, $data );

    my $story_1 = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 1 };
    my $story_2 = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 2 };
    my $story_3 = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 3 };

    $db->query( <<END, $story_2->{ stories_id }, $story_1->{ stories_id } );
insert into controversy_merged_stories_map ( source_stories_id, target_stories_id ) values( ?, ? )
END
    $db->query( <<END, $story_3->{ stories_id }, $story_2->{ stories_id } );
insert into controversy_merged_stories_map ( source_stories_id, target_stories_id ) values( ?, ? )
END

    my $tag_set = $db->create( 'tag_sets', { name => 'foo' } );

    my $controversy = {
        name                    => 'foo',
        pattern                 => 'foo',
        solr_seed_query         => 'foo',
        description             => 'foo',
        controversy_tag_sets_id => $tag_set->{ tag_sets_id }
    };
    $controversy = $db->create( 'controversies', $controversy );

    $db->create(
        'controversy_stories',
        {
            controversies_id => $controversy->{ controversies_id },
            stories_id       => $story_1->{ stories_id }
        }
    );

    $db->create(
        'controversy_links',
        {
            controversies_id => $controversy->{ controversies_id },
            stories_id       => $story_1->{ stories_id },
            url              => $story_1->{ url },
            redirect_url     => $story_1->{ url } . "/redirect_url"
        }
    );

    $db->create(
        'controversy_stories',
        {
            controversies_id => $controversy->{ controversies_id },
            stories_id       => $story_2->{ stories_id }
        }
    );

    $db->create(
        'controversy_links',
        {
            controversies_id => $controversy->{ controversies_id },
            stories_id       => $story_2->{ stories_id },
            url              => $story_2->{ url },
            redirect_url     => $story_2->{ url } . "/redirect_url"
        }
    );

    $db->create(
        'controversy_stories',
        {
            controversies_id => $controversy->{ controversies_id },
            stories_id       => $story_3->{ stories_id }
        }
    );

    $db->create(
        'controversy_links',
        {
            controversies_id => $controversy->{ controversies_id },
            stories_id       => $story_3->{ stories_id },
            url              => $story_3->{ url } . '/alternate',
        }
    );

    my $expected_urls = [
        $story_1->{ url },
        $story_2->{ url },
        $story_1->{ url } . "/redirect_url",
        $story_2->{ url } . "/redirect_url",
        $story_3->{ url },
        $story_3->{ url } . "/alternate"
    ];

    my $url_variants = MediaWords::Util::URL::get_controversy_url_variants( $db, $story_1->{ url } );

    $url_variants  = [ sort { $a cmp $b } @{ $url_variants } ];
    $expected_urls = [ sort { $a cmp $b } @{ $expected_urls } ];

    is(
        scalar( @{ $url_variants } ),
        scalar( @{ $expected_urls } ),
        'test_get_controversy_url_variants: same number variants'
    );

    for ( my $i = 0 ; $i < @{ $expected_urls } ; $i++ )
    {
        is( $url_variants->[ $i ], $expected_urls->[ $i ], 'test_get_controversy_url_variants: url variant match $i' );
    }
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_is_http_url();
    test_is_homepage_url();
    test_normalize_url();
    test_normalize_url_lossy();
    test_get_url_domain();
    test_meta_refresh_url_from_html();
    test_link_canonical_url_from_html();
    test_url_and_data_after_redirects_nonexistent();
    test_url_and_data_after_redirects_http();
    test_url_and_data_after_redirects_html();
    test_url_and_data_after_redirects_http_loop();
    test_url_and_data_after_redirects_html_loop();
    test_url_and_data_after_redirects_cookies();

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_all_url_variants( $db );
        }
    );

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_get_controversy_url_variants( $db );
        }
    );

}

main();
