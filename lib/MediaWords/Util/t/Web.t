use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::Deep;
use Test::More tests => 8;

use Readonly;
use Data::Dumper;
use HTTP::HashServer;
use HTTP::Response;

use MediaWords::Util::Web;

my Readonly $TEST_HTTP_SERVER_PORT = 9998;
my Readonly $TEST_HTTP_SERVER_URL  = 'http://localhost:' . $TEST_HTTP_SERVER_PORT;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::Web' );
}

sub test_get_meta_redirect_response()
{
    my $label = "test_get_meta_redirect_response";

    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, { '/foo' => 'foo bar' } );
    $hs->start;

    my $redirect_url = "http://localhost:$TEST_HTTP_SERVER_PORT/foo";
    my $original_url = "http://foo.bar";

    my $meta_tag = '<meta http-equiv="refresh" content="0;URL=\'' . $redirect_url . '\'" />';
    my $response =
      MediaWords::Util::Web::UserAgent::Response->new_from_http_response( HTTP::Response->new( 200, 'OK', [], $meta_tag ) );
    $response->request( MediaWords::Util::Web::UserAgent::Request->new( 'GET', $original_url ) );

    my $got_response = MediaWords::Util::Web::get_meta_redirect_response( $response, $original_url );

    ok( $got_response->is_success, "$label meta response succeeded" );

    is( $got_response->decoded_content, 'foo bar', "label redirected content" );

    # check that the response for the meta refresh redirected page got added to the end of the response chain
    is( $got_response->request->uri->as_string,           $redirect_url, "$label end url of response chain" );
    is( $got_response->previous->request->uri->as_string, $original_url, "$label previous url in response chain" );

    $hs->stop;

    $response =
      MediaWords::Util::Web::UserAgent::Response->new_from_http_response(
        HTTP::Response->new( 200, 'OK', [], 'no meta refresh' ) );
    $got_response = MediaWords::Util::Web::get_meta_redirect_response( $response, $original_url );

    is( $got_response, $response, "$label no meta same response" );

}

sub test_lwp_user_agent_retries()
{
    my $pages = {

        # Page that doesn't respond in time
        '/buggy-page' => {
            callback => sub {
                my ( $self, $cgi ) = @_;
                print "HTTP/1.0 200 OK\r\n";
                print "Content-Type: text/plain\r\n";
                print "\r\n";

                # Simulate read timeout
                sleep;
            }
        }
    };
    my $hs = HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();

    my $ua = MediaWords::Util::Web::user_agent();
    $ua->timeout( 2 );    # time-out really fast
    $ua->timing( '1,2,4' );

    my $response = $ua->get( $TEST_HTTP_SERVER_URL . '/buggy-page' );
    ok( !$response->is_success, 'Request should fail' );
    $response->decoded_content;

    $hs->stop();
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_get_meta_redirect_response();
    test_lwp_user_agent_retries();
}

main();
