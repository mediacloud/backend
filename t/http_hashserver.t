use strict;

# test HTTP::HashServer

use English '-no_match_vars';

use Test::More tests => 9;

BEGIN
{
    use_ok( 'HTTP::HashServer' );
    use_ok( 'LWP::Simple' );
}

my $_port = 8899;

# verify that a request for the given page on the test server returnes the
# given content
sub test_page
{
    my ( $url, $expected_content ) = @_;

    my $content = LWP::Simple::get( $url );

    chomp( $content );

    is( $content, $expected_content, "test_page: $url" );
}

sub main
{
    my $hs = HTTP::HashServer->new( $_port, $pages );

    ok( $hs, 'hashserver object returned' );

    $hs->start();

    while ( my ( $path, $page ) = each( %{ $pages } ) )
    {
        my $expected_content = "page-$page->{ page_num } content";
        test_page( "http://localhost:$_port/$path", $expected_content );
        test_page( "http://127.0.0.1:$_port/$path", $expected_content );
    }

    test_page( "http://localhost:$_port/",          'home' );
    test_page( "http://localhost:$_port/foo",       'foo' );
    test_page( "http://localhost:$_port/bar",       'bar' );
    test_page( "http://localhost:$_port/foo-bar",   'bar' );
    test_page( "http://127.0.0.1:$_port/localhost", 'home' );
    test_page( "http://localhost:$_port/127-foo",   'foo' );

    $hs->stop();
}

main();
