use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 27;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::URL' );
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
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_normalize_url_lossy();
    test_get_url_domain();
    test_meta_refresh_url_from_html();
    test_link_canonical_url_from_html();
}

main();
