use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::NoWarnings;
use Test::Deep;
use Test::More tests => 11;

use Readonly;
use Data::Dumper;
use URI;

use MediaWords::Util::Web;
use MediaWords::Test::HTTP::HashServer;

my Readonly $TEST_HTTP_SERVER_PORT = 9998;
my Readonly $TEST_HTTP_SERVER_URL  = 'http://localhost:' . $TEST_HTTP_SERVER_PORT;

# FIXME things to test:
#
# * max. download size
# * max. redirects
# * User-Agent: header
# * From: header
# * UTF-8 response
# * non-UTF-8 response
# * invalid encoding
# * timeouts
# * custom before / after determined callbacks
# * max. redirects
# * whether or not cookies are being stored between redirects
# * blacklisted URLs
# * HTTP request log in data/logs/
# * GET
# * POST
# * request(): custom METHOD
# * request(): custom headers
# * request(): custom content type
# * request(): custom content (POST data) -- both hashref and string
# * request(): authorization
# * response: HTTP status code, message, status line
# * response: HTTP headers
# * response: content type
# * response: decoded content (UTF-8, non-UTF-8, and invalid UTF-8)
# * response: successful and unsuccessful responses
# * response: redirects and previous
# * response: get original request
# * response: errors on client/server side
# * get_string()

sub test_parallel_get()
{
    my $pages = {

        # Test UTF-8 while we're at it
        '/a' => '𝘛𝘩𝘪𝘴 𝘪𝘴 𝘱𝘢𝘨𝘦 𝘈.',    #
        '/b' => '𝕿𝖍𝖎𝖘 𝖎𝖘 𝖕𝖆𝖌𝖊 𝕭.',    #
        '/c' => '𝕋𝕙𝕚𝕤 𝕚𝕤 𝕡𝕒𝕘𝕖 ℂ.',     #
    };
    my $hs = MediaWords::Test::HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $base_url = 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $urls     = [
        "$base_url/a",
        "$base_url/b",
        "$base_url/c",
        "$base_url/does-not-exist",                                    # does not exist
    ];

    my $ua        = MediaWords::Util::Web::UserAgent->new();
    my $responses = $ua->parallel_get( $urls );

    ok( $responses );
    ok( scalar( @{ $responses } ) == scalar( @{ $urls } ) );

    my $path_responses = {};
    foreach my $response ( @{ $responses } )
    {
        my $path = URI->new( $response->request->url )->path;
        $path_responses->{ $path } = $response;
    }

    is( $path_responses->{ '/a' }->decoded_content, $pages->{ '/a' } );
    is( $path_responses->{ '/b' }->decoded_content, $pages->{ '/b' } );
    is( $path_responses->{ '/c' }->decoded_content, $pages->{ '/c' } );
    ok( !$path_responses->{ '/does-not-exist' }->is_success );
    is( $path_responses->{ '/does-not-exist' }->code, 404 );

    $hs->stop();
}

sub test_determined_retries()
{
    my $temporarily_buggy_page_request_count = 0;    # times the request has failed

    my $pages = {

        # Page that doesn't work the first two times
        '/temporarily-buggy-page' => {
            callback => sub {
                my ( $params, $cookies ) = @_;

                my $response = '';

                ++$temporarily_buggy_page_request_count;
                if ( $temporarily_buggy_page_request_count < 3 )
                {

                    say STDERR "Simulating failure for $temporarily_buggy_page_request_count time...";
                    $response .= "HTTP/1.0 500 Internal Server Error\r\n";
                    $response .= "Content-Type: text/plain\r\n";
                    $response .= "\r\n";
                    $response .= "something's wrong";

                }
                else
                {

                    say STDERR "Returning successful request...";
                    $response .= "HTTP/1.0 200 OK\r\n";
                    $response .= "Content-Type: text/plain\r\n";
                    $response .= "\r\n";
                    $response .= "success on request $temporarily_buggy_page_request_count";
                }

                return $response;

            }
        },

        # Page that doesn't work at all
        '/permanently-buggy-page' => {
            callback => sub {
                my ( $params, $cookies ) = @_;

                my $response = '';
                $response .= "HTTP/1.0 500 Internal Server Error\r\n";
                $response .= "Content-Type: text/plain\r\n";
                $response .= "\r\n";
                $response .= "something's wrong";

                return $response;

            }
        },

    };
    my $hs = MediaWords::Test::HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();

    my $ua = MediaWords::Util::Web::UserAgent->new();
    $ua->set_timeout( 2 );    # time-out really fast
    $ua->set_timing( '1,2,4' );

    {
        my $response = $ua->get( $TEST_HTTP_SERVER_URL . '/temporarily-buggy-page' );
        ok( $response->is_success, 'Request should ultimately succeed' );
        is( $response->decoded_content, "success on request 3" );
    }

    {
        my $response = $ua->get( $TEST_HTTP_SERVER_URL . '/permanently-buggy-page' );
        ok( !$response->is_success, 'Request should fail' );
    }

    $hs->stop();
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_parallel_get();
    test_determined_retries();
}

main();
