use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::NoWarnings;
use Test::Deep;
use Test::More tests => 45;

use HTTP::Status qw(:constants);
use Readonly;
use Data::Dumper;
use URI;
use URI::Escape;

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

sub test_get_follow_http_html_redirects_http()
{
    my $ua = MediaWords::Util::Web::UserAgent->new();

    eval { $ua->get_follow_http_html_redirects( undef ); };
    ok( $@, 'Undefined URL' );

    eval { $ua->get_follow_http_html_redirects( 'gopher://gopher.floodgap.com/0/v2/vstat' ); };
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

    my $hs = MediaWords::Test::HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    is( $response->request()->url(),  $TEST_HTTP_SERVER_URL . '/fifth', 'URL after HTTP redirects' );
    is( $response->decoded_content(), $pages->{ '/fifth' },             'Data after HTTP redirects' );
}

sub test_get_follow_http_html_redirects_nonexistent()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # Nonexistent URL ("/first")
    my $pages = {};

    my $hs = MediaWords::Test::HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    ok( !$response->is_success );
    is( $response->request()->url(), $starting_url, 'URL after unsuccessful HTTP redirects' );
}

sub test_get_follow_http_html_redirects_html()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # HTML redirects
    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
        '/second' => '<meta http-equiv="refresh" content="url=third" />',
        '/third'  => '<META HTTP-EQUIV="REFRESH" CONTENT="10; URL=/fourth" />',
        '/fourth' => '< meta content="url=fifth" http-equiv="refresh" >',
        '/fifth'  => 'Seems to be working too.'
    };

    my $hs = MediaWords::Test::HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    is( $response->request()->url(),  $TEST_HTTP_SERVER_URL . '/fifth', 'URL after HTML redirects' );
    is( $response->decoded_content(), $pages->{ '/fifth' },             'Data after HTML redirects' );
}

sub test_get_follow_http_html_redirects_http_loop()
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

    my $hs = MediaWords::Test::HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    is( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/second', 'URL after HTTP redirect loop' );
}

sub test_get_follow_http_html_redirects_html_loop()
{
    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/first';

    # HTML redirects
    my $pages = {
        '/first'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
        '/second' => '<meta http-equiv="refresh" content="0; URL=/third" />',
        '/third'  => '<meta http-equiv="refresh" content="0; URL=/second" />',
    };

    my $hs = MediaWords::Test::HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    is( $response->request()->url(), $TEST_HTTP_SERVER_URL . '/first', 'URL after HTML redirect loop' );
}

# Test if the subroutine acts nicely when the server decides to ensure that the
# client supports cookies (e.g.
# http://www.dailytelegraph.com.au/news/world/charlie-hebdo-attack-police-close-in-on-two-armed-massacre-suspects-as-manhunt-continues-across-france/story-fni0xs63-1227178925700)
sub test_get_follow_http_html_redirects_cookies()
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
                my ( $params, $cookies ) = @_;

                my $received_cookie = $cookies->{ $COOKIE_NAME };
                my $response        = '';

                if ( $received_cookie and $received_cookie eq $COOKIE_VALUE )
                {

                    TRACE "Cookie was set previously, showing page";

                    $response .= "HTTP/1.0 200 OK\r\n";
                    $response .= "$DEFAULT_HEADER\r\n";
                    $response .= "\r\n";
                    $response .= $TEST_CONTENT;

                }
                else
                {

                    TRACE "Setting cookie, redirecting to /check_cookie";

                    $response .= "HTTP/1.0 302 Moved Temporarily\r\n";
                    $response .= "$DEFAULT_HEADER\r\n";
                    $response .= "Location: /check_cookie\r\n";
                    $response .= "Set-Cookie: $COOKIE_NAME=$COOKIE_VALUE\r\n";
                    $response .= "\r\n";
                    $response .= "Redirecting to the cookie check page...";
                }

                return $response;
            }
        },

        '/check_cookie' => {
            callback => sub {

                my ( $params, $cookies ) = @_;

                my $received_cookie = $cookies->{ $COOKIE_NAME };
                my $response        = '';

                if ( $received_cookie and $received_cookie eq $COOKIE_VALUE )
                {

                    TRACE "Cookie was set previously, redirecting back to the initial page";

                    $response .= "HTTP/1.0 302 Moved Temporarily\r\n";
                    $response .= "$DEFAULT_HEADER\r\n";
                    $response .= "Location: $starting_url\r\n";
                    $response .= "\r\n";
                    $response .= "Cookie looks fine, redirecting you back to the article...";

                }
                else
                {

                    TRACE "Cookie wasn't found, redirecting you to the /no_cookies page...";

                    $response .= "HTTP/1.0 302 Moved Temporarily\r\n";
                    $response .= "$DEFAULT_HEADER\r\n";
                    $response .= "Location: /no_cookies\r\n";
                    $response .= "\r\n";
                    $response .= 'Cookie wasn\'t found, redirecting you to the "no cookies" page...';
                }

                return $response;
            }
        },
        '/no_cookies' => "No cookie support, go away, we don\'t like you."
    };

    my $hs = MediaWords::Test::HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    is( $response->request()->url(),  $starting_url, 'URL after HTTP redirects (cookie)' );
    is( $response->decoded_content(), $TEST_CONTENT, 'Data after HTTP redirects (cookie)' );
}

sub test_get_follow_http_html_redirects_previous_responses()
{
    # HTTP redirect
    sub _page_http_redirect($)
    {
        my $page = shift;

        return {
            callback => sub {
                my ( $params, $cookies ) = @_;

                my $response = '';
                $response .= "HTTP/1.0 302 Moved Temporarily\r\n";
                $response .= "Content-Type: text/plain; charset=UTF-8\r\n";
                $response .= "Location: $page\r\n";
                $response .= "\r\n";
                $response .= "Redirect to $page...";

                return $response;
            }
        };
    }

    # <meta> redirect
    sub _page_html_redirect($)
    {
        my $page = shift;

        return "<meta http-equiv='refresh' content='0; URL=$page' />";
    }

    # Various types of redirects mixed together to test setting previous()
    my $pages = {

        '/page_1' => _page_http_redirect( '/page_2' ),

        '/page_2' => _page_html_redirect( '/page_3' ),

        '/page_3' => _page_http_redirect( '/page_4' ),
        '/page_4' => _page_http_redirect( '/page_5' ),

        '/page_5' => _page_html_redirect( '/page_6' ),
        '/page_6' => _page_html_redirect( '/page_7' ),

        # Final page
        '/page_7' => 'Finally!',

    };

    Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $starting_url = $TEST_HTTP_SERVER_URL . '/page_1';

    my $hs = MediaWords::Test::HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get_follow_http_html_redirects( $starting_url );

    $hs->stop();

    ok( $response->is_success() );
    is( $response->decoded_content(), 'Finally!' );
    is( $response->request()->url(),  "$TEST_HTTP_SERVER_URL/page_7" );

    $response = $response->previous();
    ok( $response );
    ok( $response->request() );
    is( $response->request()->url(), "$TEST_HTTP_SERVER_URL/page_6" );

    $response = $response->previous();
    ok( $response );
    ok( $response->request() );
    is( $response->request()->url(), "$TEST_HTTP_SERVER_URL/page_5" );

    $response = $response->previous();
    ok( $response );
    ok( $response->request() );
    is( $response->request()->url(), "$TEST_HTTP_SERVER_URL/page_4" );

    $response = $response->previous();
    ok( $response );
    ok( $response->request() );
    is( $response->request()->url(), "$TEST_HTTP_SERVER_URL/page_3" );

    $response = $response->previous();
    ok( $response );
    ok( $response->request() );
    is( $response->request()->url(), "$TEST_HTTP_SERVER_URL/page_2" );

    $response = $response->previous();
    ok( $response );
    ok( $response->request() );
    is( $response->request()->url(), "$TEST_HTTP_SERVER_URL/page_1" );

    ok( !$response->previous() );
}

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

    test_get_follow_http_html_redirects_nonexistent();
    test_get_follow_http_html_redirects_http();
    test_get_follow_http_html_redirects_html();
    test_get_follow_http_html_redirects_http_loop();
    test_get_follow_http_html_redirects_html_loop();
    test_get_follow_http_html_redirects_cookies();
    test_get_follow_http_html_redirects_previous_responses();

    test_parallel_get();
    test_determined_retries();
}

main();
