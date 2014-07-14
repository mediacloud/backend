use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 14;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::URL' );
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

    test_meta_refresh_url_from_html();
    test_link_canonical_url_from_html();
}

main();
