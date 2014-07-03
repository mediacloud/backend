use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 5;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::URL' );
}

sub test_meta_refresh_url_from_html()
{
    my $html;
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
    $expected_url = undef;
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html ), $expected_url, 'No <meta http-equiv="refresh" />' );

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
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html ), $expected_url,
        'Basic HTML <meta http-equiv="refresh">' );

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
    $expected_url = 'http://example.com/';
    is( MediaWords::Util::URL::meta_refresh_url_from_html( $html ),
        $expected_url, 'Basic XHTML <meta http-equiv="refresh" />' );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_meta_refresh_url_from_html();
}

main();
