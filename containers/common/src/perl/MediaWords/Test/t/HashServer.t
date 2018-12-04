use strict;
use warnings;
use utf8;

use Test::More tests => 15;

use MediaWords::Util::Web;
use MediaWords::Test::URLs;

BEGIN
{
    use_ok( 'MediaWords::Test::HashServer' );
}

my $_port = 8899;

# verify that a request for the given page on the test server returns the
# given content
sub __test_page
{
    my ( $url, $expected_content ) = @_;

    my $ua      = MediaWords::Util::Web::UserAgent->new();
    my $content = $ua->get_string( $url );

    chomp( $content );

    is( $content, $expected_content, "test_page: $url" );
}

sub main
{
    my $pages = {
        '/'          => 'home',
        '/foo'       => 'foo',
        '/bar'       => '𝒃𝒂𝒓',                                        # UTF-8
        '/foo-bar'   => { redirect => '/bar' },
        '/localhost' => { redirect => "http://localhost:$_port/" },
        '/127-foo'   => { redirect => "http://127.0.0.1:$_port/foo" },
        '/auth'      => { auth => 'foo:bar', content => 'foo bar' },
        '/404'       => { content => 'not found', http_status_code => 404 },
        '/callback'  => {
            callback => sub {
                my ( $request ) = @_;

                my $params  = $request->query_params();
                my $cookies = $request->cookies();

                my $response = '';
                $response .= "HTTP/1.0 200 OK\r\n";
                $response .= "Content-Type: text/plain\r\n";
                $response .= "\r\n";
                $response .= "callback";
                return $response;
            }
        },
    };

    my $hs = MediaWords::Test::HashServer->new( $_port, $pages );

    ok( $hs, 'hashserver object returned' );

    is_urls( $hs->page_url( '/foo' ), "http://localhost:$_port/foo" );

    $hs->start();

    __test_page( "http://localhost:$_port/",          'home' );
    __test_page( "http://localhost:$_port/foo",       'foo' );
    __test_page( "http://localhost:$_port/bar",       '𝒃𝒂𝒓' );
    __test_page( "http://localhost:$_port/foo-bar",   '𝒃𝒂𝒓' );
    __test_page( "http://127.0.0.1:$_port/localhost", 'home' );
    __test_page( "http://localhost:$_port/127-foo",   'foo' );
    __test_page( "http://localhost:$_port/callback",  'callback' );

    my $ua = MediaWords::Util::Web::UserAgent->new();

    my $response_404 = $ua->get( "http://localhost:$_port/404" );
    ok( !$response_404->is_success, "404 response should not succeed" );
    is( $response_404->code, 404, "404 status line" );

    my $auth_url = "http://localhost:$_port/auth";

    my $content = $ua->get_string( $auth_url );
    is( $content, undef, 'fail auth / no auth' );

    my $request = MediaWords::Util::Web::UserAgent::Request->new( 'GET', $auth_url );
    $request->set_authorization_basic( 'foo', 'bar' );
    my $response = $ua->request( $request );
    is( $response->decoded_content, 'foo bar', 'pass auth' );

    $request = MediaWords::Util::Web::UserAgent::Request->new( 'GET', $auth_url );
    $request->set_authorization_basic( 'foo', 'foo' );
    $response = $ua->request( $request );

    is( $response->code, 401, 'fail auth / bad password' );

    $hs->stop();
}

main();
