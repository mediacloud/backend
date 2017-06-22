use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::NoWarnings;
use Test::Deep;
use Test::More tests => 5;

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
# * retries via ::Determined of specific HTTP status codes
# * retry timing via ::Determined, plus custom timing
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

    my $urls = [];
    foreach my $path ( keys %{ $pages } )
    {
        push( @{ $urls }, 'http://localhost:' . $TEST_HTTP_SERVER_PORT . $path );
    }

    my $ua        = MediaWords::Util::Web::UserAgent->new();
    my $responses = $ua->parallel_get( $urls );

    ok( $responses );
    ok( scalar( @{ $responses } ) == scalar( @{ $urls } ) );

    my $paths_and_contents = {};
    foreach my $response ( @{ $responses } )
    {
        my $path    = URI->new( $response->request->url )->path;
        my $content = $response->decoded_content;
        $paths_and_contents->{ $path } = $content;
    }

    cmp_deeply( $paths_and_contents, $pages );

    $hs->stop();
}

sub test_lwp_user_agent_retries()
{
    my $pages = {

        # Page that doesn't respond in time
        '/buggy-page' => {
            callback => sub {
                my ( $params, $cookies ) = @_;

                # Simulate read timeout
                sleep;
            }
        }
    };
    my $hs = MediaWords::Test::HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();

    my $ua = MediaWords::Util::Web::UserAgent->new();
    $ua->set_timeout( 2 );    # time-out really fast
    $ua->set_timing( '1,2,4' );

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

    test_parallel_get();
    test_lwp_user_agent_retries();
}

main();
